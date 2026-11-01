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
  getSavedWebsiteLeads,
  deleteSavedWebsiteLead,
  deleteSavedWebsiteLeadsByCategory,
  getSavedEmailLeads,
  deleteSavedEmailLead,
  deleteSavedEmailLeadsByCategory,
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
// "Website leads" — businesses confirmed to have no website; "Email leads" —
// businesses whose website publishes a business email. Both are filled by the scan.
router.get('/website-leads', getSavedWebsiteLeads);
router.delete('/website-leads/:id', deleteSavedWebsiteLead);
router.delete('/website-leads', deleteSavedWebsiteLeadsByCategory);
router.get('/email-leads', getSavedEmailLeads);
router.delete('/email-leads/:id', deleteSavedEmailLead);
router.delete('/email-leads', deleteSavedEmailLeadsByCategory);
router.get('/searches', getSavedSearches);
router.get('/stats', getDbStats);
router.post('/clear', clearDatabase);

export default router;
