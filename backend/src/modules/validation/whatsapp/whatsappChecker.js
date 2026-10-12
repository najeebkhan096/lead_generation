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
 * Calling code + local-dialing convention per country this app searches.
 * `stripLeadingZero`: most of Europe/Australia dial locally with a leading
 * trunk "0" that must be dropped before prepending the calling code (e.g.
 * German "030 1234567" -> "+49 30 1234567", not "+49 030 1234567" and
 * definitely not the bare "030 1234567" misread as if it were already
 * E.164 — which is exactly the bug this fixes: businesses scraped from
 * non-US countries were getting a bogus "+0..." number, since the old
 * US-only normalizer accepted any 11-15 digit string as already-valid
 * E.164 without checking it actually had a real country code.
 * Italy (`IT`) is a genuine exception: Italian numbers keep the leading 0
 * in international form for landlines, and mobiles never had one — so
 * nothing gets stripped there.
 */
const COUNTRY_PHONE_RULES = {
  US: { callingCode: '1', nanp: true },
  CA: { callingCode: '1', nanp: true },
  UK: { callingCode: '44', stripLeadingZero: true },
  DE: { callingCode: '49', stripLeadingZero: true },
  IT: { callingCode: '39', stripLeadingZero: false },
  FR: { callingCode: '33', stripLeadingZero: true },
  AU: { callingCode: '61', stripLeadingZero: true },
  AT: { callingCode: '43', stripLeadingZero: true },
  DK: { callingCode: '45', stripLeadingZero: false },
  ES: { callingCode: '34', stripLeadingZero: false },
  NL: { callingCode: '31', stripLeadingZero: true },
  BE: { callingCode: '32', stripLeadingZero: true },
  CH: { callingCode: '41', stripLeadingZero: true },
  SE: { callingCode: '46', stripLeadingZero: true },
};

/**
 * Normalize a scraped phone number to E.164 digits (no '+'), using the
 * country the lead was actually found in — a bare local-format number
 * means something completely different in each country, so "assume US"
 * (the old behavior) silently corrupted every non-US number.
 * @returns {string|null}
 */
export function normalizePhone(phone, country = 'US') {
  if (phone == null) return null;
  const raw = String(phone).trim();
  if (!raw) return null;

  const explicitlyInternational = raw.startsWith('+');
  let digits = raw.replace(/\D/g, '');
  if (!digits) return null;

  // "0049..." is a common way to write "+49..." without the plus sign.
  if (!explicitlyInternational && digits.startsWith('00')) {
    digits = digits.slice(2);
  }

  const rule = COUNTRY_PHONE_RULES[String(country || 'US').toUpperCase()] || COUNTRY_PHONE_RULES.US;

  if (rule.nanp) {
    if (digits.length === 10) digits = `1${digits}`;
    if (digits.length === 11 && digits.startsWith('1')) return digits;
    if (digits.length >= 11 && digits.length <= 15) return digits;
    return null;
  }

  // Already international (Google Maps sometimes shows it that way
  // directly) — trust it rather than re-adding the calling code on top.
  if (explicitlyInternational || digits.startsWith(rule.callingCode)) {
    return digits.length >= 8 && digits.length <= 15 ? digits : null;
  }

  if (rule.stripLeadingZero && digits.startsWith('0')) {
    digits = digits.slice(1);
  }

  if (digits.length < 6 || digits.length > 14) return null;
  return `${rule.callingCode}${digits}`;
}

export function waMeLink(e164) {
  return e164 ? `https://wa.me/${e164}` : null;
}
