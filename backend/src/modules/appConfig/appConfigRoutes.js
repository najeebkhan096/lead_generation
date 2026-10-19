import express, { Router } from 'express';
import { getAppUpdate, saveAppUpdate, uploadApk } from './appConfigController.js';

const router = Router();

router.get('/android', getAppUpdate);
router.put('/android', saveAppUpdate);
// The APK arrives as raw bytes (about 60 MB), not JSON.
router.post('/android/apk', express.raw({ type: () => true, limit: '200mb' }), uploadApk);

export default router;
