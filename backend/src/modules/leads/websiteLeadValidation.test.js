import { test } from 'node:test';
import assert from 'node:assert/strict';
import {
  summarizeValidationRows, stateOfLocation, locationInStates, emailCheckIsDefinite, inNoWebsiteScope, buildWebsiteLeadPatch,
} from './websiteLeadStore.js';
import { toSiteRecord } from '../website/siteLeadPipeline.js';
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

test('only a dedicated no-website scan puts a lead in the no-website list: the 1-star scan\'s by-product does not', () => {
  const runs = new Set(['Cafe USA']);
  // Tagged leads say where they came from, whatever the category.
  assert.equal(inNoWebsiteScope({ scanModes: ['no_website'], category: 'Plumber USA' }, runs), true);
  assert.equal(inNoWebsiteScope({ scanModes: ['reviews'], category: 'Cafe USA' }, runs), false);
  assert.equal(inNoWebsiteScope({ scanModes: ['reviews', 'no_website'], category: 'Cafe USA' }, runs), true);
  // Filed before the tag existed: only a search a no-website scan has run for.
  assert.equal(inNoWebsiteScope({ category: 'Cafe USA' }, runs), true);
  assert.equal(inNoWebsiteScope({ category: 'Dentist USA' }, runs), false);
  assert.equal(inNoWebsiteScope({}, runs), false);
});

test('a lead records which kinds of scan found it, and a later scan adds to that', () => {
  const site = (scanMode) => ({ business: 'Joe', category: 'Cafe USA', scanMode });
  const first = buildWebsiteLeadPatch(undefined, site('reviews'));
  assert.deepEqual(first.scanModes, ['reviews']);
  const second = buildWebsiteLeadPatch({ scanModes: first.scanModes }, site('no_website'));
  assert.deepEqual(second.scanModes, ['reviews', 'no_website']);
  assert.deepEqual(buildWebsiteLeadPatch(undefined, { business: 'X' }).scanModes, ['reviews']);
});

test('the site record carries the scan kind it was found by', () => {
  const business = { name: 'Joe', category: 'Cafe', phone: '5125550100', websiteStatus: 'missing' };
  assert.equal(toSiteRecord(business, {}).scanMode, 'reviews');
  assert.equal(toSiteRecord(business, { scanMode: 'no_website' }).scanMode, 'no_website');
});
