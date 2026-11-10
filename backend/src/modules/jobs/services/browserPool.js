/**
 * One shared headless browser for the Jobs module — used only to read career
 * pages that render their listings with JavaScript.
 *
 *  - launched lazily and once (concurrent callers share the in-flight launch),
 *  - relaunched if it died,
 *  - at most `maxPages` pages open at a time, each in its own throw-away
 *    context (no cookies or storage shared between sites),
 *  - closed after a quiet period so an idle server holds no Chrome,
 *  - separate from the Google Maps scan's browser and profile — it never
 *    touches the signed-in Google session.
 *
 * It does not hide automation, rotate fingerprints or solve challenges: if a
 * site shows a bot wall, the caller reports it as blocked and moves on.
 *
 * Environment: JOBS_BROWSER_ENABLED=false turns it off;
 * JOBS_BROWSER_CHANNEL=chrome uses installed Chrome instead of Playwright's
 * bundled Chromium; JOBS_BROWSER_EXECUTABLE=/path for a specific binary.
 */

import { SourceError } from '../utils/errors.js';
import { DEFAULT_USER_AGENT } from '../utils/http.js';

const IDLE_CLOSE_MS = 90_000;
const NAV_TIMEOUT_MS = 25_000;

export function createBrowserPool({
  launch = defaultLaunch,
  maxPages = 2,
  idleCloseMs = IDLE_CLOSE_MS,
  enabled = process.env.JOBS_BROWSER_ENABLED !== 'false',
  log = { warn() {}, info() {} },
} = {}) {
  let browser = null;
  let launching = null;
  let active = 0;
  const waiters = [];
  let idleTimer = null;

  async function ensureBrowser() {
    if (browser && browser.isConnected()) return browser;
    if (!launching) {
      launching = launch()
        .then((b) => {
          browser = b;
          b.on?.('disconnected', () => {
            if (browser === b) browser = null;
          });
          return b;
        })
        .finally(() => {
          launching = null;
        });
    }
    return launching;
  }

  async function slot() {
    if (active < maxPages) {
      active += 1;
      return;
    }
    await new Promise((resolve) => waiters.push(resolve));
    active += 1;
  }

  function release() {
    active -= 1;
    waiters.shift()?.();
    if (active === 0) {
      clearTimeout(idleTimer);
      idleTimer = setTimeout(() => pool.close().catch(() => {}), idleCloseMs);
      idleTimer.unref?.();
    }
  }

  const pool = {
    get enabled() {
      return enabled;
    },

    /**
     * Opens [url] in a fresh context and returns the rendered HTML.
     * @throws {SourceError}
     */
    async render(url, { timeoutMs = NAV_TIMEOUT_MS, waitForSelector } = {}) {
      if (!enabled) throw new SourceError('not_configured', 'The browser fallback is disabled (JOBS_BROWSER_ENABLED=false)', { retryable: false });
      await slot();
      clearTimeout(idleTimer);
      let context;
      try {
        const b = await ensureBrowser();
        context = await b.newContext({ userAgent: DEFAULT_USER_AGENT, locale: 'en-US' });
        const page = await context.newPage();
        page.setDefaultTimeout(timeoutMs);
        // Pages are read for text: skip the heavy stuff.
        await page.route('**/*', (route) => (['image', 'media', 'font'].includes(route.request().resourceType()) ? route.abort() : route.continue()));
        const response = await page.goto(url, { waitUntil: 'domcontentloaded', timeout: timeoutMs });
        const status = response?.status() ?? 0;
        if (status === 404 || status === 410) throw new SourceError('not_found', `HTTP ${status}`, { status, retryable: false });
        if ([401, 403, 451].includes(status)) throw new SourceError('blocked', `HTTP ${status} (access denied — not bypassed)`, { status, retryable: false });
        if (status === 429) throw new SourceError('rate_limited', 'HTTP 429', { status, retryable: true });
        if (status >= 500) throw new SourceError('http_error', `HTTP ${status}`, { status, retryable: true });
        if (waitForSelector) await page.waitForSelector(waitForSelector, { timeout: 8_000 }).catch(() => {});
        else await page.waitForLoadState('networkidle', { timeout: 8_000 }).catch(() => {});
        return { html: await page.content(), url: page.url() };
      } catch (err) {
        if (err instanceof SourceError) throw err;
        const timedOut = err?.name === 'TimeoutError';
        if (/Executable doesn't exist|browserType\.launch|Failed to launch/i.test(String(err?.message))) {
          throw new SourceError('not_configured', 'No browser available: run `npx playwright install chromium` or set JOBS_BROWSER_CHANNEL=chrome', { retryable: false, cause: err });
        }
        log.warn('browser render failed', { error: err });
        throw new SourceError(timedOut ? 'timeout' : 'network', timedOut ? 'Page did not load in time' : 'Browser error', { retryable: true, cause: err });
      } finally {
        await context?.close().catch(() => {});
        release();
      }
    },

    async close() {
      clearTimeout(idleTimer);
      const b = browser;
      browser = null;
      if (b) await b.close().catch(() => {});
    },

    /** For diagnostics/tests. */
    stats: () => ({ active, queued: waiters.length, running: Boolean(browser) }),
  };
  return pool;
}

async function defaultLaunch() {
  const { chromium } = await import('playwright');
  const options = { headless: true };
  const channel = process.env.JOBS_BROWSER_CHANNEL?.trim();
  if (channel) options.channel = channel;
  if (process.env.JOBS_BROWSER_EXECUTABLE?.trim()) options.executablePath = process.env.JOBS_BROWSER_EXECUTABLE.trim();
  return chromium.launch(options);
}

/** Process-wide pool. */
export const browserPool = createBrowserPool();
