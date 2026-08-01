/**
 * Phone number formatting for WhatsApp click-to-chat links.
 *
 * WhatsApp does not expose registration status through any public,
 * unauthenticated endpoint — the "isn't on WhatsApp" message is only
 * produced inside an authenticated client (app or logged-in WhatsApp Web)
 * when a chat is actually opened. So this module only validates phone
 * format and builds a wa.me deep link; the caller opens it to get a real
 * answer straight from WhatsApp.
 */

/**
 * Normalize a US (or already +1) phone to E.164 digits without '+'.
 * @returns {string|null}
 */
export function normalizeUsPhone(phone) {
  if (phone == null) return null;
  let digits = String(phone).replace(/\D/g, '');
  if (!digits) return null;

  // Strip leading international 00
  if (digits.startsWith('00')) digits = digits.slice(2);

  if (digits.length === 10) digits = `1${digits}`;
  if (digits.length === 11 && digits.startsWith('1')) {
    return digits;
  }

  // Allow other country codes only when length looks plausible (11–15)
  if (digits.length >= 11 && digits.length <= 15) {
    return digits;
  }

  return null;
}

export function waMeLink(e164) {
  return e164 ? `https://wa.me/${e164}` : null;
}
