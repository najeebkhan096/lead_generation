import { Router, urlencoded } from 'express';
import { requireApprovedUser } from '../middleware/firebaseAuth.js';
import {
  chatErrorHandler, postBackfill, postEnsureLead, postImportLeads, postMedia, postReaction, postRefresh, postRetry, postTemplate,
  postText, webhookIncoming, webhookStatus,
} from '../controllers/twilioChatController.js';

/** Authenticated API for the mobile app: mounted at /api/outreach (before the email-outreach router). */
export const chatApiRouter = Router();
chatApiRouter.use(['/messages', '/leads'], requireApprovedUser);
chatApiRouter.post('/messages/text', postText);
chatApiRouter.post('/messages/media', postMedia);
chatApiRouter.post('/messages/template', postTemplate);
chatApiRouter.post('/messages/retry', postRetry);
chatApiRouter.post('/messages/refresh', postRefresh);
chatApiRouter.post('/messages/react', postReaction);
chatApiRouter.post('/leads', postEnsureLead);
chatApiRouter.post('/leads/import-twilio', postImportLeads);
chatApiRouter.post('/leads/:leadId/backfill', postBackfill);
chatApiRouter.use(['/messages', '/leads'], chatErrorHandler);

/** Twilio webhooks: mounted at /api/twilio/webhooks. Twilio posts form-encoded bodies. */
export const twilioWebhookRouter = Router();
twilioWebhookRouter.use(urlencoded({ extended: false }));
twilioWebhookRouter.post('/incoming', webhookIncoming);
twilioWebhookRouter.post('/status', webhookStatus);
twilioWebhookRouter.use(chatErrorHandler);
