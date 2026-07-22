import { Router } from 'express';
import {
  startSearch,
  getStatus,
  getResults,
  clearResults,
  analyze,
  outreach,
} from '../controllers/searchController.js';

const router = Router();

router.post('/', startSearch);
router.get('/status', getStatus);
router.get('/results', getResults);
router.delete('/results', clearResults);
router.post('/analyze', analyze);
router.post('/outreach', outreach);

export default router;
