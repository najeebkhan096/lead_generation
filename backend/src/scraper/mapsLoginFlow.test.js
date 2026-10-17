import { test, after } from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { DatabaseSync } from 'node:sqlite';
import { startLogin, getSessionSnapshot, _resetSessionManager } from './mapsSessionManager.js';

const tmp = fs.mkdtempSync(path.join(os.tmpdir(), 'login-flow-test-'));
after(() => fs.rmSync(tmp, { recursive: true, force: true }));
const backup = { ...process.env };
after(() => { process.env = backup; });

/**
 * A stand-in for Chrome. Started for sign-in it stays running like a macOS
 * Chrome whose window was closed; started with a debugging port (the status
 * check) it exits at once, so no real browser is needed.
 */
function fakeChrome(file) {
  fs.writeFileSync(
    file,
    `#!/bin/sh
case "$*" in *remote-debugging-port*) exit 1;; esac
echo $$ > '${file}.pid'
exec sleep 120
`,
    { mode: 0o755 },
  );
}

const alive = (pid) => { try { process.kill(pid, 0); return true; } catch { return false; } };

test('the sign-in is noticed from the profile and its window is closed by the app', async (t) => {
  const chrome = path.join(tmp, 'chrome');
  fakeChrome(chrome);
  const profile = path.join(tmp, 'profile');
  process.env.MAPS_CHROME_PATH = chrome;
  process.env.MAPS_PROFILE_DIR = profile;
  delete process.env.MAPS_PERSISTENT_SESSION;
  _resetSessionManager();

  const started = await startLogin();
  assert.equal(started.started, true);
  assert.equal((await getSessionSnapshot()).loginInProgress, true, 'waiting for the person to sign in');

  const pid = Number(fs.readFileSync(`${chrome}.pid`, 'utf8').trim());
  assert.ok(alive(pid), 'the (fake) Chrome window is open');

  // Nothing yet: still waiting.
  await new Promise((r) => setTimeout(r, 3500));
  assert.equal((await getSessionSnapshot()).loginInProgress, true);

  // The person signs in: Google's sign-in cookies appear in the profile.
  fs.mkdirSync(path.join(profile, 'Default'), { recursive: true });
  const db = new DatabaseSync(path.join(profile, 'Default', 'Cookies'));
  db.exec('CREATE TABLE cookies (host_key TEXT, name TEXT, encrypted_value BLOB)');
  db.prepare('INSERT INTO cookies VALUES (?, ?, ?)').run('.google.com', 'SID', Buffer.from('secret'));
  db.close();

  // Within a few seconds the app notices, closes the window, and stops waiting.
  const deadline = Date.now() + 20000;
  while (Date.now() < deadline && (await getSessionSnapshot()).loginInProgress) await new Promise((r) => setTimeout(r, 500));
  assert.equal((await getSessionSnapshot()).loginInProgress, false, 'no longer waiting on the person');
  assert.equal(alive(pid), false, 'the window was closed by the app');
  t.diagnostic('sign-in detected and window closed');
});
