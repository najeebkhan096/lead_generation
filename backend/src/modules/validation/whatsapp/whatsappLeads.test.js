import { test, beforeEach } from 'node:test';
import assert from 'node:assert/strict';
import {
  startValidationJob,
  getJobSnapshot,
  _resetValidationJobForTests,
} from './whatsappValidationJob.js';
import { leadDocId, withCountrySuffix, normalizeCategory, hasCountryTag } from '../../../lib/leadIdentity.js';
import { LEAD_SOURCES, leadSource } from '../../leads/leadSources.js';

beforeEach(() => _resetValidationJobForTests());

async function untilDone() {
  while (getJobSnapshot()?.status === 'running') await new Promise((r) => setTimeout(r, 5));
  return getJobSnapshot();
}

const lead = (id, phone, extra = {}) => ({
  id,
  dbId: id,
  business: `Biz ${id}`,
  phone,
  category: 'Cafe',
  mapsUrl: `https://maps.example/${id}`,
  ...extra,
});

test('verified numbers are copied to whatsappLeads; others are not', async () => {
  const copied = [];
  const flagged = [];
  startValidationJob({
    leads: [lead('a', '+15125550001'), lead('b', '+15125550002')],
    checkNumberFn: async (phone) => ({ checked: true, valid: phone.endsWith('1') }),
    updateLeadFn: async (id, status) => flagged.push([id, status.hasWhatsApp]),
    saveWhatsAppLeadsFn: async (leads) => copied.push(...leads),
  });
  const snap = await untilDone();

  assert.equal(snap.validCount, 1);
  assert.equal(snap.invalidCount, 1);
  assert.deepEqual(flagged, [['a', true], ['b', false]]);
  assert.deepEqual(copied.map((l) => l.id), ['a']);
  assert.equal(copied[0].category, 'Cafe');
  assert.equal(copied[0].mapsUrl, 'https://maps.example/a');
});

test('a failed copy is reported on the result and does not stop the run', async () => {
  startValidationJob({
    leads: [lead('a', '+15125550001'), lead('b', '+15125550003')],
    checkNumberFn: async () => ({ checked: true, valid: true }),
    updateLeadFn: async () => {},
    saveWhatsAppLeadsFn: async ([l]) => {
      if (l.id === 'a') throw new Error('firestore down');
    },
  });
  const snap = await untilDone();
  assert.equal(snap.checked, 2);
  assert.equal(snap.validCount, 2);
  assert.match(snap.results.a.error, /failed to save to WhatsApp leads/);
  assert.equal(snap.results.b.error, null);
});

test('leadDocId is stable across the signals a business can be identified by', () => {
  const byMaps = leadDocId({ mapsUrl: 'https://maps.example/x?hl=en', phone: '+1 555' });
  assert.equal(byMaps, leadDocId({ mapsUrl: 'HTTPS://maps.example/x?other=1' }));
  assert.equal(leadDocId({ phone: '+1 (512) 555-0001' }), leadDocId({ phone: '15125550001' }));
  assert.notEqual(leadDocId({ phone: '+15125550001' }), leadDocId({ phone: '+15125550002' }));
  assert.equal(leadDocId({ business: 'A', address: 'B', location: 'C' }).length, 40);
});

test('withCountrySuffix tags once and leaves untagged data alone', () => {
  assert.equal(withCountrySuffix('cleaning services', 'USA'), 'cleaning services USA');
  assert.equal(withCountrySuffix('cleaning services USA', 'USA'), 'cleaning services USA');
  assert.equal(withCountrySuffix('cleaning services UK', null), 'cleaning services UK');
  assert.equal(withCountrySuffix('  ', 'USA'), null);
});

test('lead sources map both signals and reject unknown collections', () => {
  assert.deepEqual(Object.keys(LEAD_SOURCES).sort(), ['leads', 'websiteLeads']);
  assert.equal(leadSource('leads').sourceType, 'review');
  assert.equal(leadSource('websiteLeads').sourceType, 'website');
  assert.throws(() => leadSource('users'), (e) => e.status === 400);
});

test('categories are normalized to the country-tagged form every collection uses', () => {
  // an Excel archive's sheet name carries no tag
  assert.equal(normalizeCategory('Car Dealer'), 'Car Dealer USA');
  assert.equal(normalizeCategory('  Auto Body Shop '), 'Auto Body Shop USA');
  // already tagged (any known country) -> untouched
  assert.equal(normalizeCategory('Car Dealer USA'), 'Car Dealer USA');
  assert.equal(normalizeCategory('Air Conditioning Contractor UK'), 'Air Conditioning Contractor UK');
  assert.equal(normalizeCategory('Cleaning Service', 'UK'), 'Cleaning Service UK');
  assert.equal(normalizeCategory(''), null);
  assert.equal(hasCountryTag('Cafe USA'), true);
  assert.equal(hasCountryTag('Cafe'), false);
  assert.equal(hasCountryTag('Spectacular'), false, 'a suffix must be a whole word');
});
