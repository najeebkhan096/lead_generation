import { Router } from 'express';
import {
  startValidation,
  startWebsiteLeadValidation,
  getValidationStatus,
  cancelValidation,
} from '../controllers/emailValidationController.js';

const router = Router();

router.post('/validate-list', startValidation);
router.post('/validate-website-leads', startWebsiteLeadValidation);
router.get('/status', getValidationStatus);
router.post('/cancel', cancelValidation);

export default router;
