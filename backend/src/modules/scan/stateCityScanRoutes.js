import { Router } from 'express';
import { startScan, getStatus, getCoverage, cancelScan, pauseScan, resumeScan, listRuns, resumeRun, discardRun } from './stateCityScanController.js';

const router = Router();

router.post('/', startScan);
router.get('/status', getStatus);
router.get('/coverage', getCoverage);
router.post('/cancel', cancelScan);
router.post('/pause', pauseScan);
router.post('/resume', resumeScan);
// Saved no-website scans: list the ones that can be resumed, resume one, or discard it.
router.get('/runs', listRuns);
router.post('/runs/:id/resume', resumeRun);
router.delete('/runs/:id', discardRun);

export default router;
