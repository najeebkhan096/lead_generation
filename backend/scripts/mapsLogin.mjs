/**
 * Opens a VISIBLE browser on the dedicated Google Maps profile so YOU can sign
 * in to a Google account by hand. Nothing here types a password, drives Google's
 * login, handles CAPTCHAs/2-step prompts, or reads cookies: you do all of that
 * in the window. Close the window when you are done; the profile (kept outside
 * the repository) is then used automatically by every scan.
 *
 *   npm run maps:login
 *
 * (The web console's Excel Scan page has the same "Sign in to Google" button.)
 *
 * Use a DEDICATED Google account, not your personal one. When Google Chrome is
 * installed it opens as an ordinary window with nothing driving it, because
 * Google refuses sign-in inside automation-controlled browsers ("this browser
 * may not be secure"). Stop any running scan first: a profile can only be open
 * in one browser.
 */
import { chromium } from 'playwright';
import 'dotenv/config';
import {
  getSessionConfig,
  ensureProfileDir,
  findChrome,
  launchManualLogin,
  launchSessionBrowser,
  checkSessionStatus,
} from '../src/scraper/mapsSession.js';
import { BROWSER_ARGS, CONTEXT_OPTIONS } from '../src/scraper/googleMapsScraper.js';

const cfg = getSessionConfig();
ensureProfileDir(cfg.profileDir);

console.log(`Browser profile: ${cfg.profileDir}`);
console.log('A browser window will open. Sign in to your DEDICATED Google account there,');
console.log('open https://www.google.com/maps once to confirm, then CLOSE THE WINDOW.\n');

const chrome = findChrome();
if (chrome) {
  const { closed } = launchManualLogin({ executable: chrome, profileDir: cfg.profileDir });
  await closed;
} else {
  let browser;
  try {
    // No Chrome installed: Playwright's browser, plain window, no stealth flags.
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
    console.error(`Could not open the profile: ${msg}`);
    console.error('If it is "already in use", close the other browser or stop the running scan, then retry.');
    process.exit(1);
  }
  const page = await browser.context.newPage();
  await page.goto('https://accounts.google.com/', { waitUntil: 'domcontentloaded' }).catch(() => {});
  await new Promise((resolve) => browser.context.on('close', resolve));
}

console.log('\nWindow closed. Checking the saved session...');
const result = await checkSessionStatus({
  chromium,
  profileDir: cfg.profileDir,
  channel: cfg.channel,
  args: BROWSER_ARGS,
  contextOptions: CONTEXT_OPTIONS,
});
console.log(`Session: ${result.status}${result.detail ? ` (${result.detail})` : ''}`);
console.log(result.status === 'signed_in'
  ? 'Signed in. Scans use this session automatically (no setting needed); restart the backend if it is running.'
  : 'Not confirmed as signed in. Run `npm run maps:login` again, or `npm run maps:session-check`.');
