import { Router } from 'express';
import { addSale, getSales, editSale, removeSale, getStats, scanReviews } from '../controllers/saleController.js';

const router = Router();

router.get('/stats', getStats);
router.post('/scan-reviews', scanReviews);
router.post('/', addSale);
router.get('/', getSales);
router.patch('/:id', editSale);
router.delete('/:id', removeSale);

export default router;
