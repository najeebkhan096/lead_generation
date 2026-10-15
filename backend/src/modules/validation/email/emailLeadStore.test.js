import { test } from 'node:test';
import assert from 'node:assert/strict';
import { emailLeadSourceType } from './emailLeadStore.js';

test('an email lead keeps the signal the validation started from', () => {
  assert.equal(emailLeadSourceType({ sourceType: 'review' }), 'review');
  assert.equal(emailLeadSourceType({ sourceType: 'website', badReview: { text: 'bad' } }), 'website');
});

test('without one, a review text means a review lead and none means no website', () => {
  assert.equal(emailLeadSourceType({ badReview: { text: 'Never showed up' } }), 'review');
  assert.equal(emailLeadSourceType({ badReview: { text: '' } }), 'website');
  assert.equal(emailLeadSourceType({}), 'website');
});

test('an unexpected value is not stored as a signal', () => {
  assert.equal(emailLeadSourceType({ sourceType: 'something' }), 'website');
});
