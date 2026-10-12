import { Router } from 'express';
import {
  getStatus,
  getSafetyStatus,
  connect,
  disconnect,
  startValidation,
  startExternalValidation,
  startSavedLeadValidation,
  startAutoValidation,
  getUnvalidatedSummary,
  getValidationStatus,
  cancelValidation,
} from './whatsappWebController.js';

const router = Router();

router.get('/status', getStatus);
router.get('/safety', getSafetyStatus);
router.post('/connect', connect);
router.post('/disconnect', disconnect);
router.post('/validate', startValidation);
router.post('/validate-list', startExternalValidation);
router.post('/validate-saved', startSavedLeadValidation);
router.post('/validate-auto', startAutoValidation);
router.get('/unvalidated', getUnvalidatedSummary);
router.get('/validate/status', getValidationStatus);
router.post('/validate/cancel', cancelValidation);

export default router;
