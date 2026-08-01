import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import 'backend_controller.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final _controller = BackendController();
  final _hostedUrlController = TextEditingController();
  final _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onControllerChanged);
    _controller.loadSettings().then((_) {
      _hostedUrlController.text = _controller.hostedUrl;
    });
  }

  void _onControllerChanged() {
    setState(() {});
    // Auto-scroll the log to the bottom on new output.
    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 150),
        curve: Curves.easeOut,
      );
    }
  }

  @override
  void dispose() {
    _controller.removeListener(_onControllerChanged);
    _controller.dispose();
    _hostedUrlController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _pickBackendFolder() async {
    final path = await getDirectoryPath(
      confirmButtonText: 'Use this folder',
    );
    if (path != null) {
      await _controller.setBackendPath(path);
    }
  }

  Future<void> _openHostedApp() async {
    final url = _hostedUrlController.text.trim();
    if (url.isEmpty) return;
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    await launchUrl(uri);
  }

  Future<void> _openLocalHealth() async {
    await launchUrl(_controller.healthUri);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Backend Launcher')),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _StatusCard(controller: _controller),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: Text(
                    _controller.backendPath.isEmpty
                        ? 'No backend folder selected'
                        : _controller.backendPath,
                    style: Theme.of(context).textTheme.bodySmall,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                TextButton(
                  onPressed: _controller.isBusy ? null : _pickBackendFolder,
                  child: const Text('Change Folder'),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: _controller.isBusy
                        ? null
                        : (_controller.status == BackendStatus.running
                            ? _controller.stop
                            : _controller.start),
                    icon: Icon(
                      _controller.status == BackendStatus.running
                          ? Icons.stop_rounded
                          : Icons.play_arrow_rounded,
                    ),
                    label: Text(
                      switch (_controller.status) {
                        BackendStatus.starting => 'Starting…',
                        BackendStatus.stopping => 'Stopping…',
                        BackendStatus.running => 'Stop Backend',
                        _ => 'Start Backend',
                      },
                    ),
                    style: FilledButton.styleFrom(
                      backgroundColor: _controller.status == BackendStatus.running
                          ? const Color(0xFFB91C1C)
                          : const Color(0xFF0F766E),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                OutlinedButton.icon(
                  onPressed: _controller.status == BackendStatus.running
                      ? _openLocalHealth
                      : null,
                  icon: const Icon(Icons.health_and_safety_outlined),
                  label: const Text('Open API'),
                ),
              ],
            ),
            const SizedBox(height: 20),
            Text('Hosted frontend', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _hostedUrlController,
                    decoration: const InputDecoration(
                      hintText: 'https://your-app.onrender.com',
                      isDense: true,
                    ),
                    onSubmitted: (value) => _controller.setHostedUrl(value.trim()),
                    onEditingComplete: () =>
                        _controller.setHostedUrl(_hostedUrlController.text.trim()),
                  ),
                ),
                const SizedBox(width: 12),
                FilledButton.tonalIcon(
                  onPressed: _openHostedApp,
                  icon: const Icon(Icons.open_in_new_rounded),
                  label: const Text('Open'),
                ),
              ],
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Text('Log', style: Theme.of(context).textTheme.titleSmall),
                const Spacer(),
                TextButton(
                  onPressed: _controller.clearLog,
                  child: const Text('Clear'),
                ),
              ],
            ),
            Expanded(child: _LogView(controller: _controller, scrollController: _scrollController)),
          ],
        ),
      ),
    );
  }
}

class _StatusCard extends StatelessWidget {
  const _StatusCard({required this.controller});

  final BackendController controller;

  @override
  Widget build(BuildContext context) {
    final (color, label) = switch (controller.status) {
      BackendStatus.stopped => (Colors.grey, 'Stopped'),
      BackendStatus.starting => (Colors.orange, 'Starting…'),
      BackendStatus.running =>
        controller.healthOk ? (Colors.green, 'Running · healthy') : (Colors.orange, 'Running · waiting for health check'),
      BackendStatus.stopping => (Colors.orange, 'Stopping…'),
      BackendStatus.error => (Colors.red, 'Error'),
    };

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          Container(
            width: 12,
            height: 12,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: const TextStyle(fontWeight: FontWeight.w700)),
                if (controller.status == BackendStatus.error && controller.lastError != null)
                  Text(
                    controller.lastError!,
                    style: const TextStyle(color: Color(0xFFB91C1C), fontSize: 12),
                  ),
                if (controller.status == BackendStatus.running)
                  Text(
                    'http://localhost:${BackendController.port}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _LogView extends StatelessWidget {
  const _LogView({required this.controller, required this.scrollController});

  final BackendController controller;
  final ScrollController scrollController;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFF0B1220),
        borderRadius: BorderRadius.circular(8),
      ),
      child: controller.logLines.isEmpty
          ? const Center(
              child: Text(
                'No output yet — press Start Backend.',
                style: TextStyle(color: Colors.white38),
              ),
            )
          : ListView.builder(
              controller: scrollController,
              itemCount: controller.logLines.length,
              itemBuilder: (context, index) => Text(
                controller.logLines[index],
                style: const TextStyle(
                  color: Color(0xFFD1D5DB),
                  fontFamily: 'monospace',
                  fontSize: 12,
                ),
              ),
            ),
    );
  }
}
