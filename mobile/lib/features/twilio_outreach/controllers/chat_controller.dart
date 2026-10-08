import 'dart:async';
import 'dart:io';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/outreach_lead.dart';
import '../models/outreach_message.dart';
import '../services/media_service.dart';
import '../services/outreach_api.dart';
import '../services/outreach_repository.dart';

enum _Kind { text, media, template }

/// An outgoing message the server has not (yet) confirmed. Shown optimistically;
/// dropped as soon as the real Firestore document with the same id arrives.
class _Pending {
  _Pending({
    required this.id,
    required this.kind,
    required this.type,
    required this.createdAt,
    this.body = '',
    this.picked,
    this.templateUrl,
    this.replyTo,
  });

  final String id;
  final _Kind kind;
  final MessageType type;
  final DateTime createdAt;
  final String body;
  final PickedMedia? picked;
  final String? templateUrl;
  final String? replyTo;

  MediaInfo? uploaded;
  double? progress;
  String? error;
  UploadTask? task;
  bool running = false;
}

/// State + actions for one open chat. Messages/status/window come from
/// Firestore streams (written by the backend from Twilio webhooks) — nothing here
/// polls Twilio.
class ChatController extends ChangeNotifier {
  ChatController({
    required this.leadId,
    OutreachRepository? repository,
    OutreachApi? api,
    MediaService? media,
  })  : _repo = repository ?? OutreachRepository(),
        _api = api ?? OutreachApi(),
        _media = media ?? MediaService();

  final String leadId;
  final OutreachRepository _repo;
  final OutreachApi _api;
  final MediaService _media;

  List<OutreachMessage> _server = const [];
  final Map<String, _Pending> _pending = {};
  OutreachConversation conversation = const OutreachConversation();
  OutreachLead? lead;
  bool loading = true;
  Object? error;

  OutreachMessage? replyTo;
  PickedMedia? attachment;

  /// Pagination: the live query covers the newest [_limit] messages; scrolling
  /// to the top widens it by [pageSize] until a query returns fewer than asked.
  static const pageSize = 50;
  int _limit = pageSize;
  bool hasMore = true;
  bool loadingOlder = false;

  StreamSubscription<MessagePage>? _msgSub;
  StreamSubscription<OutreachConversation>? _convSub;
  StreamSubscription<OutreachLead?>? _leadSub;
  Timer? _windowTicker;
  bool _markingRead = false;
  bool _active = false;
  bool _disposed = false;

  /// Begin listening. Cheap to skip when you only need the send helpers (forwarding).
  void start() {
    _active = true;
    _listenMessages();
    _convSub = _repo.watchConversation(leadId).listen((c) {
      conversation = c;
      notifyListeners();
    }, onError: (_) {});
    _leadSub = _repo.watchLead(leadId).listen((l) {
      lead = l;
      notifyListeners();
      if (l != null && l.unreadCount > 0) _markRead();
    }, onError: (_) {});
    // The 24h window closes with time, not with a data change.
    _windowTicker = Timer.periodic(const Duration(seconds: 30), (_) => notifyListeners());
  }

  void _listenMessages() {
    _msgSub?.cancel();
    _msgSub = _repo.watchMessages(leadId, limit: _limit).listen((list) {
      _server = list.messages;
      // `rawCount` includes hidden ("deleted") docs so a page of hidden messages
      // does not look like the end of history.
      hasMore = list.rawCount >= _limit;
      loadingOlder = false;
      final ids = list.messages.map((m) => m.id).toSet();
      _pending.removeWhere((id, p) => ids.contains(id));
      loading = false;
      error = null;
      notifyListeners();
      _maybeBackfill();
    }, onError: (Object e) {
      loading = false;
      loadingOlder = false;
      error = e;
      notifyListeners();
    });
  }

  /// Loads the next older page (no-op while loading or at the start of history).
  void loadOlder() {
    if (loadingOlder || !hasMore || loading) return;
    loadingOlder = true;
    _limit += pageSize;
    notifyListeners();
    _listenMessages();
  }

  Future<void> _markRead() async {
    if (_markingRead || !_active) return;
    _markingRead = true;
    try {
      await _repo.markRead(leadId);
    } catch (e) {
      debugPrint('[Outreach] markRead failed: $e');
    } finally {
      _markingRead = false;
    }
  }

  /// First time an empty conversation is opened, pull what Twilio already has
  /// into Firestore (one-off; failure is non-fatal).
  Future<void> _maybeBackfill() async {
    if (_server.isNotEmpty || _pending.isNotEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    final key = 'outreach_backfilled_$leadId';
    if (prefs.getBool(key) == true) return;
    await prefs.setBool(key, true);
    try {
      await _api.backfill(leadId);
    } catch (e) {
      debugPrint('[Outreach] backfill skipped: $e');
      await prefs.remove(key);
    }
  }

  // ---- view state ------------------------------------------------------------

  String get myUid => _repo.uid;

  bool get windowOpen => conversation.isWindowOpen();

  /// Newest first.
  List<OutreachMessage> get items {
    final local = _pending.values.map(_pendingToMessage).toList();
    return [...local, ..._server]..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  }

  OutreachMessage? messageById(String? id) {
    if (id == null) return null;
    for (final m in items) {
      if (m.id == id) return m;
    }
    return null;
  }

  OutreachMessage _pendingToMessage(_Pending p) {
    return OutreachMessage(
      id: p.id,
      conversationId: leadId,
      direction: MessageDirection.outbound,
      type: p.type,
      body: p.body,
      media: p.picked != null
          ? MediaInfo(
              mimeType: p.picked!.mimeType,
              fileName: p.picked!.fileName,
              size: p.picked!.size,
              durationMs: p.picked!.durationMs,
              localPath: p.picked!.path)
          : null,
      status: MessageStatus.sending,
      createdAt: p.createdAt,
      replyToMessageId: p.replyTo,
      uploadProgress: p.progress,
      localError: p.error,
      isLocalOnly: true,
    );
  }

  // ---- composer state --------------------------------------------------------

  void setReply(OutreachMessage? m) {
    replyTo = m;
    notifyListeners();
  }

  void setAttachment(PickedMedia? a) {
    attachment = a;
    notifyListeners();
  }

  // ---- sending ---------------------------------------------------------------

  Future<void> sendText(String text) async {
    final body = text.trim();
    if (body.isEmpty) return;
    _enqueue(_Pending(
      id: _repo.newMessageId(leadId),
      kind: _Kind.text,
      type: MessageType.text,
      createdAt: DateTime.now(),
      body: body,
      replyTo: replyTo?.id,
    ));
  }

  /// Sends the attachment currently staged in the composer, with [caption].
  void sendAttachment(String caption) {
    final a = attachment;
    if (a == null) return;
    _enqueue(_Pending(
      id: _repo.newMessageId(leadId),
      kind: _Kind.media,
      type: a.type,
      createdAt: DateTime.now(),
      body: (a.type == MessageType.audio || a.type == MessageType.document) ? '' : caption.trim(),
      picked: a,
      replyTo: replyTo?.id,
    ));
    attachment = null;
  }

  /// [downloadUrl] is the Firebase URL from [pickAndUploadTemplateImage].
  void sendTemplate(String downloadUrl) {
    _enqueue(_Pending(
      id: _repo.newMessageId(leadId),
      kind: _Kind.template,
      type: MessageType.template,
      createdAt: DateTime.now(),
      templateUrl: downloadUrl,
    ));
  }

  void _enqueue(_Pending p) {
    _pending[p.id] = p;
    replyTo = null;
    notifyListeners();
    unawaited(_run(p));
  }

  Future<void> _run(_Pending p) async {
    if (p.running) return;
    p.running = true;
    p.error = null;
    try {
      if (p.kind == _Kind.media && p.uploaded == null) {
        p.progress = 0;
        notifyListeners();
        p.uploaded = await _media.upload(
          uid: _repo.uid,
          conversationId: leadId,
          messageId: p.id,
          media: p.picked!,
          onProgress: (v) {
            p.progress = v;
            notifyListeners();
          },
          onTask: (t) => p.task = t,
        );
      }
      p.progress = null;
      notifyListeners();
      switch (p.kind) {
        case _Kind.text:
          await _api.sendText(leadId: leadId, messageId: p.id, body: p.body, replyTo: p.replyTo);
        case _Kind.media:
          await _api.sendMedia(
              leadId: leadId, messageId: p.id, media: p.uploaded!, caption: p.body, replyTo: p.replyTo);
        case _Kind.template:
          await _api.sendTemplate(leadId: leadId, messageId: p.id, mediaUrl: p.templateUrl!);
      }
      // Stay listed until the Firestore document shows up (see start()).
    } on OutreachApiException catch (e) {
      p.error = e.message;
    } on FirebaseException catch (e) {
      p.error = e.code == 'canceled' ? 'Upload cancelled.' : 'Upload failed (${e.message ?? e.code}).';
    } catch (e) {
      p.error = 'Something went wrong: $e';
    } finally {
      p.progress = null;
      p.running = false;
      p.task = null;
      if (!_disposed) notifyListeners();
    }
  }

  /// Retry either a local (upload/request failed) or a server-side failed message.
  Future<void> retry(OutreachMessage m) async {
    final p = _pending[m.id];
    if (p != null) {
      unawaited(_run(p));
      return;
    }
    try {
      await _api.retry(leadId: leadId, messageId: m.id);
    } on OutreachApiException catch (e) {
      lastActionError = e.message;
      notifyListeners();
    }
  }

  /// Set when a fire-and-forget action fails; the page shows it once.
  String? lastActionError;

  /// Drops a message that never reached the server (cancel upload / discard).
  void discard(String id) {
    final p = _pending.remove(id);
    p?.task?.cancel();
    notifyListeners();
  }

  Future<void> hide(OutreachMessage m) async {
    if (m.isLocalOnly) return discard(m.id);
    await _repo.hideMessage(leadId, m.id);
  }

  /// Toggles [emoji] as this user's reaction (same emoji again removes it).
  Future<void> react(OutreachMessage m, String emoji) async {
    if (m.isLocalOnly) return;
    final mine = m.reactions[_repo.uid];
    try {
      await _api.react(leadId: leadId, messageId: m.id, emoji: mine == emoji ? null : emoji);
    } on OutreachApiException catch (e) {
      lastActionError = e.message;
      notifyListeners();
    }
  }

  /// Voice notes send immediately (no caption step), like WhatsApp.
  void sendVoice(PickedMedia voice) {
    attachment = voice;
    sendAttachment('');
  }

  Future<void> refreshStatus(OutreachMessage m) => _api.refreshStatus(leadId: leadId, messageId: m.id);

  /// Re-sends [m]'s content into this conversation (used on the *target* lead's controller).
  /// Media is downloaded and re-uploaded into this conversation's own folder.
  Future<void> forwardHere(OutreachMessage m) async {
    if (m.type == MessageType.template) {
      throw const MediaValidationException('Templates cannot be forwarded.');
    }
    final media = m.media;
    if (media == null) {
      await sendText(m.body);
      return;
    }
    if (media.storagePath == null) {
      throw const MediaValidationException('This file has not finished downloading yet.');
    }
    final tmp = File('${Directory.systemTemp.path}/fwd_${DateTime.now().microsecondsSinceEpoch}_${media.fileName}');
    await FirebaseStorage.instance.ref(media.storagePath!).writeToFile(tmp);
    final picked = await MediaService.validate(tmp.path, originalName: media.fileName);
    attachment = picked.withDuration(media.durationMs);
    sendAttachment(m.body);
  }

  /// Waits for in-flight uploads/requests to finish; returns the first error, if any.
  /// (Lets a short-lived controller — e.g. forwarding — outlive the UI that created it.)
  Future<String?> settle() async {
    while (_pending.values.any((p) => p.running)) {
      await Future<void>.delayed(const Duration(milliseconds: 200));
    }
    for (final p in _pending.values) {
      if (p.error != null) return p.error;
    }
    return null;
  }

  @override
  void dispose() {
    _disposed = true;
    _active = false;
    _windowTicker?.cancel();
    _msgSub?.cancel();
    _convSub?.cancel();
    _leadSub?.cancel();
    for (final p in _pending.values) {
      p.task?.cancel();
    }
    super.dispose();
  }
}
