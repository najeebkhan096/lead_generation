import { test } from 'node:test';
import assert from 'node:assert/strict';
import { setUserDailyLeadLimit } from './userStore.js';

// Validation runs before any Firestore call, so these need no database.
test('the daily limit must be a whole number from 0 to 1000, or null for the default', async () => {
  for (const bad of [1.5, -1, '5', 1001, undefined]) {
    await assert.rejects(setUserDailyLeadLimit('u1', bad), (err) => err.status === 400, `accepted ${bad}`);
  }
});
