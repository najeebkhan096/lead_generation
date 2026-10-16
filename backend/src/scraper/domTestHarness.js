/**
 * Shared setup for tests that drive Playwright against local HTML fixtures.
 * Never touches Google. If Chromium is not installed the DOM tests are
 * skipped (reported as skipped, not passed) instead of failing the suite.
 */
import { before, after, test } from 'node:test';
import { chromium } from 'playwright';

export function useChromium() {
  const state = { browser: null, error: null };
  before(async () => {
    try {
      state.browser = await chromium.launch({ headless: true });
    } catch (err) {
      state.error = (err?.message || String(err)).split('\n')[0];
    }
  });
  after(async () => {
    await state.browser?.close();
  });

  /** A test that receives a fresh page, or is skipped when Chromium is unavailable. */
  return function domTest(name, fn) {
    test(name, async (t) => {
      if (!state.browser) return t.skip(`Chromium unavailable: ${state.error}`);
      const page = await state.browser.newPage();
      try {
        await fn(page);
      } finally {
        await page.close();
      }
    });
  };
}
