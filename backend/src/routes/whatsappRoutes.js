import { Router } from 'express';
import { checkWhatsAppNumber } from '../controllers/whatsappController.js';

const router = Router();

router.post('/check', checkWhatsAppNumber);

export default router;
