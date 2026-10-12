import { Router } from 'express';
import {
  startValidation,
  startSavedLeadValidation,
  getValidationStatus,
  cancelValidation,
} from './emailValidationController.js';

const router = Router();

router.post('/validate-list', startValidation);
router.post('/validate-saved', startSavedLeadValidation);
router.get('/status', getValidationStatus);
router.post('/cancel', cancelValidation);

export default router;
