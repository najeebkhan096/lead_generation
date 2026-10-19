import { test } from 'node:test';
import assert from 'node:assert/strict';
import { whatsAppStateStatus } from './firebaseLeadStore.js';

test('a state is validated only when every number in it has been checked', () => {
  assert.equal(whatsAppStateStatus({ withPhone: 5, checked: 5 }), 'validated');
  assert.equal(whatsAppStateStatus({ withPhone: 5, checked: 4 }), 'partial');
  assert.equal(whatsAppStateStatus({ withPhone: 5, checked: 0 }), 'not_validated');
});

test('a state with no phone numbers has nothing to validate', () => {
  assert.equal(whatsAppStateStatus({ withPhone: 0, checked: 0 }), 'no_phone');
});
