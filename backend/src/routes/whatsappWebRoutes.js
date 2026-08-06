import { Router } from 'express';
import {
  getStatus,
  getSafetyStatus,
  connect,
  disconnect,
  startValidation,
  getValidationStatus,
  cancelValidation,
} from '../controllers/whatsappWebController.js';

const router = Router();

router.get('/status', getStatus);
router.get('/safety', getSafetyStatus);
router.post('/connect', connect);
router.post('/disconnect', disconnect);
router.post('/validate', startValidation);
router.get('/validate/status', getValidationStatus);
router.post('/validate/cancel', cancelValidation);

export default router;
