import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import 'package:video_player/video_player.dart';
import '../controllers/chat_controller.dart';
import '../models/outreach_message.dart';
import '../services/media_service.dart';
import 'media_viewers.dart';

/// Bottom bar: attach button, text field, send button; with reply and
/// attachment previews above it.
class ChatComposer extends StatefulWidget {
  const ChatComposer({super.key, required this.controller});
  final ChatController controller;

  @override
  State<ChatComposer> createState() => _ChatComposerState();
}

class _ChatComposerState extends State<ChatComposer> {
  final _text = TextEditingController();
  final _media = MediaService();
  bool _picking = false;

  // ---- voice recording ----
  static const _maxVoice = Duration(minutes: 5);
  final _recorder = AudioRecorder();
  bool _recording = false;
  Duration _elapsed = Duration.zero;
  Timer? _ticker;

  ChatController get c => widget.controller;

  @override
  void initState() {
    super.initState();
    _text.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _ticker?.cancel();
    if (_recording) _recorder.cancel();
    _recorder.dispose();
    _text.dispose();
    super.dispose();
  }

  Future<void> _startRecording() async {
    if (_recording) return;
    try {
      if (!await _recorder.hasPermission()) {
        _toast('Microphone permission is needed to record voice notes.');
        return;
      }
      final dir = await getTemporaryDirectory();
      final path =
          '${dir.path}/rec_${DateTime.now().millisecondsSinceEpoch}.m4a';
      await _recorder.start(
        const RecordConfig(
          encoder: AudioEncoder.aacLc,
          bitRate: 64000,
          sampleRate: 44100,
          numChannels: 1,
        ),
        path: path,
      );
      setState(() {
        _recording = true;
        _elapsed = Duration.zero;
      });
      _ticker = Timer.periodic(const Duration(milliseconds: 200), (_) {
        if (!mounted) return;
        setState(() => _elapsed += const Duration(milliseconds: 200));
        if (_elapsed >= _maxVoice) _finishRecording(send: true);
      });
    } catch (e) {
      _toast('Could not start recording: $e');
    }
  }

  Future<void> _finishRecording({required bool send}) async {
    if (!_recording) return;
    _ticker?.cancel();
    final took = _elapsed;
    setState(() => _recording = false);
    try {
      if (!send) {
        await _recorder.cancel();
        return;
      }
      final path = await _recorder.stop();
      if (path == null) return;
      if (took < const Duration(seconds: 1)) {
        File(path).delete().ignore();
        _toast('Hold on a little longer to record a voice note.');
        return;
      }
      c.sendVoice(await MediaService.voiceNote(path, took.inMilliseconds));
    } on MediaValidationException catch (e) {
      _toast(e.message);
    } catch (e) {
      _toast('Recording failed: $e');
    }
  }

  bool get _canSend => c.attachment != null || _text.text.trim().isNotEmpty;

  void _send() {
    if (!_canSend) return;
    if (c.attachment != null) {
      c.sendAttachment(_text.text);
    } else {
      c.sendText(_text.text);
    }
    _text.clear();
  }

  Future<void> _pick(
    Future<PickedMedia?> Function() pick, {
    bool measureDuration = false,
  }) async {
    if (_picking) return;
    setState(() => _picking = true);
    try {
      var picked = await pick();
      if (picked == null) return;
      if (measureDuration) {
        picked = picked.withDuration(await _duration(picked.path));
      }
      c.setAttachment(picked);
    } on MediaValidationException catch (e) {
      _toast(e.message);
    } catch (e) {
      _toast('Could not attach the file: $e');
    } finally {
      if (mounted) setState(() => _picking = false);
    }
  }

  Future<int?> _duration(String path) async {
    final vc = VideoPlayerController.file(File(path));
    try {
      await vc.initialize();
      return vc.value.duration.inMilliseconds;
    } catch (_) {
      return null;
    } finally {
      await vc.dispose();
    }
  }

  void _toast(String m) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
    }
  }

  Future<void> _showAttachSheet() async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) {
        Widget item(
          IconData icon,
          Color color,
          String label,
          VoidCallback onTap,
        ) => InkWell(
          onTap: () {
            Navigator.pop(ctx);
            onTap();
          },
          borderRadius: BorderRadius.circular(12),
          child: SizedBox(
            width: 84,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircleAvatar(
                  radius: 26,
                  backgroundColor: color,
                  child: Icon(icon, color: Colors.white),
                ),
                const SizedBox(height: 6),
                Text(label, style: const TextStyle(fontSize: 12)),
                const SizedBox(height: 8),
              ],
            ),
          ),
        );
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            child: Wrap(
              alignment: WrapAlignment.center,
              runSpacing: 8,
              spacing: 8,
              children: [
                item(
                  Icons.photo_camera,
                  Colors.pink,
                  'Camera',
                  () => _pick(() => _media.pickImage(ImageSource.camera)),
                ),
                item(
                  Icons.photo,
                  Colors.purple,
                  'Gallery',
                  () => _pick(() => _media.pickImage(ImageSource.gallery)),
                ),
                item(
                  Icons.videocam,
                  Colors.red,
                  'Video',
                  () => _pick(
                    () => _media.pickVideo(ImageSource.gallery),
                    measureDuration: true,
                  ),
                ),
                item(
                  Icons.video_call,
                  Colors.deepOrange,
                  'Record',
                  () => _pick(
                    () => _media.pickVideo(ImageSource.camera),
                    measureDuration: true,
                  ),
                ),
                item(
                  Icons.insert_drive_file,
                  Colors.indigo,
                  'Document',
                  () => _pick(_media.pickDocument),
                ),
                item(
                  Icons.headphones,
                  Colors.orange,
                  'Audio',
                  () => _pick(_media.pickAudio, measureDuration: true),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final accent = dark ? const Color(0xFF00A884) : const Color(0xFF128C7E);
    final reply = c.replyTo;
    final att = c.attachment;
    return Material(
      color: dark ? const Color(0xFF0B141A) : const Color(0xFFF0F2F5),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (reply != null)
              _Strip(
                icon: Icons.reply,
                title: reply.isOutbound ? 'Replying to yourself' : 'Replying',
                subtitle: reply.preview,
                onClose: () => c.setReply(null),
              ),
            if (att != null)
              _AttachmentPreview(
                media: att,
                onClose: () => c.setAttachment(null),
              ),
            if (_recording)
              Padding(
                padding: const EdgeInsets.fromLTRB(6, 6, 6, 6),
                child: Row(
                  children: [
                    IconButton(
                      tooltip: 'Cancel recording',
                      icon: const Icon(Icons.delete_outline, color: Colors.red),
                      onPressed: () => _finishRecording(send: false),
                    ),
                    const Icon(
                      Icons.fiber_manual_record,
                      color: Colors.red,
                      size: 14,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      formatDuration(_elapsed),
                      style: const TextStyle(
                        fontSize: 16,
                        fontFeatures: [FontFeature.tabularFigures()],
                      ),
                    ),
                    const Spacer(),
                    const Text('Recording…', style: TextStyle(fontSize: 12)),
                    const SizedBox(width: 12),
                    CircleAvatar(
                      radius: 24,
                      backgroundColor: accent,
                      child: IconButton(
                        tooltip: 'Send voice note',
                        icon: const Icon(
                          Icons.send,
                          color: Colors.white,
                          size: 20,
                        ),
                        onPressed: () => _finishRecording(send: true),
                      ),
                    ),
                  ],
                ),
              )
            else
              Padding(
                padding: const EdgeInsets.fromLTRB(6, 6, 6, 6),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Expanded(
                      child: Container(
                        decoration: BoxDecoration(
                          color: dark ? const Color(0xFF1F2C34) : Colors.white,
                          borderRadius: BorderRadius.circular(24),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            IconButton(
                              tooltip: 'Attach',
                              icon: _picking
                                  ? const SizedBox(
                                      width: 20,
                                      height: 20,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : const Icon(Icons.attach_file),
                              onPressed: _picking ? null : _showAttachSheet,
                            ),
                            Expanded(
                              child: TextField(
                                controller: _text,
                                minLines: 1,
                                maxLines: 5,
                                maxLength: 4096,
                                textCapitalization:
                                    TextCapitalization.sentences,
                                decoration: InputDecoration(
                                  counterText: '',
                                  hintText:
                                      att != null &&
                                          att.type != MessageType.audio &&
                                          att.type != MessageType.document
                                      ? 'Add a caption…'
                                      : 'Type a message',
                                  border: InputBorder.none,
                                  isDense: true,
                                  contentPadding: const EdgeInsets.symmetric(
                                    vertical: 12,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    CircleAvatar(
                      radius: 24,
                      backgroundColor: accent,
                      child: _canSend
                          ? IconButton(
                              tooltip: 'Send',
                              icon: const Icon(
                                Icons.send,
                                color: Colors.white,
                                size: 20,
                              ),
                              onPressed: _send,
                            )
                          : IconButton(
                              tooltip: 'Record voice note',
                              icon: const Icon(
                                Icons.mic,
                                color: Colors.white,
                                size: 22,
                              ),
                              onPressed: _startRecording,
                            ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _Strip extends StatelessWidget {
  const _Strip({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onClose,
  });
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.fromLTRB(8, 6, 8, 0),
    padding: const EdgeInsets.fromLTRB(10, 6, 2, 6),
    decoration: BoxDecoration(
      color: Colors.black.withValues(alpha: 0.06),
      borderRadius: BorderRadius.circular(10),
      border: const Border(
        left: BorderSide(color: Color(0xFF128C7E), width: 4),
      ),
    ),
    child: Row(
      children: [
        Icon(icon, size: 18),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Text(
                subtitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 12.5),
              ),
            ],
          ),
        ),
        IconButton(
          icon: const Icon(Icons.close, size: 18),
          tooltip: 'Cancel',
          onPressed: onClose,
        ),
      ],
    ),
  );
}

class _AttachmentPreview extends StatelessWidget {
  const _AttachmentPreview({required this.media, required this.onClose});
  final PickedMedia media;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final isImage = media.type == MessageType.image;
    final canPreviewPlay =
        media.type == MessageType.video || media.type == MessageType.audio;
    final sub = [
      MediaService.humanSize(media.size),
      MediaService.extOf(media.fileName).toUpperCase(),
      if (media.durationMs != null)
        formatDuration(Duration(milliseconds: media.durationMs!)),
    ].where((s) => s.isNotEmpty).join(' • ');
    final icon = switch (media.type) {
      MessageType.video => Icons.videocam,
      MessageType.audio => Icons.headphones,
      _ => Icons.insert_drive_file,
    };
    return Container(
      margin: const EdgeInsets.fromLTRB(8, 6, 8, 0),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          GestureDetector(
            onTap: isImage
                ? () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => FullScreenImage(filePath: media.path),
                    ),
                  )
                : null,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: isImage
                  ? Image.file(
                      File(media.path),
                      width: 56,
                      height: 56,
                      fit: BoxFit.cover,
                    )
                  : Container(
                      width: 56,
                      height: 56,
                      color: Colors.black12,
                      child: Icon(icon, size: 28),
                    ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  media.fileName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                Text(sub, style: const TextStyle(fontSize: 12)),
              ],
            ),
          ),
          if (canPreviewPlay)
            IconButton(
              tooltip: 'Preview',
              icon: const Icon(Icons.play_circle_outline),
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => MediaPlayerPage(
                    filePath: media.path,
                    title: media.fileName,
                    isAudio: media.type == MessageType.audio,
                  ),
                ),
              ),
            ),
          IconButton(
            icon: const Icon(Icons.close),
            tooltip: 'Remove attachment',
            onPressed: onClose,
          ),
        ],
      ),
    );
  }
}
