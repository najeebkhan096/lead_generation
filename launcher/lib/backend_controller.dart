import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum BackendStatus { stopped, starting, running, stopping, error }

const _prefsBackendPath = 'backend_path';
const _prefsHostedUrl = 'hosted_url';
const _maxLogLines = 2000;

/// Starts, stops, and health-checks the backend's `node src/index.js`
/// process (the same thing `npm start` in backend/ runs), so the user never
/// has to open a terminal or an IDE to bring the local API server up.
class BackendController extends ChangeNotifier {
  Process? _process;
  Timer? _healthTimer;

  BackendStatus status = BackendStatus.stopped;
  String? lastError;
  String backendPath = '';
  String hostedUrl = '';
  bool healthOk = false;
  final List<String> logLines = [];

  static const int port = 3001;
  Uri get healthUri => Uri.parse('http://localhost:$port/api/health');

  /// This project's Firebase Hosting URL — known ahead of time, so the
  /// "Hosted frontend" field is pre-filled instead of requiring manual entry.
  /// Still overridable (e.g. once a Render backend URL exists) and whatever
  /// is chosen is persisted.
  static const defaultHostedUrl = 'https://whatsapplead-a8d9a.web.app';

  Future<void> loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    backendPath = prefs.getString(_prefsBackendPath) ?? await _guessBackendPath();
    hostedUrl = prefs.getString(_prefsHostedUrl) ?? defaultHostedUrl;
    notifyListeners();
  }

  /// Best-effort default: this repo's `backend/` folder next to `launcher/`.
  Future<String> _guessBackendPath() async {
    final candidate = Directory.current.parent.uri.resolve('backend/').toFilePath();
    if (await Directory(candidate).exists()) return candidate;
    return '';
  }

  Future<void> setBackendPath(String path) async {
    backendPath = path;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsBackendPath, path);
    notifyListeners();
  }

  Future<void> setHostedUrl(String url) async {
    hostedUrl = url;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsHostedUrl, url);
    notifyListeners();
  }

  void _log(String line) {
    logLines.add(line);
    if (logLines.length > _maxLogLines) {
      logLines.removeRange(0, logLines.length - _maxLogLines);
    }
    notifyListeners();
  }

  void clearLog() {
    logLines.clear();
    notifyListeners();
  }

  bool get isBusy =>
      status == BackendStatus.starting || status == BackendStatus.stopping;

  Future<bool> _isCommandAvailable(String command) async {
    try {
      final result = await Process.run(command, ['--version'], runInShell: true);
      return result.exitCode == 0;
    } catch (_) {
      return false;
    }
  }

  Future<void> start() async {
    if (status == BackendStatus.running || isBusy) return;

    if (backendPath.trim().isEmpty) {
      lastError = 'No backend folder selected. Pick the backend folder first.';
      status = BackendStatus.error;
      notifyListeners();
      return;
    }

    final dir = Directory(backendPath);
    if (!await dir.exists()) {
      lastError = 'Directory does not exist: $backendPath';
      status = BackendStatus.error;
      notifyListeners();
      return;
    }

    final entry = File('$backendPath/src/index.js');
    if (!await entry.exists()) {
      lastError = 'Can\'t find src/index.js in "$backendPath". Pick the correct backend folder.';
      status = BackendStatus.error;
      notifyListeners();
      return;
    }

    status = BackendStatus.starting;
    lastError = null;
    notifyListeners();
    _log('▶ Starting node src/index.js in $backendPath …');

    try {
      // Try common paths for node on macOS if 'node' in shell fails
      String nodeCommand = 'node';
      if (!await _isCommandAvailable('node')) {
        const commonPaths = [
          '/opt/homebrew/bin/node',
          '/usr/local/bin/node',
          '/usr/bin/node',
        ];
        for (final path in commonPaths) {
          if (await File(path).exists()) {
            nodeCommand = path;
            break;
          }
        }
      }

      // Not runInShell: nodeCommand is already an absolute path when PATH
      // lookup fails, and running the long-lived server directly (rather
      // than as a child of a wrapper shell) means Stop's kill() reliably
      // targets the actual node process instead of possibly just the shell.
      //
      // --max-old-space-size: a multi-hour multi-category scan holds a
      // shared Playwright browser open the whole time, and V8's default old
      // -space ceiling (~4GB on this machine) was observed being hit mid
      // -scan, crashing the entire job. Raised well above that so a long
      // scan has real headroom instead of dying hours in.
      final process = await Process.start(
        nodeCommand,
        ['--max-old-space-size=8192', 'src/index.js'],
        workingDirectory: backendPath,
      );
      _process = process;

      process.stdout.transform(utf8.decoder).transform(const LineSplitter()).listen(_log);
      process.stderr.transform(utf8.decoder).transform(const LineSplitter()).listen(_log);

      unawaited(process.exitCode.then((code) {
        _process = null;
        _stopHealthPolling();
        if (status != BackendStatus.stopping) {
          lastError = 'Backend exited unexpectedly (code $code).';
          status = BackendStatus.error;
        } else {
          status = BackendStatus.stopped;
        }
        healthOk = false;
        notifyListeners();
      }));

      status = BackendStatus.running;
      notifyListeners();
      _startHealthPolling();
    } catch (e) {
      _log('❌ Error: $e');
      lastError = 'Could not launch node: $e. Make sure Node.js is installed.';
      status = BackendStatus.error;
      notifyListeners();
    }
  }

  Future<void> stop() async {
    final process = _process;
    if (process == null) {
      status = BackendStatus.stopped;
      notifyListeners();
      return;
    }

    status = BackendStatus.stopping;
    notifyListeners();
    _log('■ Stopping backend…');

    try {
      process.kill(ProcessSignal.sigterm);
      final exited = await process.exitCode.timeout(
        const Duration(seconds: 5),
        onTimeout: () {
          _log('… still running after 5s, forcing kill.');
          process.kill(ProcessSignal.sigkill);
          return -9;
        },
      );
      _log('Backend stopped (exit code $exited).');
    } catch (e) {
      _log('❌ Error while stopping: $e');
    }
    // The exitCode listener registered in start() sets status/healthOk once
    // the process actually exits; nothing further to do here.
  }

  void _startHealthPolling() {
    _healthTimer?.cancel();
    _healthTimer = Timer.periodic(const Duration(seconds: 3), (_) => _checkHealth());
    _checkHealth();
  }

  void _stopHealthPolling() {
    _healthTimer?.cancel();
    _healthTimer = null;
  }

  Future<void> _checkHealth() async {
    if (status != BackendStatus.running) return;
    try {
      final client = HttpClient()..connectionTimeout = const Duration(seconds: 2);
      final request = await client.getUrl(healthUri);
      final response = await request.close();
      await response.drain<void>();
      client.close();
      final ok = response.statusCode == 200;
      if (ok != healthOk) {
        healthOk = ok;
        notifyListeners();
      }
    } catch (_) {
      if (healthOk) {
        healthOk = false;
        notifyListeners();
      }
    }
  }

  @override
  void dispose() {
    _stopHealthPolling();
    _process?.kill(ProcessSignal.sigterm);
    super.dispose();
  }
}
