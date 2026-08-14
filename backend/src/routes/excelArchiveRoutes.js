import { Router } from 'express';
import {
  listArchives,
  getArchive,
  getArchiveData,
  getArchiveLeads,
  downloadArchive,
  resumeArchive,
  removeArchive,
} from '../controllers/excelArchiveController.js';

const router = Router();

router.get('/', listArchives);
router.get('/:id', getArchive);
router.get('/:id/data', getArchiveData);
router.get('/:id/leads', getArchiveLeads);
router.get('/:id/download', downloadArchive);
router.post('/:id/resume', resumeArchive);
router.delete('/:id', removeArchive);

export default router;
