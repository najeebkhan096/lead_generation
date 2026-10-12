/**
 * Pure validators/mappers for the Twilio WhatsApp chat. No I/O so they can be
 * unit-tested without Firebase or Twilio.
 */

// Conservative: Twilio documents 16 MB for WhatsApp media (one page says 20).
export const MAX_MEDIA_BYTES = 16 * 1024 * 1024;
export const MAX_TEXT_LENGTH = 4096;
export const WINDOW_MS = 24 * 60 * 60 * 1000;

// MIME -> { type, exts }. Based on Twilio's "Guidance on WhatsApp Media
// Messages". XLS and TXT are accepted but are not on Twilio's documented list:
// if Twilio/WhatsApp rejects them the message ends up `failed` with its code.
// ZIP is deliberately not allowed (not documented as supported).
export const ALLOWED_MIME = {
  'image/jpeg': { type: 'image', exts: ['jpg', 'jpeg'] },
  'image/png': { type: 'image', exts: ['png'] },
  'video/mp4': { type: 'video', exts: ['mp4'] },
  'video/3gpp': { type: 'video', exts: ['3gp', '3gpp'] },
  'audio/ogg': { type: 'audio', exts: ['ogg', 'opus'] },
  'audio/mpeg': { type: 'audio', exts: ['mp3'] },
  'audio/aac': { type: 'audio', exts: ['aac'] },
  'audio/amr': { type: 'audio', exts: ['amr'] },
  'application/pdf': { type: 'document', exts: ['pdf'] },
  'application/msword': { type: 'document', exts: ['doc'] },
  'application/vnd.openxmlformats-officedocument.wordprocessingml.document': { type: 'document', exts: ['docx'] },
  'application/vnd.ms-excel': { type: 'document', exts: ['xls'] },
  'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet': { type: 'document', exts: ['xlsx'] },
  'application/vnd.openxmlformats-officedocument.presentationml.presentation': { type: 'document', exts: ['pptx'] },
  'text/plain': { type: 'document', exts: ['txt'] },
};

export class HttpError extends Error {
  constructor(status, message, code) {
    super(message);
    this.status = status;
    this.code = code;
  }
}

/** Converts Arabic-Indic/Persian digits, strips separators; returns +digits. */
export function normalizePhone(input) {
  let s = String(input ?? '');
  s = s.replace(/[٠-٩]/g, (d) => String(d.charCodeAt(0) - 0x0660));
  s = s.replace(/[۰-۹]/g, (d) => String(d.charCodeAt(0) - 0x06f0));
  s = s.replace(/^whatsapp:/i, '').replace(/[\s\-().]/g, '');
  return s;
}

export function isValidE164(phone) {
  return /^\+[1-9]\d{7,14}$/.test(phone);
}

export function phoneDigits(phone) {
  return phone.replace(/\D/g, '');
}

export function leadIdFor(ownerId, phone) {
  return `${ownerId}_${phoneDigits(phone)}`;
}

export function baseMime(mime) {
  return String(mime ?? '').split(';')[0].trim().toLowerCase();
}

export function messageTypeForMime(mime) {
  return ALLOWED_MIME[baseMime(mime)]?.type
    ?? (baseMime(mime).startsWith('image/') ? 'image'
      : baseMime(mime).startsWith('video/') ? 'video'
      : baseMime(mime).startsWith('audio/') ? 'audio'
      : 'document');
}

export function extForMime(mime) {
  return ALLOWED_MIME[baseMime(mime)]?.exts[0] ?? 'bin';
}

/** Throws HttpError when the media descriptor is not acceptable. */
export function validateMediaMeta({ mimeType, fileName, size }) {
  const mime = baseMime(mimeType);
  const rule = ALLOWED_MIME[mime];
  if (!rule) {
    throw new HttpError(415, `File type "${mime || 'unknown'}" is not supported by WhatsApp via Twilio.`, 'UNSUPPORTED_MEDIA');
  }
  const ext = String(fileName ?? '').split('.').pop().toLowerCase();
  if (!rule.exts.includes(ext)) {
    throw new HttpError(415, `File extension ".${ext}" does not match type ${mime}.`, 'EXTENSION_MISMATCH');
  }
  if (!Number.isFinite(size) || size <= 0) {
    throw new HttpError(400, 'Media size is missing.', 'BAD_MEDIA');
  }
  if (size > MAX_MEDIA_BYTES) {
    throw new HttpError(413, `File is too large (max ${MAX_MEDIA_BYTES / 1024 / 1024} MB).`, 'MEDIA_TOO_LARGE');
  }
  return { mime, type: rule.type };
}

export function isWindowOpen(lastInboundAtMs, nowMs = Date.now()) {
  return typeof lastInboundAtMs === 'number' && nowMs - lastInboundAtMs < WINDOW_MS;
}

// ---- status lifecycle -------------------------------------------------------
const RANK = { sending: 1, sent: 2, delivered: 3, read: 4, failed: 5, undelivered: 5 };

/** Maps a raw Twilio MessageStatus to our lifecycle value (null = ignore). */
export function mapTwilioStatus(raw) {
  switch (String(raw ?? '').toLowerCase()) {
    case 'accepted':
    case 'scheduled':
    case 'queued':
    case 'sending':
      return 'sending';
    case 'sent':
      return 'sent';
    case 'delivered':
      return 'delivered';
    case 'read':
      return 'read';
    case 'failed':
      return 'failed';
    case 'undelivered':
      return 'undelivered';
    default:
      return null;
  }
}

/**
 * Returns the status to persist, or null when the callback must be ignored
 * (duplicate, out-of-order, or a failure arriving after delivery).
 */
export function nextStatus(current, incoming) {
  if (!incoming) return null;
  const cur = RANK[current] ?? 0;
  const inc = RANK[incoming];
  if (incoming === current) return null;
  if (inc >= 5) {
    // A failure never overrides delivered/read, nor an existing failure.
    return cur >= 3 ? null : incoming;
  }
  return inc > cur ? incoming : null;
}

const FRIENDLY_ERRORS = {
  21620: 'Twilio could not fetch the media URL.',
  21610: 'The recipient has opted out of messages.',
  63003: 'WhatsApp could not find this number.',
  63007: 'The WhatsApp sender is not configured correctly.',
  63015: 'Sandbox recipients must opt in first.',
  63016: 'Outside the 24-hour window: only approved templates can be sent.',
  63018: 'WhatsApp rate limit reached. Try again later.',
  63024: 'Invalid WhatsApp recipient.',
  63032: 'WhatsApp could not deliver to this user (policy restriction).',
  63049: 'WhatsApp blocked this marketing message for this user.',
  63051: 'The recipient could not be reached for this message.',
  63112: 'WhatsApp Business account is restricted.',
  63013: 'Message violates WhatsApp policy.',
  131026: 'The recipient is not a WhatsApp user or cannot receive this message.',
  131047: 'Re-engagement message required: send a template.',
  131049: 'WhatsApp declined to deliver this marketing message.',
};

export function describeTwilioError(code, fallback) {
  const n = Number(code);
  return FRIENDLY_ERRORS[n] ?? fallback ?? (code ? `Twilio error ${code}` : 'Message failed');
}

export function previewFor(type, body) {
  if (body) return String(body).slice(0, 200);
  switch (type) {
    case 'image': return '📷 Photo';
    case 'video': return '🎥 Video';
    case 'audio': return '🎤 Audio';
    case 'document': return '📄 Document';
    case 'template': return '📋 Template';
    default: return '';
  }
}
