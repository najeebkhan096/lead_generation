import { test, beforeEach, after } from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import {
  getSessionConfig,
  stopOrphanedProfileChromes,
  defaultProfileDir,
  profileExists,
  ensureProfileDir,
  detectSignedIn,
  probeSignedIn,
  checkSessionStatus,
} from './mapsSession.js';
import { launchBrowser } from './googleMapsScraper.js';
import { resetSortDiagnostics, recordSort, describeSortDiagnostics, setSessionMode, SORT_STATUS } from './reviewSort.js';
import { accountHtml } from './mapsFixture.js';
import { useChromium } from './domTestHarness.js';
import { chromium } from 'playwright';

const domTest = useChromium();
const tmp = fs.mkdtempSync(path.join(os.tmpdir(), 'maps-session-test-'));
after(() => fs.rmSync(tmp, { recursive: true, force: true }));

const envBackup = { ...process.env };
beforeEach(() => {
  process.env = { ...envBackup };
  delete process.env.MAPS_PERSISTENT_SESSION;
  delete process.env.MAPS_PROFILE_DIR;
  delete process.env.MAPS_BROWSER_CHANNEL;
  resetSortDiagnostics();
  setSessionMode(false);
});

test('by default the session is automatic and the profile lives outside the repository', () => {
  const cfg = getSessionConfig({ MAPS_PROFILE_DIR: path.join(tmp, 'nothing-here-yet') });
  assert.equal(cfg.mode, 'auto');
  assert.equal(cfg.enabled, false, 'no profile yet, so nothing to use');
  const dflt = getSessionConfig({});
  assert.equal(dflt.profileDir, defaultProfileDir());
  assert.ok(dflt.profileDir.startsWith(os.homedir()), 'under the home folder');
  assert.ok(!dflt.profileDir.includes(`${path.sep}lead_generation${path.sep}`), 'not inside the project');
});

test('automatic mode switches on as soon as a profile exists', () => {
  const dir = path.join(tmp, 'auto-profile');
  ensureProfileDir(dir);
  assert.equal(getSessionConfig({ MAPS_PROFILE_DIR: dir }).enabled, false, 'empty folder');
  fs.writeFileSync(path.join(dir, 'Local State'), '{}');
  const cfg = getSessionConfig({ MAPS_PROFILE_DIR: dir });
  assert.equal(cfg.mode, 'auto');
  assert.equal(cfg.enabled, true);
});

test('MAPS_PERSISTENT_SESSION can force the session on or off', () => {
  const dir = path.join(tmp, 'forced-profile');
  ensureProfileDir(dir);
  fs.writeFileSync(path.join(dir, 'Local State'), '{}');
  for (const on of ['true', '1', 'yes', 'ON', 'True']) {
    const cfg = getSessionConfig({ MAPS_PERSISTENT_SESSION: on, MAPS_PROFILE_DIR: path.join(tmp, 'none') });
    assert.equal(cfg.mode, 'on', on);
    assert.equal(cfg.enabled, true, on);
  }
  for (const off of ['false', '0', 'no', 'OFF']) {
    const cfg = getSessionConfig({ MAPS_PERSISTENT_SESSION: off, MAPS_PROFILE_DIR: dir });
    assert.equal(cfg.mode, 'off', off);
    assert.equal(cfg.enabled, false, `${off} wins even though a profile exists`);
  }
});

test('MAPS_PROFILE_DIR and MAPS_BROWSER_CHANNEL override the defaults', () => {
  const cfg = getSessionConfig({ MAPS_PERSISTENT_SESSION: 'true', MAPS_PROFILE_DIR: '/tmp/x/profile', MAPS_BROWSER_CHANNEL: 'chrome' });
  assert.equal(cfg.profileDir, '/tmp/x/profile');
  assert.equal(cfg.channel, 'chrome');
});

test('a profile exists only once something is in the folder', () => {
  const dir = path.join(tmp, 'p1');
  assert.equal(profileExists(dir), false, 'missing folder');
  ensureProfileDir(dir);
  assert.equal(profileExists(dir), false, 'empty folder');
  fs.writeFileSync(path.join(dir, 'Local State'), '{}');
  assert.equal(profileExists(dir), true);
  if (process.platform !== 'win32') assert.equal(fs.statSync(dir).mode & 0o077, 0, 'private to this user');
});

test('saved session unavailable: status is no_profile, no browser is started', async () => {
  const res = await checkSessionStatus({ chromium, profileDir: path.join(tmp, 'never-created'), args: [], contextOptions: {} });
  assert.equal(res.status, 'no_profile');
});

domTest('signed-in, signed-out and unknown pages are told apart', async (page) => {
  await page.setContent(accountHtml('signed_in'));
  assert.equal(await detectSignedIn(page), 'signed_in');
  await page.setContent(accountHtml('signed_out'));
  assert.equal(await detectSignedIn(page), 'signed_out');
  await page.setContent(accountHtml('unknown'));
  assert.equal(await detectSignedIn(page), 'unknown');
});

domTest('the account probe: staying on myaccount is signed in; being sent away is signed out', async (page) => {
  const MYACCOUNT = /^https:\/\/myaccount\.google\.com\//;
  const ABOUT = /^https:\/\/www\.google\.com\/account\/about/;
  const SIGNIN = /^https:\/\/accounts\.google\.com\//;
  const html = (route, body) => route.fulfill({ status: 200, contentType: 'text/html', body: `<html><body>${body}</body></html>` });
  // (Playwright does not follow a mocked 302 for navigations, so redirect in the page.)
  const redirect = (to) => (route) => html(route, `<script>location.replace(${JSON.stringify(to)})</script>`);

  await page.route(MYACCOUNT, (route) => html(route, 'Google Account'));
  assert.equal(await probeSignedIn(page), 'signed_in');
  await page.unroute(MYACCOUNT);

  // Anonymous visitors are sent to the "about accounts" page...
  await page.route(MYACCOUNT, redirect('https://www.google.com/account/about/?hl=en'));
  await page.route(ABOUT, (route) => html(route, 'About'));
  assert.equal(await probeSignedIn(page), 'signed_out');
  await page.unroute(MYACCOUNT);

  // ...or to the sign-in page.
  await page.route(MYACCOUNT, redirect('https://accounts.google.com/v3/signin/identifier'));
  await page.route(SIGNIN, (route) => html(route, 'Sign in'));
  assert.equal(await probeSignedIn(page), 'signed_out');
});

domTest('the account probe never throws: a network failure is "unknown"', async (page) => {
  await page.route(/^https:\/\/myaccount\.google\.com\//, (route) => route.abort());
  assert.equal(await probeSignedIn(page), 'unknown');
});

domTest('unauthenticated fallback: session mode off launches the normal browser', async () => {
  process.env.MAPS_PERSISTENT_SESSION = 'false';
  const browser = await launchBrowser();
  try {
    assert.notEqual(browser.isSession, true, 'plain browser, no saved session');
    const context = await browser.newContext({});
    await context.close();
  } finally {
    await browser.close();
  }
});

domTest('unauthenticated fallback: session on but no saved profile still launches, without crashing', async () => {
  process.env.MAPS_PERSISTENT_SESSION = 'true';
  process.env.MAPS_PROFILE_DIR = path.join(tmp, 'missing-profile');
  const browser = await launchBrowser();
  try {
    assert.notEqual(browser.isSession, true, 'fell back to the anonymous browser');
    assert.equal(fs.existsSync(process.env.MAPS_PROFILE_DIR), false, 'nothing was created for a profile that was not set up');
  } finally {
    await browser.close();
  }
});

test('expired session: the diagnostics tell the user to sign in again', () => {
  setSessionMode(true); // a saved session is in use...
  recordSort(SORT_STATUS.SIGN_IN_REQUIRED); // ...yet Google still asked to sign in
  recordSort(SORT_STATUS.OK);
  const line = describeSortDiagnostics();
  assert.match(line, /1\/2 sorted/);
  assert.match(line, /saved Google session is not signed in or has expired/);
  assert.match(line, /npm run maps:login/);
});

test('no diagnostics are claimed when nothing was looked up', () => {
  assert.equal(describeSortDiagnostics(), null);
});

// ---- signing in with the real Chrome ------------------------------------------

import { findChrome, launchManualLogin } from './mapsSession.js';

test('Chrome is found through MAPS_CHROME_PATH, and an invalid path is not used', () => {
  const fake = path.join(tmp, 'chrome-fake');
  fs.writeFileSync(fake, '#!/bin/sh\nexit 0\n', { mode: 0o755 });
  assert.equal(findChrome({ MAPS_CHROME_PATH: fake }), fake);
  assert.equal(findChrome({ MAPS_CHROME_PATH: path.join(tmp, 'missing-chrome') }), null);
});

test('the scraper uses Chrome whenever it is installed, unless a browser is chosen explicitly', () => {
  const fake = path.join(tmp, 'chrome-fake2');
  fs.writeFileSync(fake, '#!/bin/sh\nexit 0\n', { mode: 0o755 });
  assert.equal(getSessionConfig({ MAPS_CHROME_PATH: fake }).channel, 'chrome');
  assert.equal(getSessionConfig({ MAPS_CHROME_PATH: fake, MAPS_BROWSER_CHANNEL: 'msedge' }).channel, 'msedge');
});

test('manual sign-in opens Chrome on the profile as an ordinary window and reports when it closes', async () => {
  const log = path.join(tmp, 'chrome-args.txt');
  const script = path.join(tmp, 'chrome-recorder');
  fs.writeFileSync(script, `#!/bin/sh\nprintf '%s\\n' "$@" > '${log}'\nexit 0\n`, { mode: 0o755 });
  const profile = path.join(tmp, 'login-profile');

  const { closed } = launchManualLogin({ executable: script, profileDir: profile });
  const code = await closed;
  assert.equal(code, 0);

  const args = fs.readFileSync(log, 'utf8').trim().split('\n');
  assert.ok(args.includes(`--user-data-dir=${profile}`), 'uses the dedicated profile');
  assert.ok(args.some((a) => a.startsWith('https://accounts.google.com')), 'opens Google sign-in');
  // Nothing that drives or disguises the browser: it is an ordinary Chrome window.
  for (const a of args) {
    assert.ok(!/remote-debugging|enable-automation|AutomationControlled|headless/i.test(a), a);
  }
});

test('a Chrome that cannot start is reported, not left hanging', async () => {
  const { closed } = launchManualLogin({ executable: path.join(tmp, 'no-such-chrome'), profileDir: path.join(tmp, 'p') });
  assert.equal(await closed, -1);
});

// ---- the saved login survives: real Chrome, started normally, driven over CDP -----------

import http from 'node:http';
import { launchSessionBrowser } from './mapsSession.js';

const CHROME = findChrome();

test('a login saved in the profile is still there after Chrome is closed and reopened', { skip: CHROME ? false : 'Google Chrome is not installed' }, async () => {
  // A local page that sets a persistent cookie, standing in for Google's sign-in cookies.
  const server = http.createServer((req, res) => {
    res.setHeader('Set-Cookie', 'leadfinder_login=ok; Max-Age=86400; Path=/');
    res.setHeader('Content-Type', 'text/html');
    res.end('<html><body>ok</body></html>');
  });
  await new Promise((r) => server.listen(0, '127.0.0.1', r));
  const url = `http://127.0.0.1:${server.address().port}/`;
  const profileDir = path.join(tmp, 'cdp-profile');
  ensureProfileDir(profileDir);
  const open = () => launchSessionBrowser({ chromium, chromePath: CHROME, profileDir, contextOptions: { viewport: { width: 1000, height: 700 } } });

  try {
    const first = await open();
    assert.equal(first.isSession, true);
    assert.equal(first.mode, 'chrome');
    const ctx = await first.newContext();
    const page = await ctx.newPage();
    assert.deepEqual(await page.evaluate(() => [innerWidth, innerHeight]).catch(() => null) && true, true);
    await page.goto(url);
    await page.close();
    await ctx.close(); // a no-op: callers close their "context" freely
    await first.close(); // closes Chrome, saving the cookies

    const second = await open(); // a later scan, same profile
    try {
      const cookies = await second.context.cookies();
      assert.ok(cookies.some((c) => c.name === 'leadfinder_login'), 'the saved login was read back');
    } finally {
      await second.close();
    }
  } finally {
    server.close();
  }
});

test('opening a profile that is already open fails clearly instead of hanging', { skip: CHROME ? false : 'Google Chrome is not installed' }, async () => {
  const profileDir = path.join(tmp, 'busy-profile');
  ensureProfileDir(profileDir);
  const first = await launchSessionBrowser({ chromium, chromePath: CHROME, profileDir });
  try {
    await assert.rejects(
      () => launchSessionBrowser({ chromium, chromePath: CHROME, profileDir }),
      /did not start|already open|Could not connect/i,
    );
  } finally {
    await first.close();
  }
});

// ---- noticing that a sign-in finished ------------------------------------------------

import { DatabaseSync } from 'node:sqlite';
import { hasGoogleSignInCookies } from './mapsSession.js';

function profileWithCookies(name, rows) {
  const dir = path.join(tmp, name);
  fs.mkdirSync(path.join(dir, 'Default'), { recursive: true });
  const db = new DatabaseSync(path.join(dir, 'Default', 'Cookies'));
  db.exec('CREATE TABLE cookies (host_key TEXT, name TEXT, encrypted_value BLOB)');
  const insert = db.prepare('INSERT INTO cookies VALUES (?, ?, ?)');
  for (const [host, cookie] of rows) insert.run(host, cookie, Buffer.from('v10secret'));
  db.close();
  return dir;
}

test('a finished sign-in is recognised by Google\'s sign-in cookie names', async () => {
  const signedIn = profileWithCookies('signed-in', [['.google.com', 'NID'], ['.google.com', 'SID'], ['.google.com', '__Secure-1PSID']]);
  assert.equal(await hasGoogleSignInCookies(signedIn), true);
});

test('anonymous Google cookies, other sites\' cookies, or no store at all are not a sign-in', async () => {
  assert.equal(await hasGoogleSignInCookies(profileWithCookies('anon', [['.google.com', 'NID'], ['.google.com', 'AEC']])), false);
  assert.equal(await hasGoogleSignInCookies(profileWithCookies('other-site', [['.example.com', 'SID']])), false, 'only Google hosts count');
  assert.equal(await hasGoogleSignInCookies(path.join(tmp, 'no-store-here')), false);
});

test('stops the Chrome left on the profile by an earlier run, asking it to quit first', async () => {
  const sent = [];
  let alive = [4242, 4243];
  const stopped = await stopOrphanedProfileChromes('/some/profile', {
    listPids: async () => alive,
    signal: (pid, sig) => {
      sent.push([pid, sig]);
      if (sig === 'SIGTERM') alive = [];
    },
    waitMs: 1000,
  });
  assert.equal(stopped, 2);
  assert.deepEqual(sent, [[4242, 'SIGTERM'], [4243, 'SIGTERM']]);
});

test('forces a Chrome that will not quit, and does nothing when none is running', async () => {
  const sent = [];
  const alive = [7];
  const stopped = await stopOrphanedProfileChromes('/some/profile', {
    listPids: async () => alive,
    signal: (pid, sig) => sent.push([pid, sig]),
    waitMs: 300,
  });
  assert.equal(stopped, 1);
  assert.deepEqual(sent, [[7, 'SIGTERM'], [7, 'SIGKILL']]);

  const none = await stopOrphanedProfileChromes('/some/profile', { listPids: async () => [], signal: () => assert.fail('no signal') });
  assert.equal(none, 0);
});
