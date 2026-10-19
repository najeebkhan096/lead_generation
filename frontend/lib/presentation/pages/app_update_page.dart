import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../core/theme/app_theme.dart';
import '../../domain/entities/app_update_config.dart';
import '../../domain/repositories/lead_repository.dart';

/// Controls the Android app update: the minimum build the phones may run, the
/// latest build, the message, and the APK they download. Saving the rule takes
/// effect on the phones the next time they start the app.
class AppUpdatePage extends StatefulWidget {
  const AppUpdatePage({super.key});

  @override
  State<AppUpdatePage> createState() => _AppUpdatePageState();
}

class _AppUpdatePageState extends State<AppUpdatePage> {
  AppUpdateConfig? _config;
  bool _loading = true;
  String? _error;

  final _minBuild = TextEditingController();
  final _latestBuild = TextEditingController();
  final _message = TextEditingController();
  final _uploadBuild = TextEditingController();

  bool _saving = false;
  bool _uploading = false;
  PlatformFile? _apk;

  LeadRepository get _repo => context.read<LeadRepository>();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _minBuild.dispose();
    _latestBuild.dispose();
    _message.dispose();
    _uploadBuild.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final config = await _repo.getAppUpdateConfig();
      if (!mounted) return;
      setState(() {
        _config = config;
        _loading = false;
        _minBuild.text = '${config.minBuild}';
        _latestBuild.text = '${config.latestBuild}';
        _message.text = config.message;
        _uploadBuild.text = '${config.latestBuild + 1}';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  void _showMessage(String text) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _saveRule() async {
    final min = int.tryParse(_minBuild.text.trim());
    final latest = int.tryParse(_latestBuild.text.trim());
    if (min == null || min < 0 || latest == null || latest < 0) {
      _showMessage('Builds must be whole numbers, 0 or more.');
      return;
    }
    if (latest < min) {
      _showMessage('The latest build cannot be lower than the minimum.');
      return;
    }
    setState(() => _saving = true);
    try {
      final config = await _repo.saveAppUpdateRule(minBuild: min, latestBuild: latest, message: _message.text.trim());
      if (!mounted) return;
      setState(() {
        _config = config;
        _saving = false;
      });
      _showMessage('Update rule saved. Phones below build $min will be asked to update.');
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      _showMessage(e.toString().replaceFirst('Exception: ', ''));
    }
  }

  Future<void> _pickApk() async {
    final result = await FilePicker.pickFiles(type: FileType.custom, allowedExtensions: ['apk'], withData: true);
    final file = result?.files.single;
    if (file == null) return;
    if (file.bytes == null) {
      _showMessage('Could not read that file. Pick the APK again.');
      return;
    }
    setState(() => _apk = file);
  }

  Future<void> _uploadApk() async {
    final apk = _apk;
    final bytes = apk?.bytes;
    final build = int.tryParse(_uploadBuild.text.trim());
    if (apk == null || bytes == null) {
      _showMessage('Pick the APK file first.');
      return;
    }
    if (build == null || build < 1) {
      _showMessage('Enter the APK\'s build number, 1 or more.');
      return;
    }
    setState(() => _uploading = true);
    try {
      final config = await _repo.uploadAppApk(Uint8List.fromList(bytes), buildNumber: build);
      if (!mounted) return;
      setState(() {
        _config = config;
        _latestBuild.text = '${config.latestBuild}';
        _uploadBuild.text = '${config.latestBuild + 1}';
        _apk = null;
        _uploading = false;
      });
      _showMessage('APK uploaded as build $build. The download link is updated.');
    } catch (e) {
      if (!mounted) return;
      setState(() => _uploading = false);
      _showMessage(e.toString().replaceFirst('Exception: ', ''));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('App update'),
        actions: [
          IconButton(
            onPressed: _loading ? null : _load,
            icon: const Icon(AppIcons.refresh, size: 18),
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: _body(context),
          ),
        ),
      ),
    );
  }

  Widget _body(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(_error!, style: const TextStyle(color: AppTheme.danger), textAlign: TextAlign.center),
              const SizedBox(height: 12),
              OutlinedButton.icon(onPressed: _load, icon: const Icon(AppIcons.refresh, size: 18), label: const Text('Retry')),
            ],
          ),
        ),
      );
    }
    final config = _config!;
    final text = Theme.of(context).textTheme;

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 40),
      children: [
        _Card(
          title: 'Current rule',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _Row(label: 'Minimum build allowed', value: config.minBuild == 0 ? 'Not set' : '${config.minBuild}'),
              _Row(label: 'Latest build', value: config.latestBuild == 0 ? 'None yet' : '${config.latestBuild}'),
              _Row(label: 'Message', value: config.message.isEmpty ? 'Default message' : config.message),
              _Row(label: 'Download link', value: config.apkUrl.isEmpty ? 'No APK uploaded yet' : config.apkUrl),
              _Row(label: 'Last changed', value: config.updatedAt == null ? '—' : config.updatedAt!.toString().substring(0, 16)),
            ],
          ),
        ),
        const SizedBox(height: 16),
        _Card(
          title: 'Upload the new APK',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Build the release APK, then upload it here. The phones download it from the link above. '
                'Uploading also sets the latest build.',
                style: text.bodySmall,
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  OutlinedButton.icon(
                    onPressed: _uploading ? null : _pickApk,
                    icon: const Icon(AppIcons.download, size: 18),
                    label: const Text('Choose APK'),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      _apk == null ? 'No file chosen' : '${_apk!.name} · ${(_apk!.size / 1048576).toStringAsFixed(1)} MB',
                      overflow: TextOverflow.ellipsis,
                      style: text.bodySmall,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  SizedBox(
                    width: 160,
                    child: TextField(
                      controller: _uploadBuild,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: 'Build number', helperText: 'From the APK, e.g. 2'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  FilledButton.icon(
                    onPressed: _uploading || _apk == null ? null : _uploadApk,
                    icon: _uploading
                        ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(AppIcons.download, size: 18),
                    label: Text(_uploading ? 'Uploading…' : 'Upload'),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        _Card(
          title: 'Set the rule',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Phones older than the minimum build are stopped on the update page until they install the latest APK.',
                style: text.bodySmall,
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _minBuild,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: 'Minimum build'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      controller: _latestBuild,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: 'Latest build'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _message,
                maxLength: 300,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: 'Message (optional)',
                  helperText: 'Shown on the update page. Leave empty for the default.',
                ),
              ),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerRight,
                child: FilledButton(
                  onPressed: _saving ? null : _saveRule,
                  child: Text(_saving ? 'Saving…' : 'Save rule'),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _Card extends StatelessWidget {
  const _Card({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(AppTheme.radiusCard),
        border: Border.all(color: AppTheme.neutral200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(fontSize: 12, color: AppTheme.faint, fontWeight: FontWeight.w600)),
          const SizedBox(height: 2),
          SelectableText(value, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}
