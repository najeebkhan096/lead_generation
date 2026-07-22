import { Router } from 'express';
import { exportAsCsv, exportAsJson } from '../controllers/exportController.js';

const router = Router();

router.get('/csv', exportAsCsv);
router.get('/json', exportAsJson);

export default router;
