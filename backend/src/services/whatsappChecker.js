/**
 * Free WhatsApp availability check via public click-to-chat pages (Playwright).
 * No paid WhatsApp Business API.
 */

import { chromium } from 'playwright';

const USER_AGENT =
  'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36';

const INVALID_PATTERNS = [
  /phone number shared via url is invalid/i,
  /phone number shared via url is not valid/i,
  /invalid phone number/i,
  /number you entered is not a valid/i,
  /not a valid phone number/i,
];

const AVAILABLE_PATTERNS = [
  /continue to chat/i,
  /continue to whatsapp/i,
  /chat on whatsapp/i,
  /open whatsapp/i,
  /send message/i,
  /use whatsapp web/i,
];

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

async function launchBrowser() {
  return chromium.launch({
    headless: true,
    args: [
      '--disable-blink-features=AutomationControlled',
      '--no-sandbox',
      '--disable-dev-shm-usage',
      '--lang=en-US',
    ],
  });
}

async function createContext(browser) {
  return browser.newContext({
    userAgent: USER_AGENT,
    locale: 'en-US',
    extraHTTPHeaders: { 'Accept-Language': 'en-US,en;q=0.9' },
    viewport: { width: 1280, height: 800 },
  });
}

function matchesAny(text, patterns) {
  return patterns.some((re) => re.test(text));
}

/**
 * Check a single phone number for WhatsApp availability.
 * @returns {{ available: boolean, e164: string|null, waLink: string|null, reason?: string }}
 */
export async function checkWhatsAppAvailable(phone, { browser } = {}) {
  const e164 = normalizeUsPhone(phone);
  if (!e164) {
    return { available: false, e164: null, waLink: null, reason: 'invalid_format' };
  }

  const waLink = waMeLink(e164);
  const ownBrowser = !browser;
  let localBrowser = browser;
  let context;
  let page;

  try {
    if (ownBrowser) localBrowser = await launchBrowser();
    context = await createContext(localBrowser);
    page = await context.newPage();

    const url = `https://api.whatsapp.com/send/?phone=${e164}&text&type=phone_number&app_absent=0`;
    await page.goto(url, { waitUntil: 'domcontentloaded', timeout: 25000 });
    await page.waitForTimeout(1800);

    const bodyText = await page.locator('body').innerText().catch(() => '');
    const title = await page.title().catch(() => '');
    const combined = `${title}\n${bodyText}`;

    if (matchesAny(combined, INVALID_PATTERNS)) {
      return { available: false, e164, waLink, reason: 'invalid_or_not_on_whatsapp' };
    }

    if (matchesAny(combined, AVAILABLE_PATTERNS)) {
      return { available: true, e164, waLink };
    }

    // Fallback: wa.me often redirects; absence of invalid copy + presence of phone in URL ≈ ok
    const currentUrl = page.url();
    if (/whatsapp\.com/i.test(currentUrl) && !matchesAny(combined, INVALID_PATTERNS)) {
      // Prefer continue/chat UI; if page only shows generic landing without error, treat as available
      const hasChatCta = await page
        .locator('a[href*="whatsapp"], a[href*="wa.me"], #action-button, a#action-button')
        .count()
        .catch(() => 0);
      if (hasChatCta > 0) {
        return { available: true, e164, waLink };
      }
    }

    return { available: false, e164, waLink, reason: 'unconfirmed' };
  } catch (err) {
    return {
      available: false,
      e164,
      waLink,
      reason: `check_failed: ${err.message}`,
    };
  } finally {
    try {
      await page?.close();
    } catch {
      /* ignore */
    }
    try {
      await context?.close();
    } catch {
      /* ignore */
    }
    if (ownBrowser && localBrowser) {
      try {
        await localBrowser.close();
      } catch {
        /* ignore */
      }
    }
  }
}

/**
 * Filter leads to those with WhatsApp-available phones.
 * Reuses one browser for the batch.
 *
 * @param {Array} leads
 * @param {{ onProgress?: (msg: string, i: number, total: number) => void, delayMs?: number }} options
 * @returns {Promise<Array>} leads with hasWhatsApp, waLink, normalized phone
 */
export async function filterLeadsWithWhatsApp(leads, { onProgress, delayMs = 700 } = {}) {
  const list = Array.isArray(leads) ? leads : [];
  if (!list.length) return [];

  const withPhone = list.filter((l) => normalizeUsPhone(l.phone));
  const total = withPhone.length;
  if (!total) return [];

  onProgress?.(`Checking WhatsApp on ${total} numbers...`, 0, total);

  const browser = await launchBrowser();
  const kept = [];

  try {
    for (let i = 0; i < withPhone.length; i++) {
      const lead = withPhone[i];
      onProgress?.(
        `Checking WhatsApp (${i + 1}/${total}): ${lead.business || lead.phone}`,
        i + 1,
        total
      );

      const result = await checkWhatsAppAvailable(lead.phone, { browser });
      if (result.available) {
        kept.push({
          ...lead,
          phone: result.e164 ? `+${result.e164}` : lead.phone,
          hasWhatsApp: true,
          waLink: result.waLink,
        });
      }

      if (i < withPhone.length - 1 && delayMs > 0) {
        await new Promise((r) => setTimeout(r, delayMs));
      }
    }
  } finally {
    try {
      await browser.close();
    } catch {
      /* ignore */
    }
  }

  return kept;
}
