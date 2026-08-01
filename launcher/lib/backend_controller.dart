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

  Future<void> loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    backendPath = prefs.getString(_prefsBackendPath) ?? await _guessBackendPath();
    hostedUrl = prefs.getString(_prefsHostedUrl) ?? '';
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

  Future<void> start() async {
    if (status == BackendStatus.running || isBusy) return;

    final entry = File('$backendPath/src/index.js');
    if (backendPath.trim().isEmpty || !await entry.exists()) {
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
      final process = await Process.start(
        'node',
        ['src/index.js'],
        workingDirectory: backendPath,
        runInShell: false,
      );
      _process = process;

      process.stdout.transform(utf8.decoder).transform(const LineSplitter()).listen(_log);
      process.stderr.transform(utf8.decoder).transform(const LineSplitter()).listen(_log);

      unawaited(process.exitCode.then((code) {
        _process = null;
        _stopHealthPolling();
        if (status != BackendStatus.stopping) {
          // Process died on its own (crash, port conflict, etc).
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
    } on ProcessException catch (e) {
      lastError = 'Could not launch node: ${e.message}. Is Node.js installed and on PATH?';
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

    process.kill(ProcessSignal.sigterm);
    final exited = await process.exitCode
        .timeout(const Duration(seconds: 5), onTimeout: () {
      _log('… still running after 5s, forcing kill.');
      process.kill(ProcessSignal.sigkill);
      return -9;
    });
    _log('Backend stopped (exit code $exited).');
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
