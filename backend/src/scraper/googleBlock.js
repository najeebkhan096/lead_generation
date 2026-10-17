/**
 * Recognising Google's "unusual traffic" check.
 *
 * When Google decides a network is sending too many automated requests it
 * replaces results with a page saying "Our systems have detected unusual
 * traffic from your computer network... not a robot" (a /sorry/ URL, often
 * with a CAPTCHA). That is a request to slow down, not an error to retry
 * through. This module only RECOGNISES it so the scan can stop, wait and
 * come back later; it never tries to solve or get past the check.
 */

export class GoogleBlockedError extends Error {
  constructor(detail = '') {
    super(
      'Google is showing its "unusual traffic" check for this network, so scanning is paused. ' +
        'Scanning more would only make it last longer.' +
        (detail ? ` (${detail})` : '')
    );
    this.name = 'GoogleBlockedError';
    this.code = 'GOOGLE_BLOCKED';
  }
}

/** Pure test of a page's URL and visible text. */
export function isBlockedPage({ url = '', text = '' } = {}) {
  if (/^https?:\/\/(www\.)?google\.[a-z.]+\/sorry\//i.test(url)) return true;
  return /unusual traffic|not a robot|detected unusual traffic|recaptcha/i.test(String(text).slice(0, 1500));
}

/** Throws GoogleBlockedError if the page is Google's check. */
export async function throwIfBlocked(page) {
  let url = '';
  try {
    url = page.url();
  } catch {
    return;
  }
  let text = '';
  try {
    text = await page.evaluate(() => (document.body ? document.body.innerText.slice(0, 1500) : ''));
  } catch {
    // page mid-navigation: judge by the URL alone
  }
  if (isBlockedPage({ url, text })) throw new GoogleBlockedError(url.startsWith('http') ? new URL(url).pathname : '');
}
