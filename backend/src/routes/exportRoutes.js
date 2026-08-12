import { Router } from 'express';
import { exportAsCsv, exportAsJson, exportAsXlsx, exportMultiAsXlsx } from '../controllers/exportController.js';

const router = Router();

router.get('/csv', exportAsCsv);
router.get('/json', exportAsJson);
router.get('/xlsx', exportAsXlsx);
router.get('/xlsx/multi', exportMultiAsXlsx);

export default router;
