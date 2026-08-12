import { Router } from 'express';
import {
  uploadValidated,
  listValidated,
  getValidatedData,
  getValidatedLeads,
  downloadValidated,
  removeValidated,
} from '../controllers/whatsappValidatedController.js';

const router = Router();

router.post('/', uploadValidated);
router.get('/', listValidated);
router.get('/:id/data', getValidatedData);
router.get('/:id/leads', getValidatedLeads);
router.get('/:id/download', downloadValidated);
router.delete('/:id', removeValidated);

export default router;
