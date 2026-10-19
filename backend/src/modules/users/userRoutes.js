import { Router } from 'express';
import { getUsers, editUser, getSalesmanStats } from './userController.js';

const router = Router();

router.get('/', getUsers);
router.get('/stats', getSalesmanStats);
router.patch('/:id', editUser);

export default router;
