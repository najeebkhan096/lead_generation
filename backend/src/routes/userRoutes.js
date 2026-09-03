import { Router } from 'express';
import { getUsers, editUser } from '../controllers/userController.js';

const router = Router();

router.get('/', getUsers);
router.patch('/:id', editUser);

export default router;
