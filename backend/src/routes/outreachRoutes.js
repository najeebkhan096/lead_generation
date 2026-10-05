import { Router } from 'express';
import {
  getDashboard,
  getAnalytics,
  getSettings,
  patchSettings,
  listRecords,
  ensureAndGetRecord,
  getRecord,
  patchRecord,
  postDiscover,
  postVerify,
  postAnalyze,
  postGenerate,
  postProcess,
  postApprove,
  postReject,
  postStatus,
  listCampaigns,
  createCampaign,
  patchCampaign,
  postEnrollCampaign,
  postStartCampaign,
  postRun,
  getJob,
  postCancelJob,
  postDrainQueue,
  getQueue,
  postWebhook,
  getUnsubscribe,
} from '../controllers/outreachController.js';

const router = Router();

router.get('/unsubscribe', getUnsubscribe);
router.post('/webhooks/email', postWebhook);

router.get('/dashboard', getDashboard);
router.get('/analytics', getAnalytics);
router.get('/settings', getSettings);
router.patch('/settings', patchSettings);

router.get('/records', listRecords);
router.post('/records', ensureAndGetRecord);
router.get('/records/:id', getRecord);
router.patch('/records/:id', patchRecord);
router.post('/records/:id/discover-email', postDiscover);
router.post('/records/:id/verify-email', postVerify);
router.post('/records/:id/analyze-website', postAnalyze);
router.post('/records/:id/generate-email', postGenerate);
router.post('/records/:id/process', postProcess);
router.post('/records/:id/approve', postApprove);
router.post('/records/:id/reject', postReject);
router.post('/records/:id/status', postStatus);

router.get('/campaigns', listCampaigns);
router.post('/campaigns', createCampaign);
router.patch('/campaigns/:id', patchCampaign);
router.post('/campaigns/:id/enroll', postEnrollCampaign);
router.post('/campaigns/:id/start', postStartCampaign);
router.post('/run', postRun);

router.get('/job', getJob);
router.post('/job/cancel', postCancelJob);
router.post('/queue/drain', postDrainQueue);
router.get('/queue', getQueue);

export default router;
