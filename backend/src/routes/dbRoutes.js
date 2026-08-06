import { Router } from 'express';
import {
  saveToDatabase,
  getSavedLeads,
  getSavedSearches,
  getDbStats,
  clearDatabase,
  setLeadWhatsAppStatus,
} from '../controllers/dbController.js';

const router = Router();

router.post('/save', saveToDatabase);
router.get('/leads', getSavedLeads);
router.patch('/leads/:id/whatsapp', setLeadWhatsAppStatus);
router.get('/searches', getSavedSearches);
router.get('/stats', getDbStats);
router.post('/clear', clearDatabase);

export default router;
