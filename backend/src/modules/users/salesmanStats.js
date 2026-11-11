import { getFirestore } from '../../firebase/admin.js';
import { DEFAULT_DAILY_LEAD_LIMIT, listUsers } from './userStore.js';

// The same business day the contact limit counts by (see functions/src/leadContact.js).
const DAY_TIMEZONE = process.env.LEAD_DAY_TIMEZONE || 'Asia/Qatar';
const DEFAULT_DAYS = 14;
const MAX_DAYS = 60;

/** 'YYYY-MM-DD' for [date] in [timeZone]. */
export function dayKey(date, timeZone = DAY_TIMEZONE) {
  return new Intl.DateTimeFormat('en-CA', { timeZone, year: 'numeric', month: '2-digit', day: '2-digit' }).format(date);
}

/** The hour of the day (0 to 23) that [date] falls in, in [timeZone]. */
export function hourOf(date, timeZone = DAY_TIMEZONE) {
  return Number(new Intl.DateTimeFormat('en-GB', { timeZone, hour: '2-digit', hourCycle: 'h23' }).format(date));
}

/** The `days` day keys ending on [today], oldest first. */
export function recentDayKeys(today, days) {
  const [y, m, d] = today.split('-').map(Number);
  const base = Date.UTC(y, m - 1, d);
  const keys = [];
  for (let i = days - 1; i >= 0; i--) {
    keys.push(new Date(base - i * 86400000).toISOString().slice(0, 10));
  }
  return keys;
}

/** The two kinds of lead a salesman contacts. One daily limit covers both. */
export const KINDS = ['review', 'website'];

/**
 * Per-salesman contact stats, from the 1-star WhatsApp leads (`whatsappLeads`,
 * kind `review`), the no-website leads (`websiteLeads`, kind `website`) and the
 * user accounts (`users`). A contact is a lead whose `contactedBy` is that
 * salesman: a lead moved back to New stops counting, as it does for the limit.
 *
 * Each [leads] item is `{kind?, status, contactedBy, contactedAt, verified?}`;
 * without a `kind` it is a 1-star lead.
 *
 * Each salesman gets their contacts per day for the last `days` days (the
 * chart), today's count against their limit — both kinds together, since that
 * is what the limit counts — totals, and how often they hit the limit in that
 * window. `byKind` splits today / last 7 days / total into 1-star and
 * no-website. `totals` covers every salesman together.
 */
export function buildSalesmanStats({ users, leads, now = new Date(), days = DEFAULT_DAYS, timeZone = DAY_TIMEZONE }) {
  const today = dayKey(now, timeZone);
  const window = recentDayKeys(today, days);
  const last7 = new Set(window.slice(-7));

  const salesmen = users.map((u) => ({
    id: u.id,
    name: u.name,
    email: u.email ?? null,
    role: u.role,
    approved: u.approved === true,
    dailyLeadLimit: Number.isInteger(u.dailyLeadLimit) ? u.dailyLeadLimit : DEFAULT_DAILY_LEAD_LIMIT,
    byDay: new Map(),
    byKindDay: { review: new Map(), website: new Map() },
    hourlyToday: Array(24).fill(0),
    contactedTotal: 0,
    firstContactAt: null,
    lastContactAt: null,
  }));
  const byId = new Map(salesmen.map((s) => [s.id, s]));

  let contactedByAnyone = 0;
  let reviewLeads = 0;
  let newLeft = 0;
  let websiteLeads = 0; // verified no-website leads
  let websiteNewLeft = 0;
  const kindContacted = { review: 0, website: 0 };
  for (const lead of leads) {
    const kind = lead.kind === 'website' ? 'website' : 'review';
    const contacted = Boolean(lead.contactedBy) && Boolean(lead.contactedAt);
    if (contacted) {
      contactedByAnyone += 1;
      kindContacted[kind] += 1;
    }
    const isNew = !lead.status || lead.status === 'lead';
    if (kind === 'review' && lead.sourceType === 'review') {
      reviewLeads += 1;
      if (isNew) newLeft += 1;
    }
    if (kind === 'website' && lead.verified === true) {
      websiteLeads += 1;
      if (isNew) websiteNewLeft += 1;
    }
    const s = byId.get(lead.contactedBy);
    if (!s || !contacted) continue;
    const day = dayKey(lead.contactedAt, timeZone);
    s.byKindDay[kind].set(day, (s.byKindDay[kind].get(day) || 0) + 1);
    s.byDay.set(day, (s.byDay.get(day) || 0) + 1);
    if (day === today) s.hourlyToday[hourOf(lead.contactedAt, timeZone)] += 1;
    s.contactedTotal += 1;
    if (!s.firstContactAt || lead.contactedAt < s.firstContactAt) s.firstContactAt = lead.contactedAt;
    if (!s.lastContactAt || lead.contactedAt > s.lastContactAt) s.lastContactAt = lead.contactedAt;
  }

  const rows = salesmen.map((s) => {
    const daily = window.map((day) => ({ day, count: s.byDay.get(day) || 0 }));
    const contactedToday = s.byDay.get(today) || 0;
    const contactedLast7 = daily.filter((d) => last7.has(d.day)).reduce((sum, d) => sum + d.count, 0);
    const activeDays = [...s.byDay.values()].filter((n) => n > 0).length;
    const byKind = Object.fromEntries(
      KINDS.map((kind) => {
        const days = s.byKindDay[kind];
        const total = [...days.values()].reduce((sum, n) => sum + n, 0);
        const last7Kind = window.filter((d) => last7.has(d)).reduce((sum, d) => sum + (days.get(d) || 0), 0);
        return [kind, { today: days.get(today) || 0, last7: last7Kind, total }];
      }),
    );
    return {
      id: s.id,
      name: s.name,
      email: s.email,
      role: s.role,
      approved: s.approved,
      dailyLeadLimit: s.dailyLeadLimit,
      limitLeftToday: Math.max(0, s.dailyLeadLimit - contactedToday),
      contactedToday,
      contactedLast7,
      contactedTotal: s.contactedTotal,
      byKind,
      activeDays,
      averagePerActiveDay: activeDays ? Math.round((s.contactedTotal / activeDays) * 10) / 10 : 0,
      daysAtLimit: daily.filter((d) => d.count > 0 && d.count >= s.dailyLeadLimit).length,
      hourlyToday: s.hourlyToday,
      firstContactAt: s.firstContactAt ? s.firstContactAt.toISOString() : null,
      lastContactAt: s.lastContactAt ? s.lastContactAt.toISOString() : null,
      daily,
    };
  });
  rows.sort((a, b) => b.contactedTotal - a.contactedTotal || a.name.localeCompare(b.name));

  return {
    generatedAt: now.toISOString(),
    today,
    timeZone,
    days: window,
    totals: {
      contactedTotal: contactedByAnyone,
      contactedToday: rows.reduce((sum, r) => sum + r.contactedToday, 0),
      contactedLast7: rows.reduce((sum, r) => sum + r.contactedLast7, 0),
      activeSalesmen: rows.filter((r) => r.contactedTotal > 0).length,
      reviewLeads,
      newLeft,
      websiteLeads,
      websiteNewLeft,
      byKind: {
        review: {
          today: rows.reduce((sum, r) => sum + r.byKind.review.today, 0),
          last7: rows.reduce((sum, r) => sum + r.byKind.review.last7, 0),
          total: kindContacted.review,
        },
        website: {
          today: rows.reduce((sum, r) => sum + r.byKind.website.today, 0),
          last7: rows.reduce((sum, r) => sum + r.byKind.website.last7, 0),
          total: kindContacted.website,
        },
      },
      daily: window.map((day) => ({ day, count: rows.reduce((sum, r) => sum + (r.daily.find((d) => d.day === day)?.count || 0), 0) })),
      hourlyToday: Array.from({ length: 24 }, (_, h) => rows.reduce((sum, r) => sum + r.hourlyToday[h], 0)),
    },
    salesmen: rows,
  };
}

/** Reads the users and both kinds of lead, and builds the stats. */
export async function loadSalesmanStats({ days = DEFAULT_DAYS, now = new Date() } = {}) {
  const db = getFirestore();
  const [users, review, website] = await Promise.all([
    listUsers(),
    db.collection('whatsappLeads').get(),
    // Only what the stats read; this collection is the largest.
    db.collection('websiteLeads').select('contactedBy', 'contactedAt', 'status', 'hasWhatsApp', 'websiteStatus').get(),
  ]);
  const common = (d) => ({
    status: d.status ?? null,
    contactedBy: typeof d.contactedBy === 'string' ? d.contactedBy : null,
    contactedAt: d.contactedAt?.toDate?.() ?? null,
  });
  const leads = [
    ...review.docs.map((doc) => ({ kind: 'review', sourceType: doc.data().sourceType ?? null, ...common(doc.data()) })),
    ...website.docs.map((doc) => {
      const d = doc.data();
      return { kind: 'website', verified: d.hasWhatsApp === true && d.websiteStatus === 'missing', ...common(d) };
    }),
  ];
  return buildSalesmanStats({ users, leads, now, days });
}

export function clampDays(value) {
  const n = Number.parseInt(value, 10);
  if (!Number.isFinite(n)) return DEFAULT_DAYS;
  return Math.min(MAX_DAYS, Math.max(1, n));
}
