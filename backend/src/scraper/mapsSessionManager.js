/**
 * Lets the app itself drive the Google sign-in the scraper needs, without
 * touching the terminal: report whether the saved session is signed in, and
 * open a VISIBLE browser window on this computer where the person signs in
 * by hand. (Same rules as scripts/mapsLogin.mjs: nothing here types
 * credentials, handles challenges, or reads cookies.)
 */

import { chromium } from 'playwright';
import {
  getSessionConfig,
  ensureProfileDir,
  findChrome,
  hasGoogleSignInCookies,
  waitForProfileFree,
  launchManualLogin,
  launchSessionBrowser,
  checkSessionStatus,
} from './mapsSession.js';
import { BROWSER_ARGS, CONTEXT_OPTIONS, isSessionProfileInUse } from './googleMapsScraper.js';

const CACHE_MS = 60_000;

let last = null; // { status, detail, checkedAt }
let login = null; // { startedAt } while the sign-in window is open
let inflight = null; // the check currently running, shared by everyone who asks

function remember(result) {
  last = { status: result.status, detail: result.detail || '', checkedAt: Date.now() };
  return last;
}

/**
 * One real check at a time: a profile can only be open in one browser, so two
 * overlapping checks (the background one after sign-in, and a page polling)
 * would make one of them report "locked". Callers share the running one.
 */
function runCheck() {
  if (inflight) return inflight;
  const cfg = getSessionConfig();
  inflight = checkSessionStatus({
    chromium,
    profileDir: cfg.profileDir,
    channel: cfg.channel,
    args: BROWSER_ARGS,
    contextOptions: CONTEXT_OPTIONS,
    chromePath: cfg.chromePath || undefined,
  })
    .then(remember)
    .finally(() => {
      inflight = null;
    });
  return inflight;
}

/** What the scan page needs to know. Cheap unless `refresh` forces a real check. */
export async function getSessionSnapshot({ refresh = false } = {}) {
  const cfg = getSessionConfig();
  const base = { mode: cfg.mode, enabled: cfg.enabled, profileDir: cfg.profileDir };

  if (login) return { ...base, status: 'login_in_progress', inUseByScan: false, loginInProgress: true, detail: '' };

  if (isSessionProfileInUse()) {
    // A scan holds the profile (so it is signed in as far as we can tell).
    return { ...base, status: last?.status ?? 'in_use', inUseByScan: true, loginInProgress: false, detail: 'A scan is using the Google session.' };
  }

  if (!refresh && last && Date.now() - last.checkedAt < CACHE_MS) {
    return { ...base, status: last.status, inUseByScan: false, loginInProgress: false, detail: last.detail };
  }

  const result = await runCheck();
  return { ...base, status: result.status, inUseByScan: false, loginInProgress: false, detail: result.detail || '' };
}

/**
 * Opens the sign-in window and returns at once; when the person closes it the
 * session is re-checked in the background (see `getSessionSnapshot`).
 */
export async function startLogin() {
  const fail = (status, message) => Object.assign(new Error(message), { status });
  if (login) return { started: false, alreadyOpen: true };
  if (isSessionProfileInUse()) {
    throw fail(409, 'A scan is using the Google session. Stop the scan first, then sign in.');
  }

  const cfg = getSessionConfig();
  ensureProfileDir(cfg.profileDir);

  // Preferred: the real Chrome as an ordinary window, nothing driving it,
  // because Google refuses sign-in inside automation-controlled browsers.
  const chrome = findChrome();
  if (chrome) {
    const { child, closed } = launchManualLogin({ executable: chrome, profileDir: cfg.profileDir });
    login = { startedAt: Date.now() };
    const early = await Promise.race([closed, new Promise((r) => setTimeout(() => r(null), 1500))]);
    if (early !== null) {
      // It ended almost at once: it did not open (or handed over to a Chrome
      // already using this profile).
      login = null;
      throw fail(
        409,
        early === 0
          ? 'This Google profile is already open in another Chrome window. Use that window, or close it and try again.'
          : 'Chrome could not be opened for sign-in.'
      );
    }

    // Done when the window's Chrome exits, or as soon as the sign-in shows up
    // in the profile: on macOS closing the last window does NOT quit Chrome,
    // so waiting for it to exit would wait forever.
    let finished = false;
    const finish = async () => {
      if (finished) return;
      finished = true;
      clearInterval(poll);
      await waitForProfileFree(cfg.profileDir); // helpers can outlive the main process
      login = null;
      last = null; // force a fresh check next time
      runCheck().catch(() => {});
    };
    const poll = setInterval(async () => {
      if (finished || !(await hasGoogleSignInCookies(cfg.profileDir))) return;
      clearInterval(poll);
      // Give Chrome a moment to finish writing, then close its window ourselves
      // (a profile can only be open in one browser, and the scanner needs it).
      await new Promise((r) => setTimeout(r, 4000));
      child.kill('SIGTERM');
      await new Promise((resolve) => {
        const t = setTimeout(() => {
          child.kill('SIGKILL');
          resolve();
        }, 10000);
        child.once('exit', () => {
          clearTimeout(t);
          resolve();
        });
        if (child.exitCode !== null) {
          clearTimeout(t);
          resolve();
        }
      });
      finish();
    }, 3000);
    closed.then(finish);
    return { started: true, browser: 'chrome' };
  }

  let browser;
  try {
    // A plain window, no custom user agent or stealth flags: a person signing in.
    browser = await launchSessionBrowser({
      chromium,
      profileDir: cfg.profileDir,
      channel: cfg.channel,
      args: [],
      contextOptions: { locale: 'en-US', viewport: null },
      headless: false,
    });
  } catch (err) {
    const msg = (err?.message || String(err)).split('\n')[0];
    throw fail(
      409,
      /ProcessSingleton|SingletonLock|already in use/i.test(msg)
        ? 'The Google profile is already open in another browser window. Close it and try again.'
        : `Could not open the sign-in window: ${msg}`
    );
  }

  login = { startedAt: Date.now() };
  browser.context.on('close', () => {
    login = null;
    last = null; // force a fresh check next time
    runCheck().catch(() => {});
  });

  const page = await browser.context.newPage();
  await page.goto('https://accounts.google.com/', { waitUntil: 'domcontentloaded' }).catch(() => {});
  return { started: true };
}

/** Test hook. */
export function _resetSessionManager() {
  last = null;
  login = null;
  inflight = null;
}
