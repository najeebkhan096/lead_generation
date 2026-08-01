import 'dart:async';
import 'dart:developer' as developer;
import 'dart:io';

import 'package:flutter/material.dart';

import 'home_page.dart';

/// Appends to ~/Library/Application Support/BackendLauncher/crash.log so
/// there's hard evidence to inspect even when the app is launched standalone
/// (double-clicked, no debugger attached — `developer.log` alone goes nowhere
/// visible in that case).
void _logToFile(String label, Object error, StackTrace? stack) {
  try {
    final home = Platform.environment['HOME'];
    if (home == null) return;
    final dir = Directory('$home/Library/Application Support/BackendLauncher');
    dir.createSync(recursive: true);
    final file = File('${dir.path}/crash.log');
    file.writeAsStringSync(
      '[${DateTime.now().toIso8601String()}] $label: $error\n${stack ?? ''}\n\n',
      mode: FileMode.append,
    );
  } catch (_) {
    // Best-effort only — never let logging itself throw.
  }
}

void main() {
  // A crash-safety net: any uncaught error anywhere (an unawaited Future
  // rejecting, a stray exception in a callback, etc.) gets logged instead
  // of silently taking down the whole app.
  FlutterError.onError = (details) {
    FlutterError.presentError(details);
    developer.log('FlutterError', error: details.exception, stackTrace: details.stack);
    _logToFile('FlutterError', details.exception, details.stack);
  };

  runZonedGuarded(
    () => runApp(const LauncherApp()),
    (error, stack) {
      developer.log('Uncaught zone error', error: error, stackTrace: stack);
      _logToFile('Uncaught zone error', error, stack);
    },
  );
}

class LauncherApp extends StatelessWidget {
  const LauncherApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Backend Launcher',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF0F766E),
          brightness: Brightness.light,
        ),
      ),
      home: const HomePage(),
    );
  }
}
