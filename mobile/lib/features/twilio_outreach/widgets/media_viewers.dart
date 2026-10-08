import 'dart:io';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:video_player/video_player.dart';

Future<void> openExternally(BuildContext context, String url) async {
  final ok = await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
  if (!ok && context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No app available to open this file.')));
  }
}

String formatDuration(Duration d) {
  final m = d.inMinutes.remainder(60).toString().padLeft(1, '0');
  final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
  return d.inHours > 0 ? '${d.inHours}:${m.padLeft(2, '0')}:$s' : '$m:$s';
}

/// Pinch-zoom image viewer. Pass exactly one of [url] / [filePath].
/// The "open" action hands the file to the system (browser / viewer), from
/// where it can be saved or shared.
class FullScreenImage extends StatelessWidget {
  const FullScreenImage({super.key, this.url, this.filePath});

  final String? url;
  final String? filePath;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        actions: [
          if (url != null)
            IconButton(
              tooltip: 'Open / download',
              icon: const Icon(Icons.download_outlined),
              onPressed: () => openExternally(context, url!),
            ),
        ],
      ),
      body: Center(
        child: InteractiveViewer(
          maxScale: 6,
          child: filePath != null
              ? Image.file(File(filePath!))
              : Image.network(
                  url!,
                  loadingBuilder: (_, child, p) =>
                      p == null ? child : const Center(child: CircularProgressIndicator()),
                  errorBuilder: (_, _, _) =>
                      const Icon(Icons.broken_image_outlined, color: Colors.white54, size: 64),
                ),
        ),
      ),
    );
  }
}

/// Full-screen video/audio player (streams network sources; never loads the file into memory).
class MediaPlayerPage extends StatefulWidget {
  const MediaPlayerPage({super.key, this.url, this.filePath, this.title = '', this.isAudio = false});

  final String? url;
  final String? filePath;
  final String title;
  final bool isAudio;

  @override
  State<MediaPlayerPage> createState() => _MediaPlayerPageState();
}

class _MediaPlayerPageState extends State<MediaPlayerPage> {
  late final VideoPlayerController _c;
  bool _ready = false;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _c = widget.filePath != null
        ? VideoPlayerController.file(File(widget.filePath!))
        : VideoPlayerController.networkUrl(Uri.parse(widget.url!));
    _c.addListener(() {
      if (mounted) setState(() {});
    });
    _c.initialize().then((_) {
      if (!mounted) return;
      setState(() => _ready = true);
      _c.play();
    }).catchError((Object e) {
      if (mounted) setState(() => _error = e);
    });
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(widget.title, style: const TextStyle(fontSize: 14)),
        actions: [
          if (widget.url != null)
            IconButton(
              tooltip: 'Open / download',
              icon: const Icon(Icons.download_outlined),
              onPressed: () => openExternally(context, widget.url!),
            ),
        ],
      ),
      body: _error != null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  const Icon(Icons.error_outline, color: Colors.white70, size: 48),
                  const SizedBox(height: 12),
                  const Text("This file can't be played in the app.",
                      style: TextStyle(color: Colors.white70), textAlign: TextAlign.center),
                  if (widget.url != null)
                    TextButton(
                        onPressed: () => openExternally(context, widget.url!),
                        child: const Text('Open in another app')),
                ]),
              ),
            )
          : !_ready
              ? const Center(child: CircularProgressIndicator())
              : Column(children: [
                  Expanded(
                    child: Center(
                      child: widget.isAudio
                          ? const Icon(Icons.graphic_eq, color: Colors.white54, size: 96)
                          : AspectRatio(aspectRatio: _c.value.aspectRatio, child: VideoPlayer(_c)),
                    ),
                  ),
                  VideoProgressIndicator(_c, allowScrubbing: true, padding: const EdgeInsets.all(16)),
                  Padding(
                    padding: const EdgeInsets.only(bottom: 24),
                    child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                      Text(formatDuration(_c.value.position), style: const TextStyle(color: Colors.white70)),
                      const SizedBox(width: 12),
                      IconButton(
                        iconSize: 56,
                        color: Colors.white,
                        icon: Icon(_c.value.isPlaying ? Icons.pause_circle : Icons.play_circle),
                        onPressed: () => _c.value.isPlaying ? _c.pause() : _c.play(),
                      ),
                      const SizedBox(width: 12),
                      Text(formatDuration(_c.value.duration), style: const TextStyle(color: Colors.white70)),
                    ]),
                  ),
                ]),
    );
  }
}
