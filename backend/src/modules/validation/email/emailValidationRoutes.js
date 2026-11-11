import { Router } from 'express';
import { startAutoValidation, getUnvalidatedSummary, getValidationStatus, cancelValidation } from './emailValidationController.js';

const router = Router();

router.post('/validate-auto', startAutoValidation);
router.get('/unvalidated', getUnvalidatedSummary);
router.get('/validate/status', getValidationStatus);
router.post('/validate/cancel', cancelValidation);

export default router;
