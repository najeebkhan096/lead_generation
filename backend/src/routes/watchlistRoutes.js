import { Router } from 'express';
import { addEntry, listEntries, removeEntry, triggerScan, assignEntry } from '../controllers/watchlistController.js';

const router = Router();

router.post('/', addEntry);
router.get('/', listEntries);
router.delete('/:id', removeEntry);
router.post('/scan', triggerScan);
router.patch('/:id/assign', assignEntry);

export default router;
