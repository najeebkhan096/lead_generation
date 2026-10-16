import { test, beforeEach } from 'node:test';
import assert from 'node:assert/strict';
import { startStateCityScan, getStateCityJobSnapshot } from './stateCityOrchestrator.js';
import { useChromium } from '../../scraper/domTestHarness.js';

const domTest = useChromium();
const backup = { ...process.env };

beforeEach(() => {
  process.env = { ...backup, MAPS_PERSISTENT_SESSION: 'false' }; // anonymous: no saved session
});

domTest('a scan will not start without a signed-in Google session', async () => {
  await assert.rejects(
    () => startStateCityScan({ categories: ['Car Wash'] }),
    (err) => {
      assert.equal(err.status, 409);
      assert.equal(err.code, 'GOOGLE_SIGN_IN_REQUIRED');
      assert.match(err.message, /Sign in to Google/);
      return true;
    },
  );
});

domTest('a refused start leaves no scan behind (a second start is not told "already running")', async () => {
  for (let i = 0; i < 2; i++) {
    await assert.rejects(
      () => startStateCityScan({ categories: ['Car Wash'] }),
      (err) => err.code === 'GOOGLE_SIGN_IN_REQUIRED',
    );
  }
  assert.equal(getStateCityJobSnapshot(), null);
});
