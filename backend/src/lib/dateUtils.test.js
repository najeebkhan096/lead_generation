import { test } from 'node:test';
import assert from 'node:assert/strict';
import { daysForRange, parseRelativeDate, isWithinRange } from './dateUtils.js';

const NOW = new Date('2026-10-17T12:00:00.000Z');
const within28 = (text) => isWithinRange(text, '28', NOW);

test('a "28" range means 28 days', () => {
  assert.equal(daysForRange('28'), 28);
  assert.equal(daysForRange(28), 28);
});

test('28-day window: recent reviews are inside', () => {
  for (const text of ['just now', '3 hours ago', 'an hour ago', 'yesterday', 'a day ago', '2 days ago', '27 days ago', 'a week ago', '3 weeks ago', 'Edited 2 weeks ago']) {
    assert.equal(within28(text), true, text);
  }
});

test('28-day window: older reviews are outside', () => {
  for (const text of ['29 days ago', '30 days ago', '5 weeks ago', 'a month ago', '2 months ago', '6 months ago', 'a year ago', '2 years ago']) {
    assert.equal(within28(text), false, text);
  }
});

test('the boundary is deterministic: exactly 28 days old is inside, every time', () => {
  // "4 weeks ago" is 28 days. Reading the clock separately for the review and
  // for the cutoff made this fall in or out depending on the millisecond.
  for (let i = 0; i < 50; i++) {
    assert.equal(within28('28 days ago'), true);
    assert.equal(within28('4 weeks ago'), true);
  }
  assert.equal(within28('29 days ago'), false);
});

test('the window follows the range given, not a fixed one', () => {
  assert.equal(isWithinRange('2 months ago', '28', NOW), false);
  assert.equal(isWithinRange('2 months ago', '90', NOW), true);
  assert.equal(isWithinRange('20 days ago', '7', NOW), false);
});

test('an unreadable date is kept (existing behaviour: favour recall)', () => {
  assert.equal(within28('Unknown'), true);
  assert.equal(within28(''), true);
  assert.equal(parseRelativeDate('Unknown', NOW), null);
});

test('parsing is relative to the clock reading it is given', () => {
  assert.equal(parseRelativeDate('2 days ago', NOW).getTime(), NOW.getTime() - 2 * 86400000);
  assert.equal(parseRelativeDate('3 weeks ago', NOW).getTime(), NOW.getTime() - 21 * 86400000);
  assert.equal(parseRelativeDate('a month ago', NOW).getTime(), NOW.getTime() - 30 * 86400000);
});

test('callers that pass no clock still work', () => {
  assert.equal(isWithinRange('2 days ago', '28'), true);
  assert.equal(isWithinRange('2 months ago', '28'), false);
});
