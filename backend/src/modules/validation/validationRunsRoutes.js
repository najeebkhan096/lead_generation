import { Router } from 'express';
import { getUnfinishedRuns, resumeRun, discardRun } from './validationRunsController.js';

const router = Router();

router.get('/', getUnfinishedRuns);
router.post('/:id/resume', resumeRun);
router.delete('/:id', discardRun);

export default router;
