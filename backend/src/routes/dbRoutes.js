import { Router } from 'express';
import {
  saveToDatabase,
  getSavedLeads,
  getSavedSearches,
  getDbStats,
  clearDatabase,
  setLeadWhatsAppStatus,
  deleteSavedLead,
  deleteSavedLeadsByCategory,
} from '../controllers/dbController.js';

const router = Router();

router.post('/save', saveToDatabase);
router.get('/leads', getSavedLeads);
router.patch('/leads/:id/whatsapp', setLeadWhatsAppStatus);
router.delete('/leads/:id', deleteSavedLead);
router.delete('/leads', deleteSavedLeadsByCategory);
router.get('/searches', getSavedSearches);
router.get('/stats', getDbStats);
router.post('/clear', clearDatabase);

export default router;
