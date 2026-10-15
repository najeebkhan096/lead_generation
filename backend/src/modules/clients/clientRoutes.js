import { Router } from 'express';
import { getClients, addClient, editClient, removeClient } from './clientController.js';

const router = Router();

router.get('/', getClients);
router.post('/', addClient);
router.patch('/:id', editClient);
router.delete('/:id', removeClient);

export default router;
