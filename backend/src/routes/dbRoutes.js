import { Router } from 'express';
import {
  saveToDatabase,
  getSavedLeads,
  getSavedSearches,
  getDbStats,
} from '../controllers/dbController.js';

const router = Router();

router.post('/save', saveToDatabase);
router.get('/leads', getSavedLeads);
router.get('/searches', getSavedSearches);
router.get('/stats', getDbStats);

export default router;
