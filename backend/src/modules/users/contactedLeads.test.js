import { test } from 'node:test';
import assert from 'node:assert/strict';
import { Timestamp } from 'firebase-admin/firestore';
import { refundsToday, toContactedLead } from './contactedLeads.js';

test('a contacted lead is shaped for the admin page', () => {
  const lead = toContactedLead('abc', {
    business: 'Acme Motors',
    category: 'automotive',
    location: 'Texas',
    phone: '+14155550100',
    rating: 3.2,
    status: 'contacted',
    contactedAt: Timestamp.fromDate(new Date('2026-10-19T08:00:00Z')),
    badReview: { text: 'Never showed up' },
  });
  assert.equal(lead.id, 'abc');
  assert.equal(lead.business, 'Acme Motors');
  assert.equal(lead.contactedAt, '2026-10-19T08:00:00.000Z');
  assert.equal(lead.reviewText, 'Never showed up');
  assert.equal(lead.rating, 3.2);
  assert.equal(lead.totalReviews, null);
});

test('a lead with missing fields still shows, with blanks where the data is missing', () => {
  const lead = toContactedLead('x', {});
  assert.equal(lead.business, 'Unnamed');
  assert.equal(lead.contactedAt, null);
  assert.equal(lead.reviewText, '');
});

test('moving a lead back frees a slot only when it was contacted today (Dubai day)', () => {
  const now = new Date('2026-10-19T10:00:00Z'); // 14:00 in Dubai on the 19th
  const today = Timestamp.fromDate(new Date('2026-10-19T06:00:00Z')); // 10:00 Dubai, same day
  const yesterday = Timestamp.fromDate(new Date('2026-10-18T10:00:00Z'));
  assert.equal(refundsToday({ contactedAt: today }, '2026-10-19'), true);
  assert.equal(refundsToday({ contactedAt: yesterday }, '2026-10-19'), false);
  assert.equal(refundsToday({}, '2026-10-19'), false);
  assert.ok(now);
});
