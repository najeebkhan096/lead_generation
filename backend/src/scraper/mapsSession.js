/**
 * Optional, manually authenticated Google session for the Maps scraper.
 *
 * Google shows anonymous visitors only a few reviews and asks them to sign in
 * before sorting. This lets YOU sign in once, in a visible browser window with
 * a dedicated Google account, and the scraper reuse that browser profile.
 *
 * What this never does: type credentials, drive Google's login, solve or skip
 * CAPTCHAs / verification challenges, or read the profile's cookies. The login
 * is done by a person (see scripts/mapsLogin.mjs). If the session is missing,
 * locked or expired the scraper carries on anonymously.
 */

import fs from 'node:fs';
import { spawn } from 'node:child_process';
import os from 'node:os';
import path from 'node:path';

const TRUE = /^(1|true|yes|on)$/i;

/** Default profile location: outside the repository, so it can never be committed. */
export function defaultProfileDir() {
  return path.join(os.homedir(), '.leadfinder', 'google-maps-profile');
}

/**
 * The installed Google Chrome, if any (MAPS_CHROME_PATH overrides). Used for
 * the sign-in window and, so the profile stays readable, for scraping too.
 */
export function findChrome(env = process.env) {
  if (env.MAPS_CHROME_PATH) return fs.existsSync(env.MAPS_CHROME_PATH) ? env.MAPS_CHROME_PATH : null;
  const candidates =
    process.platform === 'darwin'
      ? ['/Applications/Google Chrome.app/Contents/MacOS/Google Chrome']
      : process.platform === 'win32'
        ? [
            path.join(process.env['PROGRAMFILES'] || 'C:\\Program Files', 'Google/Chrome/Application/chrome.exe'),
            path.join(process.env['PROGRAMFILES(X86)'] || 'C:\\Program Files (x86)', 'Google/Chrome/Application/chrome.exe'),
          ]
        : ['/usr/bin/google-chrome', '/usr/bin/google-chrome-stable', '/opt/google/chrome/chrome'];
  return candidates.find((c) => fs.existsSync(c)) || null;
}

/**
 * Opens the profile in a NORMAL Chrome window, with nothing driving it, for a
 * person to sign in. Google refuses sign-in inside browsers controlled by
 * automation ("this browser may not be secure"); an ordinary window has no
 * such problem, and the session it saves is what the scraper later reuses.
 * `closed` resolves with the exit code when the window is closed.
 */
export function launchManualLogin({ executable, profileDir, url = 'https://accounts.google.com/', spawnFn = spawn }) {
  const child = spawnFn(
    executable,
    [`--user-data-dir=${profileDir}`, '--no-first-run', '--no-default-browser-check', url],
    { stdio: 'ignore' },
  );
  const closed = new Promise((resolve) => {
    child.once('exit', (code) => resolve(code ?? 0));
    child.once('error', () => resolve(-1));
  });
  return { child, closed };
}

/**
 * @param {Record<string,string|undefined>} [env]
 *   MAPS_PERSISTENT_SESSION  true/false to force the saved session on/off.
 *                            Unset (the default) = automatic: used whenever a
 *                            profile has been created by signing in.
 *   MAPS_PROFILE_DIR         browser profile folder (default ~/.leadfinder/google-maps-profile)
 *   MAPS_BROWSER_CHANNEL     browser to use; defaults to "chrome" when Google Chrome is installed
 *   MAPS_CHROME_PATH         path to Chrome if it is not in the usual place
 */
export function getSessionConfig(env = process.env) {
  const raw = (env.MAPS_PERSISTENT_SESSION || '').trim();
  const profileDir = env.MAPS_PROFILE_DIR ? path.resolve(env.MAPS_PROFILE_DIR) : defaultProfileDir();
  const mode = TRUE.test(raw) ? 'on' : /^(0|false|no|off)$/i.test(raw) ? 'off' : 'auto';
  return {
    mode,
    enabled: mode === 'on' || (mode === 'auto' && profileExists(profileDir)),
    profileDir,
    // The profile is signed in with the real Chrome, so the scraper must open
    // it with that same Chrome (cookies are tied to the browser that made them).
    channel: env.MAPS_BROWSER_CHANNEL || (findChrome(env) ? 'chrome' : undefined),
  };
}

/** A profile exists once a browser has been opened on it (the folder is non-empty). */
export function profileExists(dir) {
  try {
    return fs.readdirSync(dir).length > 0;
  } catch {
    return false;
  }
}

/** Creates the profile folder readable by this user only. */
export function ensureProfileDir(dir) {
  fs.mkdirSync(dir, { recursive: true, mode: 0o700 });
  return dir;
}

/**
 * Opens a persistent browser profile and presents it as the `Browser` the
 * scraper already works with: `newContext()` hands out the one shared context
 * (cookies live in the profile, so options cannot differ per context), whose
 * `close()` does nothing; closing the returned object closes the profile.
 */
export async function launchSessionBrowser({ chromium, profileDir, channel, args, contextOptions, headless = true }) {
  const context = await chromium.launchPersistentContext(profileDir, {
    headless,
    channel,
    args,
    ...contextOptions,
  });

  const shared = new Proxy(context, {
    get(target, prop) {
      if (prop === 'close') return async () => {};
      const value = Reflect.get(target, prop, target);
      return typeof value === 'function' ? value.bind(target) : value;
    },
  });

  return {
    isSession: true,
    context,
    newContext: async () => shared,
    close: async () => {
      await context.close().catch(() => {});
    },
  };
}

/**
 * Whether the page shows a signed-in Google account.
 * 'signed_in' | 'signed_out' | 'unknown' (neither marker found, e.g. Google
 * changed its markup or the page did not finish loading).
 */
export async function detectSignedIn(page) {
  try {
    const signedIn = await page
      .locator('a[aria-label^="Google Account"], a[href*="accounts.google.com/SignOutOptions"], button[aria-label^="Google Account"]')
      .count();
    if (signedIn) return 'signed_in';
    const signedOut = await page
      .locator('a[aria-label="Sign in"], a[href*="accounts.google.com/ServiceLogin"], a[href*="accounts.google.com/signin"]')
      .or(page.getByRole('link', { name: /^sign in$/i }))
      .or(page.getByRole('button', { name: /^sign in$/i }))
      .count();
    return signedOut ? 'signed_out' : 'unknown';
  } catch {
    return 'unknown';
  }
}

/**
 * Whether the browser is signed in, by asking Google's own account page: a
 * signed-in profile stays on myaccount.google.com, a signed-out one is sent to
 * the sign-in page. That decision is in the URL, so it does not depend on how
 * Maps happens to lay out its header (which shows nothing either way for an
 * anonymous desktop visitor). Falls back to the markup check if the redirect
 * cannot be read.
 */
export async function probeSignedIn(page) {
  try {
    await page.goto('https://myaccount.google.com/?hl=en', { waitUntil: 'domcontentloaded', timeout: 30000 });
    await page.waitForTimeout(1500);
    const url = page.url();
    // Signed out: sent to the sign-in page, or (anonymous visitors) to the
    // "about Google accounts" marketing page.
    if (/^https:\/\/accounts\.google\.com\//i.test(url) || /^https:\/\/www\.google\.[a-z.]+\/account\/about/i.test(url)) return 'signed_out';
    if (/^https:\/\/myaccount\.google\.com\//i.test(url)) return 'signed_in';
    return await detectSignedIn(page);
  } catch {
    return 'unknown';
  }
}

/**
 * Opens Maps headlessly on the saved profile and reports its state:
 *   no_profile | locked | signed_in | signed_out | unknown | error
 * Never throws.
 */
export async function checkSessionStatus({ chromium, profileDir, channel, args, contextOptions }) {
  if (!profileExists(profileDir)) return { status: 'no_profile', detail: `no browser profile at ${profileDir}` };
  let browser;
  try {
    browser = await launchSessionBrowser({ chromium, profileDir, channel, args, contextOptions, headless: true });
  } catch (err) {
    const msg = err?.message || String(err);
    // Chromium allows one process per profile.
    const locked = /ProcessSingleton|SingletonLock|already in use|user data directory is already/i.test(msg);
    return { status: locked ? 'locked' : 'error', detail: locked ? 'the profile is open in another browser/scan' : msg.split('\n')[0] };
  }
  try {
    const page = await browser.context.newPage();
    return { status: await probeSignedIn(page), detail: '' };
  } catch (err) {
    return { status: 'error', detail: (err?.message || String(err)).split('\n')[0] };
  } finally {
    await browser.close();
  }
}
