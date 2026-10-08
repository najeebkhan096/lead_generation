# Twilio WhatsApp Outreach — How It Works

**Firebase only — no server to run.** The logic lives in Cloud Functions (`functions/`):

```
 Mobile app (Flutter)                  Cloud Functions (functions/)                 Twilio
 ───────────────────                   ────────────────────────────                 ──────
 Firestore ◄── realtime streams ─────  writes messages / statuses (Admin SDK)
 Storage   ──► uploads media ────────► outreachApi (callable, Firebase Auth) ──────► sends WhatsApp
 callable  ──► outreachApi({action}) ─►                                                  │
                                       ◄── twilioIncoming / twilioStatus webhooks ◄─────┘
```

* **No Twilio credentials in the app.** They live in `functions/.env` (gitignored, deployed with the functions).
  The app calls the `outreachApi` callable; Firebase Auth identifies the user and the function checks `users/{uid}.approved`.
* **No polling.** Incoming messages and status changes arrive via the two webhook functions → Firestore → the app's listeners.
* A Twilio `201` is **not** "delivered": a message stays `sending` until Twilio's status callback says otherwise.
* `backend/src/services/twilioChat` (Express) is the original implementation of the same logic and is no longer used by
  the app; `functions/src/twilioChat` is a copy adapted for Functions (token download URLs instead of IAM-signed URLs;
  media is copied before the webhook responds because Functions throttle CPU after the response).

## Deploy (one time)

1. Firebase **Blaze** plan (Cloud Functions requires it; Twilio is the only real cost driver).
2. `cd functions && npm install && cd .. && firebase deploy --only functions,firestore:rules,storage`
3. In the Twilio console set the WhatsApp sender's / Messaging Service's **incoming message webhook** to
   `https://us-central1-whatsapplead-a8d9a.cloudfunctions.net/twilioIncoming` (POST). If `firebase deploy` prints a
   different URL for `twilioIncoming`, set `PUBLIC_BASE_URL` in `functions/.env` to its origin (everything before
   `/twilioIncoming`) and redeploy — the signature check must see the exact URL Twilio calls.
4. Optional in `functions/.env`: `OUTREACH_DEFAULT_OWNER_UID=<your uid>` to keep inbound messages from numbers that match no lead.

Callable actions: `text, media, template, retry, refresh, react, ensureLead, importTwilio, backfill` (same payloads as the REST
table in §2; errors come back as Firebase `HttpsError` with the app-level code in `details.code`, e.g. `WINDOW_CLOSED`).

## 1. Code map

| Area | Files |
|---|---|
| Entry widget (own Navigator + WhatsApp-green theme) | `mobile/lib/features/twilio_outreach/twilio_outreach_page.dart` |
| Pages | `pages/lead_list_page.dart`, `pages/chat_page.dart`, `pages/lead_picker.dart` |
| State | `controllers/chat_controller.dart` (streams, optimistic sends, upload/retry) |
| Data | `services/outreach_repository.dart` (Firestore + legacy migration), `services/outreach_api.dart` (backend client), `services/media_service.dart` (pick / validate / upload), `services/template_image.dart` (template header image) |
| Models | `models/outreach_lead.dart`, `models/outreach_message.dart` |
| Widgets | `widgets/message_bubble.dart`, `composer.dart`, `media_content.dart`, `media_viewers.dart`, `status_ticks.dart` |
| Backend | `backend/src/services/twilioChat/{messageService,twilioClient,validation,signature}.js`, `controllers/twilioChatController.js`, `routes/twilioChatRoutes.js`, `middleware/firebaseAuth.js` |
| Rules | `firestore.rules`, `storage.rules` |

## 2. API (callable actions; originally REST under `/api/outreach`)

Authenticated (`Authorization: Bearer <Firebase ID token>`), mounted under `/api/outreach` (before the e-mail outreach router):

| Endpoint | Body | Notes |
|---|---|---|
| `POST /messages/text` | `leadId, messageId, body, replyToMessageId?` | 409 `WINDOW_CLOSED` outside the 24 h window |
| `POST /messages/media` | `leadId, messageId, media{storagePath,mimeType,size,durationMs?}, caption?` | file must already be at `outreach_media/{uid}/{leadId}/{messageId}/…`; `media.voice: true` marks a recorded voice note (AAC/m4a) which the backend converts to OGG/Opus with ffmpeg before sending; backend re-checks existence, size, MIME, extension, then hands Twilio a 24 h signed URL |
| `POST /messages/template` | `leadId, messageId, mediaUrl` | `mediaUrl` = Firebase download URL of the header image (must be in the caller's `outreach_images/{uid}/`) |
| `POST /messages/retry` | `leadId, messageId` | re-sends a `failed`/`undelivered` message |
| `POST /messages/react` | `leadId, messageId, emoji \| null` | stores `reactions.<uid>` on the message (null removes). **Inbox-only** — see §9 |
| `POST /messages/refresh` | `leadId, messageId` | optional: pulls one message's status from Twilio |
| `POST /leads` | `name, businessName, phoneNumber` | idempotent; creates lead + conversation |
| `POST /leads/import-twilio` | — | optional: leads from the last 200 Twilio messages |
| `POST /leads/:leadId/backfill` | — | optional: copies Twilio's existing history for one lead into Firestore |

Twilio webhooks (no Firebase auth; protected by `X-Twilio-Signature`, HMAC-SHA1 over `PUBLIC_BASE_URL + originalUrl + sorted params`):

| Endpoint | Purpose |
|---|---|
| `POST /api/twilio/webhooks/incoming` | stores the message (doc id = Twilio SID ⇒ duplicate webhooks are no-ops), bumps unread + opens the 24 h window, then downloads media into Storage after answering Twilio |
| `POST /api/twilio/webhooks/status?c=<conv>&m=<msg>` | applies `sent/delivered/read/failed/undelivered` (order-safe: never goes backwards, a failure never overrides delivered/read) |

Messages are created by the backend **before** calling Twilio, so a crash never loses a message; `messageId` makes sends idempotent.

## 3. Firestore schema

`outreachLeads/{leadId}` — `leadId = "<ownerUid>_<phone digits>"` (one lead per phone per user)
`id, ownerId, name, businessName, phoneNumber (E.164), profileImage, createdAt, updatedAt, lastMessage (already a preview: text / "📷 Photo" / "🎥 Video" / "🎤 Audio" / "📄 Document"), lastMessageType, lastMessageAt, unreadCount`

`outreachConversations/{leadId}` — `id, ownerId, leadId, phoneNumber, lastInboundAt, lastOutboundAt, createdAt` (conversationId == leadId: one thread per lead, so nothing is duplicated)

`outreachConversations/{leadId}/messages/{messageId}`
`id, conversationId, leadId, direction (inbound|outbound), type (text|image|video|audio|document|template), body, media{storagePath, mimeType, fileName, size, durationMs?, error?, voice?, playbackPath?}, template{contentSid, variables}, twilioSid, status (sending|sent|delivered|read|failed|undelivered), senderId, createdAt, sentAt, deliveredAt, readAt, failedAt, errorCode, errorMessage, replyToMessageId, deletedAt, reactions{<uid>: emoji}`

Voice notes: `storagePath` is the OGG/Opus that was sent to WhatsApp; `playbackPath` is the recorded AAC original the app plays (iOS cannot play OGG).

All timestamps are Firestore `Timestamp`s. Deviation from the brief: `media.downloadUrl` is **not** stored — the app resolves `storagePath` through the Storage SDK so Storage rules always apply.

## 4. Storage

* `outreach_media/{uid}/{conversationId}/{messageId}/{file}` — chat attachments (outgoing uploaded by the app, incoming copied by the backend). Owner-only read; create-only (no overwrite); ≤ 16 MB; MIME allow-list.
* `outreach_images/{uid}/{ts}.jpg` — template header images (unchanged). Read stays "any signed-in user" because the template URL carries a download token.

## 5. Template messages (unchanged behaviour)

The approved template's media URL is `<TWILIO_TEMPLATE_MEDIA_PREFIX>{{1}}`, so variable `1` is **only** the part after `/o/`
(`outreach_images%2F…jpg?alt=media&token=…`). The backend strips the prefix (and refuses URLs outside the caller's
folder). Sending the full URL causes Twilio error 21620. Template messages are now stored as `type: template` with
`template.contentSid/variables` + `media`, so they survive reopening the app.

## 6. Message features

* Statuses: spinner → ✓ sent → ✓✓ delivered → blue ✓✓ read → red ! failed/undelivered. Tap a failed bubble for the reason + **Retry**.
* 24 h window: derived from the lead's last inbound message (`lastInboundAt`; Twilio exposes no window state). Outside it the composer is replaced by an explanation + **Send template**; the backend enforces it too.
* Composer: camera, gallery, video (gallery / record), document, audio file; **voice-note recorder** (mic button when the field is empty: timer, cancel, send; max 5 min); preview, caption, cancel, progress, failure + retry.
* Long-press: **emoji reactions** (👍 ❤️ 😂 😮 😢 🙏, tap again to remove), Reply (quoted preview, `replyToMessageId`), Copy, **Save / share file** (system share sheet), Forward (text and files; templates can't be forwarded), Delete, Retry, Message info (timestamps, Twilio SID, error, "Refresh status").
* Pagination: the chat streams the newest 50 messages and widens the query by 50 each time you scroll to the top (spinner while loading) until history is exhausted.
* Chat: date separators (Today/Yesterday), grouping, unread badges (cleared on open), scroll-to-bottom button, loading/empty/error states.
* Migration: on first open, leads in the old `SharedPreferences` key `saved_clients` are created in Firestore through `POST /leads`; the local copy is left as a backup. Existing conversations are pulled in lazily by `backfill` the first time an empty chat opens.

## 7. Configuration

Environment (`functions/.env`; the old Express backend reads the same names from `backend/.env`):

| Var | Purpose |
|---|---|
| `TWILIO_ACCOUNT_SID`, `TWILIO_AUTH_TOKEN` | credentials (backend only) |
| `TWILIO_MESSAGING_SERVICE_SID` | sender pool (`MG…`) |
| `TWILIO_TEMPLATE_CONTENT_SID` | approved template (`HX…`) |
| `TWILIO_TEMPLATE_MEDIA_PREFIX` | optional; defaults to the project's `…/o/` prefix |
| `PUBLIC_BASE_URL` | public HTTPS origin of the backend: status-callback URL + webhook signature validation |
| `OUTREACH_DEFAULT_OWNER_UID` | optional: owner for inbound messages from numbers that match no lead |
| `FIREBASE_*` | already used by the backend |

Twilio console: set the WhatsApp sender's / Messaging Service's **incoming message webhook** to
`https://<PUBLIC_BASE_URL>/api/twilio/webhooks/incoming` (HTTP POST). Status callbacks are attached per message, no console setting needed.

Mobile: nothing to configure — the app calls the `outreachApi` function through the Firebase SDK (`cloud_functions`).
Deploy rules: `firebase deploy --only functions,firestore:rules,storage`.

Packages added: mobile `file_picker`, `record`, `share_plus`; backend `ffmpeg-static` (voice-note conversion; downloads a binary at `npm install`). iOS `Info.plist`: microphone string; Android: `RECORD_AUDIO`.

## 8. Tests

* `cd functions && npm test` / `npm run test:emulator` — the same suites against the Functions copy (plus callable approval gating and signed-webhook tests). Legacy: `cd backend && npm run test:twilio` — unit tests (validation, status lifecycle, signature incl. Twilio's published vector, template-URL contract).
* `cd backend && npm run test:twilio:emulator` — send/retry/status/inbound/media-copy/window/ownership/duplicate-callback logic and the HTTP signature + auth layer against the Firestore + Storage emulators with Twilio mocked (needs Java ≥ 21).
* `cd scripts/rules-test && npm i && npm test` — Firestore + Storage security rules in the emulators.
* `cd mobile && flutter test test/outreach_logic_test.dart`.

## 9. Limitations / not implemented

* **Real Twilio / WhatsApp delivery, real devices, the webhook path from the public internet, and the Firebase-ID-token check against production were not exercised** (no credentials / device available). Everything Twilio-facing is verified only against a mock.
* **Reactions are inbox-only.** No documented Twilio WhatsApp API sends a reaction, so the contact never sees them; they are stored per user in Firestore and shown in our chat.
* **Quoted replies are local to our inbox.** Twilio's WhatsApp API cannot send a native reply-to, so the recipient does not see the quote; only `replyToMessageId` is stored.
* **Delete is "delete for me"** (hidden in our inbox). WhatsApp can't recall a sent message through Twilio.
* **Voice notes are recorded as AAC/m4a and converted server-side to OGG/Opus** (the only format WhatsApp plays as a native voice note; the `record` package's iOS Opus output is CAF, not OGG). The conversion is tested against ffmpeg; the *recording* itself has not been run on a device. Audio *files* are supported: MP3 / AAC / OGG(Opus) / AMR. M4A/WAV are rejected with a clear message. Playback uses `video_player`; OGG won't play inside iOS (the app offers "open in another app").
* **ZIP is not allowed** (not in Twilio's documented WhatsApp media list). XLS and TXT are allowed but are not on that list either: if WhatsApp rejects them the message ends `failed` with Twilio's error code.
* Twilio documents the media limit as 16 MB on one page and 20 MB on another; 16 MB is enforced. Videos are not transcoded: >16 MB is rejected. Twilio ignores captions on documents/audio and only supports MP4 (H.264/AAC) video.
* Video "thumbnails" are the first decoded frame (via `video_player`), not a pre-rendered image; downloads go through the system share sheet (Save to Files / other apps), not straight to the gallery.
* Read receipts only arrive when the recipient has them enabled. Status callbacks need `PUBLIC_BASE_URL`; without it messages stay `sending` until "Refresh status".
* Inbound messages from unknown numbers are dropped (logged) unless `OUTREACH_DEFAULT_OWNER_UID` is set. With a shared sender number, an inbound message goes to the user who most recently wrote to that number.
* `GET /conversations/:id` from the brief was not built: the app reads Firestore directly.
* `widget_navigation_test.dart` fails on a clean checkout too (it makes a real HTTP request); unrelated to this change.
