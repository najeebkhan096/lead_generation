import { test } from 'node:test';
import assert from 'node:assert/strict';
import { isWhatsAppCheckFresh, WHATSAPP_RECHECK_DAYS } from './leadChecks.js';
import {
  startValidationJob,
  getJobSnapshot,
  _resetValidationJobForTests,
} from './whatsapp/whatsappValidationJob.js';

const DAY = 24 * 60 * 60 * 1000;
const ago = (days) => ({ toMillis: () => Date.now() - days * DAY });

// ---- freshness rules -------------------------------------------------------

test('a WhatsApp answer is reused for a while, either way', () => {
  assert.equal(isWhatsAppCheckFresh({ valid: true, at: ago(5) }), true);
  assert.equal(isWhatsAppCheckFresh({ valid: false, at: ago(5) }), true);
  assert.equal(isWhatsAppCheckFresh({ valid: false, at: ago(WHATSAPP_RECHECK_DAYS + 1) }), false);
  assert.equal(isWhatsAppCheckFresh({ at: ago(1) }), false, 'no answer recorded');
});

// ---- the jobs remember every outcome ---------------------------------------

async function untilDone(snapshot) {
  while (snapshot()?.status === 'running') await new Promise((r) => setTimeout(r, 5));
  return snapshot();
}

test('whatsapp job records both answers, and a run of only reused answers needs no session', async () => {
  _resetValidationJobForTests();
  const recorded = [];
  startValidationJob({
    leads: [
      { id: 'on', business: 'On', phone: '+15125550001' },
      { id: 'off', business: 'Off', phone: '+15125550002' },
    ],
    checkNumberFn: async (phone) => ({ checked: true, valid: phone.endsWith('1') }),
    updateLeadFn: async () => {},
    saveWhatsAppLeadsFn: async () => {},
    recordCheckFn: async (lead, check) => recorded.push([lead.id, check.valid]),
  });
  await untilDone(getJobSnapshot);
  assert.deepEqual(recorded, [['on', true], ['off', false]]);

  _resetValidationJobForTests();
  // default checker + nothing to check: must not demand a WhatsApp session
  const out = startValidationJob({ leads: [], reused: { known: { valid: true } } });
  assert.equal(out.reused, 1);
  const snap = await untilDone(getJobSnapshot);
  assert.equal(snap.status, 'done');
  assert.equal(snap.results.known.valid, true);
  assert.equal(snap.results.known.reused, true);
});
