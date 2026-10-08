import 'dart:async';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import '../models/outreach_message.dart';

class MediaValidationException implements Exception {
  final String message;
  const MediaValidationException(this.message);
  @override
  String toString() => message;
}

/// A file chosen by the user, validated and ready to upload.
class PickedMedia {
  final String path;
  final String fileName;
  final String mimeType;
  final int size;
  final MessageType type;
  final int? durationMs;

  /// A freshly recorded voice note (AAC/m4a; the backend converts it to OGG/Opus).
  final bool voice;

  const PickedMedia({
    required this.path,
    required this.fileName,
    required this.mimeType,
    required this.size,
    required this.type,
    this.durationMs,
    this.voice = false,
  });

  PickedMedia withDuration(int? ms) => PickedMedia(
      path: path, fileName: fileName, mimeType: mimeType, size: size, type: type, durationMs: ms, voice: voice);
}

/// Picks, validates (extension / MIME / size — mirrors the backend and Storage
/// rules) and uploads attachments to
/// `outreach_media/{uid}/{conversationId}/{messageId}/{file}`.
class MediaService {
  static const maxBytes = 16 * 1024 * 1024; // Twilio's WhatsApp media limit

  // extension -> (mime, type). ZIP is intentionally absent: Twilio does not
  // document it as supported for WhatsApp.
  static const _byExt = <String, (String, MessageType)>{
    'jpg': ('image/jpeg', MessageType.image),
    'jpeg': ('image/jpeg', MessageType.image),
    'png': ('image/png', MessageType.image),
    'mp4': ('video/mp4', MessageType.video),
    '3gp': ('video/3gpp', MessageType.video),
    'ogg': ('audio/ogg', MessageType.audio),
    'opus': ('audio/ogg', MessageType.audio),
    'mp3': ('audio/mpeg', MessageType.audio),
    'aac': ('audio/aac', MessageType.audio),
    'amr': ('audio/amr', MessageType.audio),
    'pdf': ('application/pdf', MessageType.document),
    'doc': ('application/msword', MessageType.document),
    'docx': ('application/vnd.openxmlformats-officedocument.wordprocessingml.document', MessageType.document),
    'xls': ('application/vnd.ms-excel', MessageType.document),
    'xlsx': ('application/vnd.openxmlformats-officedocument.spreadsheetml.sheet', MessageType.document),
    'pptx': ('application/vnd.openxmlformats-officedocument.presentationml.presentation', MessageType.document),
    'txt': ('text/plain', MessageType.document),
  };

  static List<String> get documentExtensions =>
      ['pdf', 'doc', 'docx', 'xls', 'xlsx', 'pptx', 'txt'];
  static List<String> get audioExtensions => ['mp3', 'aac', 'ogg', 'opus', 'amr'];

  static String extOf(String name) => name.contains('.') ? name.split('.').last.toLowerCase() : '';

  static String humanSize(int? bytes) {
    if (bytes == null) return '';
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(0)} KB';
    return '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB';
  }

  /// Safe storage file name: ASCII letters/digits/._- only, extension preserved.
  static String sanitizeName(String name) {
    final ext = extOf(name);
    var base = name.contains('.') ? name.substring(0, name.lastIndexOf('.')) : name;
    base = base.replaceAll(RegExp(r'[^A-Za-z0-9_-]+'), '_');
    if (base.length > 60) base = base.substring(0, 60);
    if (base.isEmpty) base = 'file';
    return '$base.$ext';
  }

  static Future<PickedMedia> validate(String path, {String? originalName}) async {
    final name = originalName ?? path.split(Platform.pathSeparator).last;
    final ext = extOf(name);
    final rule = _byExt[ext];
    if (rule == null) {
      throw MediaValidationException(
          '".$ext" files are not supported by WhatsApp via Twilio. Allowed: images (JPG/PNG), video (MP4/3GP), '
          'audio (MP3/AAC/OGG/AMR), documents (PDF/DOC/DOCX/XLS/XLSX/PPTX/TXT).');
    }
    final size = await File(path).length();
    if (size == 0) throw const MediaValidationException('The file is empty.');
    if (size > maxBytes) {
      throw MediaValidationException(
          'File is ${humanSize(size)}; WhatsApp media is limited to ${humanSize(maxBytes)}.');
    }
    return PickedMedia(
        path: path, fileName: sanitizeName(name), mimeType: rule.$1, size: size, type: rule.$2);
  }

  /// Wraps a recording made by the in-app recorder. m4a is deliberately not in
  /// [_byExt]: users cannot attach arbitrary m4a files, only record them.
  static Future<PickedMedia> voiceNote(String path, int durationMs) async {
    final size = await File(path).length();
    if (size == 0) throw const MediaValidationException('The recording is empty.');
    if (size > maxBytes) throw const MediaValidationException('The recording is too long to send.');
    return PickedMedia(
      path: path,
      fileName: 'voice_${DateTime.now().millisecondsSinceEpoch}.m4a',
      mimeType: 'audio/mp4',
      size: size,
      type: MessageType.audio,
      durationMs: durationMs,
      voice: true,
    );
  }

  final _images = ImagePicker();

  /// Photo (compressed to max 1600px / 85% JPEG so it stays under the limit).
  Future<PickedMedia?> pickImage(ImageSource source) async {
    final f = await _images.pickImage(source: source, maxWidth: 1600, imageQuality: 85);
    return f == null ? null : validate(f.path, originalName: f.name);
  }

  Future<PickedMedia?> pickVideo(ImageSource source) async {
    final f = await _images.pickVideo(source: source, maxDuration: const Duration(minutes: 3));
    return f == null ? null : validate(f.path, originalName: f.name);
  }

  Future<PickedMedia?> pickDocument() => _pickFile(documentExtensions);

  Future<PickedMedia?> pickAudio() => _pickFile(audioExtensions);

  Future<PickedMedia?> _pickFile(List<String> exts) async {
    final r = await FilePicker.pickFiles(type: FileType.custom, allowedExtensions: exts);
    final file = r?.files.firstOrNull;
    if (file?.path == null) return null; // cancelled
    return validate(file!.path!, originalName: file.name);
  }

  /// Uploads with progress (0..1). Returns the storage path. [onTask] lets the
  /// caller cancel. Throws on failure.
  Future<MediaInfo> upload({
    required String uid,
    required String conversationId,
    required String messageId,
    required PickedMedia media,
    required void Function(double) onProgress,
    void Function(UploadTask)? onTask,
  }) async {
    final path = 'outreach_media/$uid/$conversationId/$messageId/${media.fileName}';
    final task = FirebaseStorage.instance
        .ref(path)
        .putFile(File(media.path), SettableMetadata(contentType: media.mimeType));
    onTask?.call(task);
    final sub = task.snapshotEvents.listen((s) {
      if (s.totalBytes > 0) onProgress(s.bytesTransferred / s.totalBytes);
    });
    try {
      await task;
    } finally {
      await sub.cancel();
    }
    return MediaInfo(
      storagePath: path,
      mimeType: media.mimeType,
      fileName: media.fileName,
      size: media.size,
      durationMs: media.durationMs,
    );
  }
}

/// Saves/shares a stored chat file through the system share sheet (Save to
/// Files / Photos, other apps...). Downloads through the Storage SDK so
/// Storage rules apply.
class MediaExport {
  static Future<File> download(MediaInfo media, {void Function(double)? onProgress}) async {
    final path = media.storagePath;
    if (path == null) throw const MediaValidationException('This file has not finished downloading yet.');
    final dir = await getTemporaryDirectory();
    final name = media.fileName.isEmpty ? 'file' : media.fileName;
    // Keyed by storage path so equal names from different messages never collide.
    final file = File('${dir.path}/${path.hashCode.toUnsigned(32)}_$name');
    if (await file.exists() && await file.length() > 0) {
      onProgress?.call(1);
      return file; // already downloaded: open instantly, like WhatsApp
    }
    final task = FirebaseStorage.instance.ref(path).writeToFile(file);
    final sub = task.snapshotEvents.listen((s) {
      if (s.totalBytes > 0) onProgress?.call(s.bytesTransferred / s.totalBytes);
    });
    try {
      await task;
    } finally {
      await sub.cancel();
    }
    return file;
  }

  /// Downloads (once) and opens the file in the platform viewer.
  static Future<void> open(MediaInfo media, {void Function(double)? onProgress}) async {
    final file = await download(media, onProgress: onProgress);
    final r = await OpenFilex.open(file.path, type: media.mimeType.isEmpty ? null : media.mimeType);
    if (r.type != ResultType.done) {
      throw MediaValidationException(r.type == ResultType.noAppToOpen
          ? 'No app on this phone can open this file type.'
          : 'Could not open the file.');
    }
  }

  static Future<void> share(MediaInfo media, {void Function(double)? onProgress}) async {
    final file = await download(media, onProgress: onProgress);
    await SharePlus.instance.share(ShareParams(files: [XFile(file.path, mimeType: media.mimeType)]));
  }
}

/// Resolves a Storage path to a download URL through the SDK (so Storage rules
/// apply) and caches it. Incoming media is never exposed through a stored URL.
class MediaUrls {
  static final _cache = <String, Future<String>>{};

  static Future<String> resolve(String storagePath) {
    return _cache.putIfAbsent(storagePath, () async {
      try {
        return await FirebaseStorage.instance.ref(storagePath).getDownloadURL();
      } catch (_) {
        _cache.remove(storagePath);
        rethrow;
      }
    });
  }
}
