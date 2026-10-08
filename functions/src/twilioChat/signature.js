import crypto from 'crypto';

/** Twilio X-Twilio-Signature: base64(HMAC-SHA1(token, url + sortedKey+value...)). */
export function computeTwilioSignature(authToken, url, params = {}) {
  const data = Object.keys(params)
    .sort()
    .reduce((acc, k) => acc + k + params[k], url);
  return crypto.createHmac('sha1', authToken).update(Buffer.from(data, 'utf-8')).digest('base64');
}

export function isValidTwilioSignature(authToken, signature, url, params) {
  if (!authToken || !signature) return false;
  const expected = Buffer.from(computeTwilioSignature(authToken, url, params));
  const given = Buffer.from(String(signature));
  return expected.length === given.length && crypto.timingSafeEqual(expected, given);
}
