/**
 * The saved-lead collections a validator can run over: review leads (`leads`,
 * businesses with a recent 1-star review) and no-website leads (`websiteLeads`).
 * This is the one place that knows how each collection loads leads by id or by
 * state, how its per-state progress is summarised, and how a validation result
 * is written back onto the lead — so the validator controllers don't branch on
 * names.
 *
 * `saveVerified` is where a WhatsApp-verified lead is copied after a check. It
 * is left undefined for review leads (the job's default copies them into
 * `whatsappLeads`, the verified 1-star list). A no-website lead stays in
 * `websiteLeads` — copying it would list it as a 1-star lead.
 */

import {
  getSavedLeadsByIds,
  updateLeadWhatsAppStatus,
  listUnvalidatedLeads,
  summarizeWhatsAppByState,
} from './firebaseLeadStore.js';
import {
  getWebsiteLeadsByIds,
  updateWebsiteLeadWhatsApp,
  listUncheckedWhatsApp,
  summarizeWebsiteLeadValidation,
} from './websiteLeadStore.js';

export const LEAD_SOURCES = {
  leads: {
    sourceType: 'review',
    load: getSavedLeadsByIds,
    setWhatsApp: updateLeadWhatsAppStatus,
    listUncheckedWhatsApp: ({ states } = {}) => listUnvalidatedLeads({ states }),
    summarizeWhatsApp: summarizeWhatsAppByState,
    saveVerified: undefined,
  },
  websiteLeads: {
    sourceType: 'website',
    load: getWebsiteLeadsByIds,
    setWhatsApp: updateWebsiteLeadWhatsApp,
    listUncheckedWhatsApp,
    summarizeWhatsApp: () => summarizeWebsiteLeadValidation('whatsapp'),
    saveVerified: async () => {},
  },
};

/** Resolves a `collection` request field (default `leads`), or throws a 400. */
export function leadSource(name = 'leads') {
  const source = LEAD_SOURCES[name];
  if (!source) {
    const err = new Error('collection must be one of: leads, websiteLeads');
    err.status = 400;
    throw err;
  }
  return source;
}
