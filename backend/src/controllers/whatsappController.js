import { normalizePhone, waMeLink } from '../services/whatsappChecker.js';

/**
 * POST /api/whatsapp/check — validate a phone number's format and build its
 * wa.me link.
 *
 * NOTE: WhatsApp does not expose registration status via any public,
 * unauthenticated endpoint, so this cannot confirm whether the number is
 * actually on WhatsApp — only that it's a plausible phone number. The
 * client should open `waLink` to get a real answer from WhatsApp itself.
 */
export function checkWhatsAppNumber(req, res) {
  const phone = (req.body?.phone ?? req.query.phone ?? '').toString().trim();
  const country = (req.body?.country ?? req.query.country ?? 'US').toString();
  if (!phone) {
    return res.status(400).json({ error: 'Phone number is required', validFormat: false });
  }

  const e164 = normalizePhone(phone, country);
  if (!e164) {
    return res.status(400).json({ error: 'Enter a valid phone number', validFormat: false });
  }

  return res.json({ validFormat: true, e164, waLink: waMeLink(e164) });
}
