import { Router } from 'express';
import { getClients, addClient, editClient, removeClient, scanReviews } from './clientController.js';

const router = Router();

router.get('/', getClients);
router.post('/', addClient);
router.post('/scan-reviews', scanReviews);
router.patch('/:id', editClient);
router.delete('/:id', removeClient);

export default router;
