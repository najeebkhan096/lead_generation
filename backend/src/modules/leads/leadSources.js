/**
 * The saved-lead collections a validator can run over.
 *
 * Both validators (WhatsApp, email) work on either lead signal — a review
 * lead (`leads`) or a no-website lead (`websiteLeads`). This is the one
 * place that knows how each collection loads leads by id and how a
 * validation result is written back onto the lead itself, so the
 * validator controllers don't branch on collection names.
 */

import {
  getSavedLeadsByIds,
  setLeadEmail,
  updateLeadWhatsAppStatus,
} from './firebaseLeadStore.js';
import {
  getWebsiteLeadsByIds,
  setWebsiteLeadEmail,
  updateWebsiteLeadWhatsAppStatus,
} from './websiteLeadStore.js';

export const LEAD_SOURCES = {
  leads: {
    sourceType: 'review',
    load: getSavedLeadsByIds,
    setEmail: setLeadEmail,
    setWhatsApp: updateLeadWhatsAppStatus,
  },
  websiteLeads: {
    sourceType: 'website',
    load: getWebsiteLeadsByIds,
    setEmail: setWebsiteLeadEmail,
    setWhatsApp: updateWebsiteLeadWhatsAppStatus,
  },
};

/** Resolves a `collection` request field, or throws a 400. */
export function leadSource(name) {
  const source = LEAD_SOURCES[name];
  if (!source) {
    const err = new Error(`collection must be one of: ${Object.keys(LEAD_SOURCES).join(', ')}`);
    err.status = 400;
    throw err;
  }
  return source;
}
