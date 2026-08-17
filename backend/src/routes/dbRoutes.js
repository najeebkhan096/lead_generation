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
  getSavedWebsiteLeads,
  deleteSavedWebsiteLead,
  deleteSavedWebsiteLeadsByCategory,
} from '../controllers/dbController.js';

const router = Router();

router.post('/save', saveToDatabase);
router.get('/leads', getSavedLeads);
router.patch('/leads/:id/whatsapp', setLeadWhatsAppStatus);
router.delete('/leads/:id', deleteSavedLead);
router.delete('/leads', deleteSavedLeadsByCategory);
// "Website leads" — businesses found during a scan with no website at
// all, saved automatically to their own collection alongside `leads`.
router.get('/website-leads', getSavedWebsiteLeads);
router.delete('/website-leads/:id', deleteSavedWebsiteLead);
router.delete('/website-leads', deleteSavedWebsiteLeadsByCategory);
router.get('/searches', getSavedSearches);
router.get('/stats', getDbStats);
router.post('/clear', clearDatabase);

export default router;
