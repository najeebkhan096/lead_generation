import { test, beforeEach, after } from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import {
  getSessionConfig,
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
