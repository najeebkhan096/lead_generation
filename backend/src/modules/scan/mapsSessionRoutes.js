import { Router } from 'express';
import { getStatus, login } from './mapsSessionController.js';

const router = Router();

router.get('/status', getStatus);
router.post('/login', login);

export default router;
