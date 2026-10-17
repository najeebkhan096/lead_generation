import { Router } from 'express';
import { startScan, getStatus, getCoverage, cancelScan, pauseScan, resumeScan } from './stateCityScanController.js';

const router = Router();

router.post('/', startScan);
router.get('/status', getStatus);
router.get('/coverage', getCoverage);
router.post('/cancel', cancelScan);
router.post('/pause', pauseScan);
router.post('/resume', resumeScan);

export default router;
