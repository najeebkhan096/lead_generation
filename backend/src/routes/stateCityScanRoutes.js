import { Router } from 'express';
import { startScan, getStatus, cancelScan, pauseScan, resumeScan } from '../controllers/stateCityScanController.js';

const router = Router();

router.post('/', startScan);
router.get('/status', getStatus);
router.post('/cancel', cancelScan);
router.post('/pause', pauseScan);
router.post('/resume', resumeScan);

export default router;
