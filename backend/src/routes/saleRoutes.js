import { Router } from 'express';
import { addSale, getSales, editSale, removeSale, getStats } from '../controllers/saleController.js';

const router = Router();

router.get('/stats', getStats);
router.post('/', addSale);
router.get('/', getSales);
router.patch('/:id', editSale);
router.delete('/:id', removeSale);

export default router;
