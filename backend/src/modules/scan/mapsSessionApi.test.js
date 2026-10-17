import { test, beforeEach, after } from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { getStatus } from './mapsSessionController.js';
import { _resetSessionManager } from '../../scraper/mapsSessionManager.js';

const tmp = fs.mkdtempSync(path.join(os.tmpdir(), 'maps-api-test-'));
after(() => fs.rmSync(tmp, { recursive: true, force: true }));
const backup = { ...process.env };

beforeEach(() => {
  process.env = { ...backup };
  process.env.MAPS_PROFILE_DIR = path.join(tmp, 'no-profile-here');
  delete process.env.MAPS_PERSISTENT_SESSION;
  _resetSessionManager();
});

function call(handler, req = {}) {
  return new Promise((resolve) => {
    const res = {
      statusCode: 200,
      status(code) { this.statusCode = code; return this; },
      json(body) { resolve({ status: this.statusCode, body }); },
    };
    handler({ query: {}, ...req }, res);
  });
}

test('status with no saved profile: not ready, and says to sign in (no browser is started)', async () => {
  const { status, body } = await call(getStatus);
  assert.equal(status, 200);
  assert.equal(body.status, 'no_profile');
  assert.equal(body.ready, false);
  assert.equal(body.loginInProgress, false);
  assert.equal(body.mode, 'auto');
});

test('status never returns the profile cookies or any session data, only its folder', async () => {
  const { body } = await call(getStatus);
  assert.deepEqual(Object.keys(body).sort(), ['detail', 'enabled', 'inUseByScan', 'loginInProgress', 'mode', 'profileDir', 'ready', 'status']);
});

// ---- coverage tiers endpoint --------------------------------------------------------------

import { getCoverage } from './stateCityScanController.js';

test('the coverage endpoint lists the three tiers with their size and time', async () => {
  const { body } = await call(getCoverage);
  assert.deepEqual(body.tiers.map((t) => t.tier), ['standard', 'extended', 'maximum']);
  assert.equal(body.tiers[0].searches, 501);
  assert.ok(body.tiers[1].searches > body.tiers[0].searches && body.tiers[2].searches > body.tiers[1].searches);
  for (const t of body.tiers) assert.ok(t.hours > 0 && t.businesses > 0 && t.label);
});
