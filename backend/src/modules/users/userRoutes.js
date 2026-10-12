import { Router } from 'express';
import { getUsers, editUser } from './userController.js';

const router = Router();

router.get('/', getUsers);
router.patch('/:id', editUser);

export default router;
