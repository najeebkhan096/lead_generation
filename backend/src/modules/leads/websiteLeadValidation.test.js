import { test } from 'node:test';
import assert from 'node:assert/strict';
import { summarizeValidationRows, stateOfLocation, locationInStates, emailCheckIsDefinite } from './websiteLeadStore.js';
import { leadSource } from './leadSources.js';

const docs = [
  { location: 'Austin, TX', phone: '+1 1', whatsAppCheckedAt: new Date(), hasWhatsApp: true },
  { location: 'Dallas, TX', phone: '+1 2' },
  { location: 'Texas', phone: null },
  { location: 'Miami, FL', phone: '+1 3', whatsAppCheckedAt: new Date(), hasWhatsApp: false, email: 'a@b.com', emailCheckedAt: new Date(), emailStatus: 'found' },
  { location: '', phone: '+1 4', emailCheckedAt: new Date(), emailStatus: 'check_failed' },
];

test('stateOfLocation / locationInStates group by the state part', () => {
  assert.equal(stateOfLocation('Austin, TX'), 'TX');
  assert.equal(stateOfLocation('Texas'), 'Texas');
  assert.equal(locationInStates('Austin, TX', new Set(['tx'])), true);
  assert.equal(locationInStates('Austin, TX', new Set(['fl'])), false);
  assert.equal(locationInStates('anything', null), true);
});

test('WhatsApp summary: per state, only numbers count', () => {
  const { total, locations } = summarizeValidationRows(docs, 'whatsapp');
  const by = Object.fromEntries(locations.map((l) => [l.name, l]));
  assert.deepEqual([by.TX.eligible, by.TX.checked, by.TX.found, by.TX.count, by.TX.status], [2, 1, 1, 1, 'partial']);
  assert.equal(by.FL.status, 'validated');
  assert.equal(by.Texas.status, 'no_phone'); // no phone number to check
  assert.equal(by.Unknown.status, 'not_validated');
  assert.equal(total, 2);
});

test('email summary: a found address or a definite miss is checked; a failure is retried', () => {
  const { locations } = summarizeValidationRows(docs, 'email');
  const by = Object.fromEntries(locations.map((l) => [l.name, l]));
  assert.deepEqual([by.FL.checked, by.FL.found, by.FL.status], [1, 1, 'validated']);
  assert.equal(by.Unknown.checked, 0);
  assert.equal(by.Unknown.status, 'not_validated');
  assert.equal(emailCheckIsDefinite({ emailCheckedAt: new Date(), emailStatus: 'not_found' }), true);
  assert.equal(emailCheckIsDefinite({ emailCheckedAt: new Date(), emailStatus: 'check_failed' }), false);
});

test('websiteLeads is a validator source that does not copy verified leads into whatsappLeads', () => {
  const source = leadSource('websiteLeads');
  assert.equal(source.sourceType, 'website');
  assert.equal(typeof source.saveVerified, 'function'); // an explicit no-op, not the job's default copy
  assert.equal(leadSource().sourceType, 'review');
  assert.equal(leadSource('leads').saveVerified, undefined);
  assert.throws(() => leadSource('nope'), (e) => e.status === 400);
});
