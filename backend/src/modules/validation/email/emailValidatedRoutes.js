import { Router } from 'express';
import {
  uploadEmailVerified,
  listEmailVerified,
  getEmailVerifiedData,
  getEmailVerifiedLeads,
  downloadEmailVerified,
  removeEmailVerified,
} from './emailValidatedController.js';

const router = Router();

router.post('/', uploadEmailVerified);
router.get('/', listEmailVerified);
router.get('/:id/data', getEmailVerifiedData);
router.get('/:id/leads', getEmailVerifiedLeads);
router.get('/:id/download', downloadEmailVerified);
router.delete('/:id', removeEmailVerified);

export default router;
