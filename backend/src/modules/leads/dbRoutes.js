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
  getCategories,
  getDashboardOverview,
  getSavedWhatsAppLeads,
  deleteSavedWhatsAppLead,
  deleteSavedWhatsAppLeadsByCategory,
} from './dbController.js';

const router = Router();

router.post('/save', saveToDatabase);
router.get('/overview', getDashboardOverview);
router.get('/categories', getCategories);
router.get('/leads', getSavedLeads);
router.patch('/leads/:id/whatsapp', setLeadWhatsAppStatus);
router.delete('/leads/:id', deleteSavedLead);
router.delete('/leads', deleteSavedLeadsByCategory);
// "WhatsApp leads" — businesses whose number a real WhatsApp check
// confirmed, copied here by the WhatsApp validation job.
router.get('/whatsapp-leads', getSavedWhatsAppLeads);
router.delete('/whatsapp-leads/:id', deleteSavedWhatsAppLead);
router.delete('/whatsapp-leads', deleteSavedWhatsAppLeadsByCategory);
router.get('/searches', getSavedSearches);
router.get('/stats', getDbStats);
router.post('/clear', clearDatabase);

export default router;
