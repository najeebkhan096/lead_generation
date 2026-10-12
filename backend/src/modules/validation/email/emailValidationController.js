import {
  startEmailValidationJob,
  getEmailJobSnapshot,
  cancelEmailValidationJob,
} from './emailValidationJob.js';
import { discoverEmailsByWebSearch } from './webSearchEmailDiscovery.js';
import { discoverEmailsFromWebsite } from './emailDiscoveryService.js';
import { leadSource } from '../../leads/leadSources.js';
import { saveEmailLeadsToFirebase, getEmailLeadsByDocIds } from './emailLeadStore.js';
import { getChecks, isEmailCheckFresh } from '../leadChecks.js';
import { leadDocId } from '../../../lib/leadIdentity.js';

// Web search is paced and slow per business, so run few lookups at once.
const WEB_SEARCH_CONCURRENCY = 3;

/**
 * Decides what an archive run actually needs to do, so running it twice
 * doesn't repeat work (archive leads have no document of their own to carry
 * a flag):
 *
 *  - already verified (in `emailLeads`)        -> reused as a result
 *  - checked recently, nothing usable found    -> skipped (`alreadyChecked`)
 *  - everything else                           -> processed
 *
 * `recheck` bypasses all of it.
 */
async function planArchiveRun(leads, { recheck }) {
  if (recheck) return { toProcess: leads, reused: {}, alreadyChecked: 0 };

  const ids = leads.map((l) => leadDocId(l));
  const [checks, verified] = await Promise.all([getChecks(leads), getEmailLeadsByDocIds(ids)]);

  const toProcess = [];
  const reused = {};
  let alreadyChecked = 0;
  leads.forEach((lead, i) => {
    const known = verified.get(ids[i]);
    if (known) {
      reused[lead.id] = {
        valid: true,
        email: known.email,
        emails: (known.emails || []).map((e) => (typeof e === 'string' ? e : e.email)).filter(Boolean),
        source: known.emailSource || null,
        foundOn: known.emailFoundOn || null,
        website: known.website || null,
        result: 'valid',
        reason: null,
        error: null,
      };
    } else if (isEmailCheckFresh(checks.get(ids[i])?.email)) {
      alreadyChecked += 1;
    } else {
      toProcess.push(lead);
    }
  });
  return { toProcess, reused, alreadyChecked };
}

/**
 * POST /api/email-validation/validate-list
 *
 * Body: `{ leads: [{ id, website, business, phone?, category?, location?,
 * address?, mapsUrl?, rating?, totalReviews? }], recheck?: boolean }` — an
 * explicit list (e.g. businesses extracted from an Excel archive that were
 * never saved to Firestore), same as the WhatsApp tool's `/validate-list`.
 * `id` is only a key to read each result back out of the status snapshot.
 *
 * Businesses already verified are reused (so the client still gets a
 * complete picture) and ones checked recently with nothing found are
 * skipped. `recheck: true` forces everything to be looked at again.
 */
export async function startValidation(req, res) {
  const { leads, recheck } = req.body || {};
  if (!Array.isArray(leads) || !leads.length) {
    return res.status(400).json({ error: 'leads array is required' });
  }
  try {
    const plan = await planArchiveRun(leads, { recheck: recheck === true });
    const withSite = plan.toProcess.filter((l) => l?.website && String(l.website).trim());
    if (!withSite.length && !Object.keys(plan.reused).length) {
      return res.status(400).json({
        code: plan.alreadyChecked ? 'ALREADY_CHECKED' : 'NOTHING_TO_CHECK',
        error: plan.alreadyChecked
          ? `All ${plan.alreadyChecked} business${plan.alreadyChecked === 1 ? ' was' : 'es were'} already checked and no email was found. Choose "re-check" to try again.`
          : 'None of the selected businesses have a website to check.',
      });
    }
    const result = startEmailValidationJob({ leads: plan.toProcess, reused: plan.reused });
    return res.status(202).json({ ...result, alreadyChecked: plan.alreadyChecked });
  } catch (err) {
    return res.status(err.status || 500).json({ error: err.message || 'Failed to start email validation' });
  }
}

/**
 * POST /api/email-validation/validate-saved
 *
 * Body: `{ collection: 'leads' | 'websiteLeads', ids: string[], recheck?:
 * boolean }` — Firestore ids (`dbId`) of saved leads. Fields are read from
 * Firestore by id rather than trusted from the client.
 *
 * Skipped: leads that already carry an email, and leads checked recently
 * with nothing found (see `leadChecks.js` for how long a negative result is
 * trusted). `recheck: true` includes the latter.
 *
 * A lead with a website has that site crawled for a contact address; one
 * without (every website lead, and some review leads) is looked up on the
 * public web instead — see `webSearchEmailDiscovery.js`. A verified address
 * is written onto the lead itself AND into the `emailLeads` collection.
 */
export async function startSavedLeadValidation(req, res) {
  const { collection, ids, recheck } = req.body || {};
  if (!Array.isArray(ids) || !ids.length) {
    return res.status(400).json({ error: 'ids array is required' });
  }
  try {
    const source = leadSource(collection);
    const found = await source.load(ids);
    const withoutEmail = found.filter((l) => !l.email);
    const checks = recheck === true ? new Map() : await getChecks(withoutEmail);
    const todo = withoutEmail.filter((l) => !isEmailCheckFresh(checks.get(leadDocId(l))?.email));
    const alreadyChecked = withoutEmail.length - todo.length;
    if (!todo.length) {
      const message = !found.length
        ? 'None of the selected businesses were found.'
        : alreadyChecked
          ? `${alreadyChecked} business${alreadyChecked === 1 ? ' was' : 'es were'} already checked and no email was found. Choose "re-check" to try again.`
          : 'Every selected business already has an email.';
      return res.status(400).json({ code: alreadyChecked ? 'ALREADY_CHECKED' : 'NOTHING_TO_CHECK', error: message });
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
      alreadyHadEmail: found.length - withoutEmail.length,
      alreadyChecked,
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
