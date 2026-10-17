/**
 * People who messaged the WhatsApp number.
 *
 * Their first message opens WhatsApp's 24-hour window, after which the chat
 * page can send free text with no template (and so no error 63049, which
 * blocks business-initiated marketing templates to US numbers).
 *
 * No Twilio webhook reaches this server, so `sync` reads the account's
 * inbound WhatsApp messages from the API. Each sender becomes (or is matched
 * to) a lead and its messages are stored by the same pipeline as the phone
 * app. Leads that replied are flagged `repliedViaLink` for `list`.
 */
import { getFirestore } from '../../firebase/admin.js';
import { businessFromPrefill, whatsappDigits } from '../../lib/whatsappCta.js';
import { ensureLead, ingestInbound } from '../twilio-chat/messageService.js';
import { listTwilioMedia, listTwilioMessages, twilioConfig } from '../twilio-chat/twilioClient.js';
import { HttpError, isValidE164, normalizePhone } from '../twilio-chat/validation.js';
import { defaultOwnerId } from './testLeadService.js';

const LEADS = 'outreachLeads';
const CONVS = 'outreachConversations';
const PAGE = 50;
const LIST_LIMIT = 100;

const millis = (ts) => (typeof ts?.toMillis === 'function' ? ts.toMillis() : null);

export function inboxJson(id, d) {
  return {
    id,
    name: d.name ?? '',
    businessName: d.businessName ?? '',
    phoneNumber: d.phoneNumber ?? '',
    ownerId: d.ownerId ?? '',
    createdAt: millis(d.createdAt),
    lastMessage: d.lastMessage ?? '',
    lastMessageAt: millis(d.lastMessageAt),
    unreadCount: Number(d.unreadCount) || 0,
  };
}

export function inboxService(overrides = {}) {
  const d = {
    db: getFirestore,
    config: twilioConfig,
    listTwilioMessages,
    listTwilioMedia,
    ingestInbound,
    ensureLead,
    ...overrides,
  };
  // Same owner the webhook path uses for numbers it does not know.
  const ownerId = () => process.env.OUTREACH_DEFAULT_OWNER_UID?.trim() || defaultOwnerId();
  const db = () => d.db();

  async function leadsForPhone(phone) {
    const q = await db().collection(LEADS).where('phoneNumber', '==', phone).limit(25).get();
    return q.docs.map((doc) => ({ id: doc.id, ...doc.data() }));
  }

  return {
    /** Leads that replied, most recent activity first. */
    async list() {
      const snap = await db().collection(LEADS).where('repliedViaLink', '==', true).get();
      return snap.docs
        .map((doc) => inboxJson(doc.id, doc.data()))
        .sort((a, b) => (b.lastMessageAt ?? b.createdAt ?? 0) - (a.lastMessageAt ?? a.createdAt ?? 0))
        .slice(0, LIST_LIMIT);
    },

    /** Pulls new inbound WhatsApp messages from Twilio. Safe to repeat. */
    async sync() {
      const number = whatsappDigits(d.config().whatsappNumber);
      if (!number) {
        throw new HttpError(503, 'TWILIO_WHATSAPP_NUMBER is not configured on the server.', 'NOT_CONFIGURED');
      }
      const recent = await d.listTwilioMessages({ To: `whatsapp:+${number}`, PageSize: String(PAGE) });
      const inbound = recent
        .filter((m) => m.direction === 'inbound' && /^whatsapp:/i.test(String(m.from ?? '')))
        .sort((a, b) => new Date(a.date_sent ?? a.date_created) - new Date(b.date_sent ?? b.date_created));

      let ingested = 0;
      let newLeads = 0;
      for (const m of inbound) {
        const phone = normalizePhone(m.from);
        if (!isValidE164(phone)) continue;

        let leads = await leadsForPhone(phone);
        if (leads.length) {
          const seen = await Promise.all(
            leads.map((l) => db().collection(CONVS).doc(l.id).collection('messages').doc(m.sid).get()),
          );
          if (seen.some((s) => s.exists)) continue;
        }
        if (!leads.length) {
          const made = await d.ensureLead({
            ownerId: ownerId(),
            name: phone,
            businessName: businessFromPrefill(m.body),
            phoneNumber: phone,
          });
          if (made.created) {
            newLeads += 1;
            await db().collection(LEADS).doc(made.id).update({ source: 'whatsapp-inbound' });
          }
        }

        const media = Number(m.num_media) > 0 ? await d.listTwilioMedia(m.sid) : [];
        if (!m.body && media.length === 0) continue;
        const r = await d.ingestInbound({
          sid: m.sid, from: m.from, body: m.body, media, createdAt: new Date(m.date_sent ?? m.date_created),
        });
        if (!r.stored) continue;
        ingested += 1;
        leads = await leadsForPhone(phone);
        await Promise.all(leads.map((l) => db().collection(LEADS).doc(l.id).update({ repliedViaLink: true })));
      }
      return { ingested, newLeads };
    },
  };
}
