import { deleteRun, listUnfinished, loadRun, isResumable, effectiveStatus, saveRun } from './validationRuns.js';
import { launchAutoValidation } from './whatsapp/whatsappWebController.js';
import { launchEmailValidation } from './email/emailValidationController.js';

/** The launchers a resume uses — an object, so tests can swap them. */
export const launchers = { whatsapp: launchAutoValidation, email: launchEmailValidation };

/** The fields the page shows for an unfinished run. */
export function toRunSummary(run) {
  return {
    id: run.id,
    kind: run.kind,
    collection: run.collection,
    archiveId: run.archiveId || null,
    category: run.category || null,
    states: run.states || [],
    status: run.status, // stopped | interrupted
    total: run.total || 0,
    checked: run.checked || 0,
    found: run.found || 0,
    stoppedReason: run.stoppedReason || null,
    startedAt: run.startedAt || null,
    updatedAt: run.updatedAt || null,
  };
}

/** GET /api/validation-runs?collection=&kind= — runs that stopped before finishing. */
export async function getUnfinishedRuns(req, res) {
  try {
    const runs = await listUnfinished({
      collection: req.query?.collection ? String(req.query.collection) : undefined,
      kind: req.query?.kind ? String(req.query.kind) : undefined,
    });
    return res.json({ runs: runs.map(toRunSummary) });
  } catch (err) {
    return res.status(err.status || 500).json({ error: err.message || 'Failed to load unfinished validations' });
  }
}

/**
 * POST /api/validation-runs/:id/resume — starts the run's scope again. Leads it
 * already checked are skipped, so it carries on from where it stopped. The old
 * record is replaced by the new run's (or closed, when nothing was left).
 */
export async function resumeRun(req, res) {
  try {
    const run = await loadRun(req.params.id);
    if (!run) return res.status(404).json({ error: 'That validation is no longer on record.' });
    if (!isResumable(effectiveStatus(run))) {
      return res.status(409).json({ error: 'That validation is still running.' });
    }
    // An archive's leads live in its workbook and the page that has it open, so
    // that page resumes it (the answers already given are remembered, so it asks
    // only about the rest).
    if (run.collection === 'archive') {
      return res.status(409).json({ error: 'Resume this one from its Excel archive page.' });
    }
    const states = run.states?.length ? run.states : undefined;
    const category = run.category || undefined;
    const out =
      run.kind === 'email'
        ? await launchers.email({ states, category, recheck: run.recheck === true })
        : await launchers.whatsapp({ collection: run.collection, states, category });
    // Either way this record has done its job: a started run has a new one, and
    // a scope with nothing left is finished.
    await saveRun({ id: run.id, status: 'done', updatedAt: Date.now(), resumedAt: Date.now() });
    if (!out.started) return res.json({ success: true, message: 'Nothing was left to check — that validation is complete.' });
    return res.status(202).json({ ...out.result, runId: out.runId, message: `Resumed. ${out.message}` });
  } catch (err) {
    return res.status(err.status || 500).json({ error: err.message || 'Failed to resume the validation' });
  }
}

/** DELETE /api/validation-runs/:id — forgets an unfinished run (the leads keep their checks). */
export async function discardRun(req, res) {
  try {
    await deleteRun(req.params.id);
    return res.json({ success: true });
  } catch (err) {
    return res.status(err.status || 500).json({ error: err.message || 'Failed to discard the validation' });
  }
}
