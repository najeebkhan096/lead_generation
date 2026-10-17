/**
 * The saved-lead collections a validator can run over: review leads (`leads`,
 * businesses with a recent 1-star review). This is the one place that knows
 * how that collection loads leads by id and how a validation result is written
 * back onto the lead, so the validator controllers don't branch on names.
 */

import { getSavedLeadsByIds, updateLeadWhatsAppStatus } from './firebaseLeadStore.js';

export const LEAD_SOURCES = {
  leads: {
    sourceType: 'review',
    load: getSavedLeadsByIds,
    setWhatsApp: updateLeadWhatsAppStatus,
  },
};

/** Resolves a `collection` request field, or throws a 400. */
export function leadSource(name) {
  const source = LEAD_SOURCES[name];
  if (!source) {
    const err = new Error('collection must be: leads');
    err.status = 400;
    throw err;
  }
  return source;
}
