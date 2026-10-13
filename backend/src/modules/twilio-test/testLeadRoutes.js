import { Router } from 'express';
import { HttpError } from '../twilio-chat/validation.js';
import { chatService } from './chatService.js';
import { createTestLead, deleteTestLead, listTestLeads } from './testLeadService.js';

/**
 * Mounted at /api/twilio-test. Same trust level as the rest of the web admin
 * API (no per-request auth); it only ever creates/deletes `isTest` leads.
 */
const router = Router();

const wrap = (fn) => (req, res, next) => Promise.resolve(fn(req, res, next)).catch(next);

router.get('/leads', wrap(async (_req, res) => {
  res.json({ leads: await listTestLeads() });
}));

router.post('/leads', wrap(async (req, res) => {
  const b = req.body ?? {};
  res.status(201).json(await createTestLead({
    name: b.name, businessName: b.businessName, phoneNumber: b.phoneNumber, ownerId: b.ownerId,
  }));
}));

router.delete('/leads/:leadId', wrap(async (req, res) => {
  await deleteTestLead(req.params.leadId);
  res.json({ deleted: true });
}));

// ---- chat with a test lead ---------------------------------------------------

router.get('/leads/:leadId/chat', wrap(async (req, res) => {
  res.json(await chatService().getChat(req.params.leadId));
}));

router.post('/leads/:leadId/messages', wrap(async (req, res) => {
  const b = req.body ?? {};
  res.status(201).json({ message: await chatService().sendText(req.params.leadId, { kind: b.kind, body: b.body }) });
}));

router.post('/leads/:leadId/template', wrap(async (req, res) => {
  const b = req.body ?? {};
  res.status(201).json({
    message: await chatService().sendTemplate(req.params.leadId, {
      imageBase64: b.imageBase64, mimeType: b.mimeType, channel: b.channel,
    }),
  });
}));

router.post('/leads/:leadId/messages/:messageId/retry', wrap(async (req, res) => {
  res.json({ message: await chatService().retry(req.params.leadId, req.params.messageId) });
}));

router.post('/leads/:leadId/sync', wrap(async (req, res) => {
  res.json(await chatService().sync(req.params.leadId));
}));

router.use((err, _req, res, next) => {
  if (err instanceof HttpError) return res.status(err.status).json({ error: err.message, code: err.code });
  return next(err);
});

export default router;
