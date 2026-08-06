import { Router } from 'express';
import {
  startMultiSearch,
  getMultiStatus,
  cancelJob,
  cancelOneCategory,
  pauseJob,
  resumeJob,
  pauseOneCategory,
  resumeOneCategory,
} from '../controllers/multiSearchController.js';

const router = Router();

router.post('/', startMultiSearch);
router.get('/status', getMultiStatus);
router.post('/cancel', cancelJob);
router.post('/cancel-category', cancelOneCategory);
router.post('/pause', pauseJob);
router.post('/resume', resumeJob);
router.post('/pause-category', pauseOneCategory);
router.post('/resume-category', resumeOneCategory);

export default router;
