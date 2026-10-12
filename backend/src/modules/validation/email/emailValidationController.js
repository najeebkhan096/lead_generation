import {
  startEmailValidationJob,
  getEmailJobSnapshot,
  cancelEmailValidationJob,
} from './emailValidationJob.js';
import { discoverEmailsByWebSearch } from './webSearchEmailDiscovery.js';
import { discoverEmailsFromWebsite } from './emailDiscoveryService.js';
import { leadSource } from '../../leads/leadSources.js';
import { saveEmailLeadsToFirebase } from './emailLeadStore.js';

// Web search is paced and slow per business, so run few lookups at once.
const WEB_SEARCH_CONCURRENCY = 3;

/**
 * POST /api/email-validation/validate-list
 *
 * Body: `{ leads: [{ id, website, business, phone?, category?, location?,
 * address?, mapsUrl?, rating?, totalReviews? }] }` — an explicit list (e.g.
 * businesses extracted from an Excel archive that were never saved to
 * Firestore), same as the WhatsApp tool's `/validate-list`. `id` is only a
 * key to read each result back out of the status snapshot.
 */
export function startValidation(req, res) {
  const { leads } = req.body || {};
  if (!Array.isArray(leads) || !leads.length) {
    return res.status(400).json({ error: 'leads array is required' });
  }
  try {
    const result = startEmailValidationJob({ leads });
    return res.status(202).json(result);
  } catch (err) {
    return res.status(err.status || 500).json({ error: err.message || 'Failed to start email validation' });
  }
}

/**
 * POST /api/email-validation/validate-saved
 *
 * Body: `{ collection: 'leads' | 'websiteLeads', ids: string[] }` — Firestore
 * ids (`dbId`) of saved leads. Fields are read from Firestore by id rather
 * than trusted from the client, and leads that already carry an email are
 * skipped.
 *
 * A lead with a website has that site crawled for a contact address; one
 * without (every website lead, and some review leads) is looked up on the
 * public web instead — see `webSearchEmailDiscovery.js`. A verified address
 * is written onto the lead itself AND into the `emailLeads` collection.
 */
export async function startSavedLeadValidation(req, res) {
  const { collection, ids } = req.body || {};
  if (!Array.isArray(ids) || !ids.length) {
    return res.status(400).json({ error: 'ids array is required' });
  }
  try {
    const source = leadSource(collection);
    const found = await source.load(ids);
    const todo = found.filter((l) => !l.email);
    if (!todo.length) {
      return res.status(400).json({
        error: found.length
          ? 'Every selected business already has an email.'
          : 'None of the selected businesses were found.',
      });
    }

    const result = startEmailValidationJob({
      // `id` must be the Firestore doc id: it keys the result and is what
      // the write-back below updates.
      leads: todo.map((l) => ({ ...l, id: l.dbId, sourceType: source.sourceType })),
      requireWebsite: false,
      concurrency: WEB_SEARCH_CONCURRENCY,
      discoverFn: (website, lead) =>
        website ? discoverEmailsFromWebsite(website) : discoverEmailsByWebSearch(lead),
      saveFn: async (saved) => {
        // `emailLeads` is the browsable list; the write-back is what makes
        // the lead itself outreach-ready. Both must land or the save is
        // reported as failed on that business's result.
        await saveEmailLeadsToFirebase(saved);
        for (const lead of saved) {
          await source.setEmail(lead.dbId, lead);
        }
      },
    });
    return res.status(202).json({
      ...result,
      alreadyHadEmail: found.length - todo.length,
      notFound: ids.length - found.length,
    });
  } catch (err) {
    return res.status(err.status || 500).json({ error: err.message || 'Failed to start email validation' });
  }
}

export function getValidationStatus(_req, res) {
  const snapshot = getEmailJobSnapshot();
  if (!snapshot) return res.json({ active: false, status: 'idle' });
  return res.json({ active: snapshot.status === 'running', ...snapshot });
}

export function cancelValidation(_req, res) {
  return res.json({ success: cancelEmailValidationJob() });
}
