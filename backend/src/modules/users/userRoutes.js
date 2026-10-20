import { Router } from 'express';
import { getUsers, editUser, getSalesmanStats, getSalesmanContactedLeads, moveContactedLeadBack } from './userController.js';

const router = Router();

router.get('/', getUsers);
router.get('/stats', getSalesmanStats);
router.get('/:id/contacted-leads', getSalesmanContactedLeads);
router.post('/:id/contacted-leads/:leadId/move-back', moveContactedLeadBack);
router.patch('/:id', editUser);

export default router;
