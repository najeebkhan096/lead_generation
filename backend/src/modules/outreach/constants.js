/** Outreach pipeline enums — keep these in one place so Firestore, the
 * API, and the Flutter client never drift into ad-hoc strings. */

export const SOURCE_COLLECTIONS = ['websiteLeads', 'leads'];

export const OUTREACH_STATUSES = [
  'not_processed',
  'email_found',
  'email_verified',
  'email_invalid',
  'ready_for_review',
  'approved',
  'queued',
  'sent',
  'delivered',
  'opened',
  'replied',
  'interested',
  'not_interested',
  'bounced',
  'unsubscribed',
  'failed',
  'paused',
];

export const EMAIL_SOURCES = [
  'website',
  'contact_page',
  'about_page',
  'mailto',
  'maps_listing',
  'manual',
];

export const EMAIL_VERIFY_RESULTS = ['valid', 'invalid', 'risky', 'unknown'];

export const PIPELINE_STATUSES = ['not_started', 'running', 'completed', 'failed', 'skipped'];

export const QUEUE_STATUSES = ['pending', 'processing', 'sent', 'failed', 'cancelled'];

export const CAMPAIGN_STATUSES = ['draft', 'active', 'paused', 'completed'];

export const FOLLOW_UP_KINDS = ['initial', 'follow_up_1', 'follow_up_2'];

export const EVENT_TYPES = [
  'lead_processed',
  'email_discovered',
  'email_verified',
  'website_analyzed',
  'ai_email_generated',
  'email_approved',
  'email_rejected',
  'email_queued',
  'email_sent',
  'email_failed',
  'email_delivered',
  'email_opened',
  'email_clicked',
  'email_bounced',
  'follow_up_scheduled',
  'follow_up_cancelled',
  'reply_received',
  'unsubscribed',
  'status_changed',
];

export const BUSINESS_EMAIL_PREFIXES = [
  'info',
  'contact',
  'hello',
  'sales',
  'support',
  'admin',
  'office',
  'enquiries',
  'inquiry',
  'bookings',
  'reservations',
];

export const DISCOVERY_PATHS = ['/', '/contact', '/contact-us', '/about', '/about-us'];

export const COLLECTIONS = {
  records: 'outreachRecords',
  campaigns: 'outreachCampaigns',
  queue: 'outreachQueue',
  events: 'outreachEvents',
  unsubscribes: 'outreachUnsubscribes',
  settings: 'outreachSettings',
};

export const SETTINGS_DOC_ID = 'global';

export const DEFAULT_DAILY_LIMIT = 30;
export const DEFAULT_FOLLOW_UP_1_DAYS = 3;
export const DEFAULT_FOLLOW_UP_2_DAYS = 4;
export const DEFAULT_SEND_INTERVAL_MS = 8000;
export const DEFAULT_BATCH_SIZE = 20;
export const MAX_LEAD_RANGE = 200;

export function parseLeadRange(from, to, maxSpan = MAX_LEAD_RANGE) {
  const start = Math.max(1, Math.floor(Number(from) || 1));
  const end = Math.max(start, Math.floor(Number(to) || start));
  const count = end - start + 1;
  if (count > maxSpan) {
    const err = new Error(`Pick at most ${maxSpan} leads at a time (you chose ${count}).`);
    err.status = 400;
    throw err;
  }
  return { from: start, to: end, count };
}

export const TERMINAL_NO_FOLLOW_UP = [
  'replied',
  'interested',
  'not_interested',
  'bounced',
  'unsubscribed',
  'paused',
];
