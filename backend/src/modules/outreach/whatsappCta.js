/**
 * The "message us on WhatsApp" link added to outreach emails.
 *
 * WhatsApp does not allow business-initiated marketing templates to US
 * numbers (Twilio error 63049), but once a person messages the business
 * number first, a 24-hour window opens in which free text is allowed. The
 * email carries a wa.me link whose prefilled text names the business, so the
 * reply can be matched to the lead.
 */

/** Digits of a WhatsApp number (E.164 without the +), or '' when it is not usable. */
export function whatsappDigits(raw) {
  const digits = String(raw ?? '').replace(/\D/g, '');
  return digits.length >= 8 && digits.length <= 15 ? digits : '';
}

const PREFILL_RE = /email about (.+?)\.?\s*$/i;

export function whatsappChatUrl(number, business) {
  const digits = whatsappDigits(number);
  if (!digits) return '';
  const name = String(business ?? '').trim().slice(0, 120);
  const text = name ? `Hi, I got your email about ${name}.` : 'Hi, I got your email.';
  return `https://wa.me/${digits}?text=${encodeURIComponent(text)}`;
}

/** Business name carried by the prefilled text of [whatsappChatUrl], or ''. */
export function businessFromPrefill(message) {
  const first = String(message ?? '').split('\n')[0];
  return (PREFILL_RE.exec(first)?.[1] ?? '').trim().slice(0, 160);
}

/** Appends the link once; unchanged when disabled, unconfigured, or already present. */
export function appendWhatsAppCta(body, { number, business, enabled = true } = {}) {
  const url = whatsappChatUrl(number, business);
  const text = String(body ?? '');
  if (!enabled || !url || /wa\.me\//i.test(text)) return text;
  return `${text.trim()}\n\nPrefer WhatsApp? Message me directly:\n${url}`;
}
