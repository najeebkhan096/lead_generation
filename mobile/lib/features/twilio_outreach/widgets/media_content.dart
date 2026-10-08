import 'dart:io';
import 'package:flutter/material.dart';
import 'package:open_filex/open_filex.dart';
import 'package:video_player/video_player.dart';
import '../models/outreach_message.dart';
import '../services/media_service.dart';
import 'media_viewers.dart';

/// Builds the inside-the-bubble media for a message: image, video, audio or document.
class MessageMedia extends StatelessWidget {
  const MessageMedia({super.key, required this.message});

  final OutreachMessage message;

  @override
  Widget build(BuildContext context) {
    final media = message.media;
    if (media == null) return const SizedBox.shrink();
    final child = switch (message.type) {
      MessageType.image || MessageType.template => _ImageContent(media: media),
      MessageType.video => _VideoContent(media: media),
      MessageType.audio => _AudioContent(media: media),
      _ => _DocumentContent(media: media),
    };
    if (!message.isUploading) return child;
    // Upload progress over the whole attachment.
    return Stack(alignment: Alignment.center, children: [
      Opacity(opacity: 0.45, child: child),
      CircularProgressIndicator(value: message.uploadProgress == 0 ? null : message.uploadProgress),
    ]);
  }
}

class _Placeholder extends StatelessWidget {
  const _Placeholder({required this.icon, this.label, this.busy = false, this.h = 160});
  final IconData icon;
  final String? label;
  final bool busy;
  final double h;

  @override
  Widget build(BuildContext context) => Container(
        width: 220,
        height: h,
        color: Colors.black12,
        alignment: Alignment.center,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          busy ? const CircularProgressIndicator(strokeWidth: 2) : Icon(icon, size: 36, color: Colors.black45),
          if (label != null) Padding(padding: const EdgeInsets.only(top: 6), child: Text(label!, style: const TextStyle(fontSize: 12))),
        ]),
      );
}

/// Resolves the media's download URL; shows loading / error states.
class _UrlBuilder extends StatelessWidget {
  const _UrlBuilder({required this.media, required this.builder});
  final MediaInfo media;
  final Widget Function(BuildContext, String url) builder;

  @override
  Widget build(BuildContext context) {
    if (media.error != null) {
      return _Placeholder(icon: Icons.error_outline, label: 'Could not load file');
    }
    if (media.storagePath == null) {
      return const _Placeholder(icon: Icons.downloading, busy: true, label: 'Downloading…');
    }
    return FutureBuilder<String>(
      future: MediaUrls.resolve(media.storagePath!),
      builder: (ctx, snap) {
        if (snap.hasError) return const _Placeholder(icon: Icons.error_outline, label: 'Could not load file');
        if (!snap.hasData) return const _Placeholder(icon: Icons.image, busy: true);
        return builder(ctx, snap.data!);
      },
    );
  }
}

class _ImageContent extends StatelessWidget {
  const _ImageContent({required this.media});
  final MediaInfo media;

  @override
  Widget build(BuildContext context) {
    final local = media.localPath;
    final image = local != null
        ? GestureDetector(
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => FullScreenImage(filePath: local))),
            child: Image.file(File(local), width: 220, height: 220, fit: BoxFit.cover),
          )
        : _UrlBuilder(
            media: media,
            builder: (ctx, url) => GestureDetector(
              onTap: () => Navigator.push(ctx, MaterialPageRoute(builder: (_) => FullScreenImage(url: url))),
              child: Image.network(
                url,
                width: 220,
                height: 220,
                fit: BoxFit.cover,
                loadingBuilder: (_, child, p) => p == null ? child : const _Placeholder(icon: Icons.image, busy: true, h: 220),
                errorBuilder: (_, _, _) => const _Placeholder(icon: Icons.broken_image_outlined, label: 'Image unavailable', h: 220),
              ),
            ),
          );
    return ClipRRect(borderRadius: BorderRadius.circular(8), child: image);
  }
}

class _VideoContent extends StatefulWidget {
  const _VideoContent({required this.media});
  final MediaInfo media;

  @override
  State<_VideoContent> createState() => _VideoContentState();
}

class _VideoContentState extends State<_VideoContent> {
  VideoPlayerController? _c;
  String? _url;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _prepare();
  }

  Future<void> _prepare() async {
    final m = widget.media;
    try {
      if (m.localPath != null) {
        _c = VideoPlayerController.file(File(m.localPath!));
      } else if (m.storagePath != null) {
        _url = await MediaUrls.resolve(m.storagePath!);
        _c = VideoPlayerController.networkUrl(Uri.parse(_url!));
      } else {
        return;
      }
      await _c!.initialize(); // first frame doubles as the thumbnail
      if (mounted) setState(() {});
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    }
  }

  @override
  void dispose() {
    _c?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final m = widget.media;
    if (m.error != null) return const _Placeholder(icon: Icons.error_outline, label: 'Video unavailable');
    if (m.localPath == null && m.storagePath == null) {
      return const _Placeholder(icon: Icons.downloading, busy: true, label: 'Downloading…');
    }
    final c = _c;
    final ready = c != null && c.value.isInitialized;
    final duration = ready ? c.value.duration : (m.durationMs != null ? Duration(milliseconds: m.durationMs!) : null);
    return GestureDetector(
      onTap: () {
        Navigator.push(context, MaterialPageRoute(builder: (_) => MediaPlayerPage(url: _url, filePath: m.localPath, title: m.fileName)));
      },
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: SizedBox(
          width: 220,
          height: 160,
          child: Stack(fit: StackFit.expand, children: [
            Container(color: Colors.black),
            if (ready)
              FittedBox(fit: BoxFit.cover, clipBehavior: Clip.hardEdge, child: SizedBox(width: c.value.size.width, height: c.value.size.height, child: VideoPlayer(c))),
            if (!ready && !_failed) const Center(child: CircularProgressIndicator(strokeWidth: 2)),
            const Center(child: Icon(Icons.play_circle_fill, color: Colors.white70, size: 52)),
            if (duration != null)
              Positioned(
                left: 8,
                bottom: 6,
                child: Row(children: [
                  const Icon(Icons.videocam, size: 14, color: Colors.white),
                  const SizedBox(width: 4),
                  Text(formatDuration(duration), style: const TextStyle(color: Colors.white, fontSize: 12)),
                ]),
              ),
          ]),
        ),
      ),
    );
  }
}

class _AudioContent extends StatefulWidget {
  const _AudioContent({required this.media});
  final MediaInfo media;

  @override
  State<_AudioContent> createState() => _AudioContentState();
}

class _AudioContentState extends State<_AudioContent> {
  VideoPlayerController? _c; // video_player plays audio-only files too
  String? _url;
  bool _loading = false;
  bool _failed = false;

  Future<void> _toggle() async {
    final m = widget.media;
    if (_c == null) {
      setState(() => _loading = true);
      try {
        if (m.localPath != null) {
          _c = VideoPlayerController.file(File(m.localPath!));
        } else {
          _url = await MediaUrls.resolve(m.playablePath!);
          _c = VideoPlayerController.networkUrl(Uri.parse(_url!));
        }
        _c!.addListener(() {
          if (mounted) setState(() {});
        });
        await _c!.initialize();
        await _c!.play();
      } catch (_) {
        _failed = true;
      }
      if (mounted) setState(() => _loading = false);
      return;
    }
    _c!.value.isPlaying ? await _c!.pause() : await _c!.play();
  }

  @override
  void dispose() {
    _c?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final m = widget.media;
    if (m.error != null) return const _Placeholder(icon: Icons.error_outline, label: 'Audio unavailable', h: 56);
    final ready = _c?.value.isInitialized ?? false;
    final total = ready
        ? _c!.value.duration
        : (m.durationMs != null ? Duration(milliseconds: m.durationMs!) : Duration.zero);
    final pos = ready ? _c!.value.position : Duration.zero;
    final playing = _c?.value.isPlaying ?? false;
    final canPlay = m.localPath != null || m.playablePath != null;
    return SizedBox(
      width: 230,
      child: Row(children: [
        if (m.voice) const Padding(padding: EdgeInsets.only(left: 4), child: Icon(Icons.mic, size: 18)),
        _loading
            ? const Padding(padding: EdgeInsets.all(10), child: SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2)))
            : IconButton(
                icon: Icon(playing ? Icons.pause_circle_filled : Icons.play_circle_filled, size: 36),
                onPressed: canPlay && !_failed ? _toggle : null,
              ),
        Expanded(
          child: _failed
              ? Row(children: [
                  const Expanded(child: Text("Can't play this format here", style: TextStyle(fontSize: 12))),
                  if (_url != null) TextButton(onPressed: () => openExternally(context, _url!), child: const Text('Open')),
                ])
              : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  LinearProgressIndicator(
                    value: total.inMilliseconds == 0 ? 0 : (pos.inMilliseconds / total.inMilliseconds).clamp(0, 1).toDouble(),
                    minHeight: 3,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    total == Duration.zero ? m.fileName : '${formatDuration(pos)} / ${formatDuration(total)}',
                    style: const TextStyle(fontSize: 11),
                    overflow: TextOverflow.ellipsis,
                  ),
                ]),
        ),
      ]),
    );
  }
}

class _DocumentContent extends StatefulWidget {
  const _DocumentContent({required this.media});
  final MediaInfo media;

  @override
  State<_DocumentContent> createState() => _DocumentContentState();
}

class _DocumentContentState extends State<_DocumentContent> {
  double? _progress; // non-null while downloading

  MediaInfo get media => widget.media;

  IconData get _icon {
    switch (MediaService.extOf(media.fileName)) {
      case 'pdf':
        return Icons.picture_as_pdf;
      case 'xls':
      case 'xlsx':
        return Icons.table_chart;
      case 'doc':
      case 'docx':
        return Icons.description;
      default:
        return Icons.insert_drive_file;
    }
  }

  Future<void> _open() async {
    if (_progress != null) return;
    final local = media.localPath;
    setState(() => _progress = 0);
    try {
      if (local != null) {
        await OpenFilex.open(local);
      } else {
        await MediaExport.open(media, onProgress: (p) {
          if (mounted) setState(() => _progress = p);
        });
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
    } finally {
      if (mounted) setState(() => _progress = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ext = MediaService.extOf(media.fileName).toUpperCase();
    final sub = [if (ext.isNotEmpty) ext, MediaService.humanSize(media.size)].where((s) => s.isNotEmpty).join(' • ');
    final available = media.storagePath != null || media.localPath != null;
    final tile = Container(
      width: 240,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.06), borderRadius: BorderRadius.circular(8)),
      child: Row(children: [
        Icon(_icon, size: 34, color: Colors.blueGrey),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(media.fileName, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
            if (sub.isNotEmpty) Text(sub, style: const TextStyle(fontSize: 11)),
            if (media.error != null) const Text('File unavailable', style: TextStyle(fontSize: 11, color: Colors.red)),
            if (!available && media.error == null) const Text('Downloading…', style: TextStyle(fontSize: 11)),
          ]),
        ),
        if (available)
          _progress != null
              ? SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2, value: _progress == 0 ? null : _progress),
                )
              : const Icon(Icons.open_in_new, size: 18),
      ]),
    );
    if (!available) return tile;
    return InkWell(borderRadius: BorderRadius.circular(8), onTap: _open, child: tile);
  }
}
