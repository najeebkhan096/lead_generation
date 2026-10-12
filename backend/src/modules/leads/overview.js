/**
 * Dashboard numbers, computed server-side.
 *
 * The dashboard used to download every review lead (up to 5,000 documents)
 * just to count and average them in the browser. This returns the handful
 * of numbers it actually shows — a few hundred bytes — and caches them for
 * a minute so refreshing the dashboard doesn't re-scan.
 */

import { FieldPath } from 'firebase-admin/firestore';
import { getFirestore } from '../../firebase/admin.js';
import { listFirebaseLeads, getFirebaseLeadCount } from './firebaseLeadStore.js';
import { getWebsiteLeadCount } from './websiteLeadStore.js';
import { getWhatsAppLeadCount } from '../validation/whatsapp/whatsappLeadStore.js';
import { getEmailLeadCount } from '../validation/email/emailLeadStore.js';

const TTL_MS = 60_000;
const CHUNK = 2000;
let cache = null;

async function scanReviewLeads(db) {
  const categories = new Map();
  const markets = new Set();
  let total = 0;
  let whatsAppReady = 0;
  let ratingSum = 0;
  let ratingCount = 0;
  let addedThisWeek = 0;
  const weekAgo = Date.now() - 7 * 24 * 60 * 60 * 1000;

  let last = null;
  for (;;) {
    let q = db
      .collection('leads')
      .orderBy(FieldPath.documentId())
      .select('category', 'location', 'rating', 'updatedAt', 'hasWhatsApp', 'waLink')
      .limit(CHUNK);
    if (last) q = q.startAfter(last);
    const snap = await q.get();
    for (const doc of snap.docs) {
      const d = doc.data();
      total += 1;
      const category = String(d.category || '').trim();
      if (category) categories.set(category, (categories.get(category) || 0) + 1);
      const location = String(d.location || '').trim();
      if (location) markets.add(location);
      if (d.hasWhatsApp === true || d.waLink) whatsAppReady += 1;
      if (typeof d.rating === 'number' && d.rating > 0) {
        ratingSum += d.rating;
        ratingCount += 1;
      }
      const at = d.updatedAt?.toMillis?.();
      if (at && at > weekAgo) addedThisWeek += 1;
    }
    last = snap.docs[snap.docs.length - 1];
    if (snap.docs.length < CHUNK) break;
  }

  return {
    total,
    whatsAppReady,
    categories: categories.size,
    markets: markets.size,
    avgRating: ratingCount ? ratingSum / ratingCount : null,
    addedThisWeek,
    topCategories: [...categories.entries()]
      .sort((a, b) => b[1] - a[1])
      .slice(0, 6)
      .map(([name, count]) => ({ name, count })),
  };
}

export async function getOverview({ force = false } = {}) {
  if (!force && cache && Date.now() - cache.at < TTL_MS) return cache.value;

  const db = getFirestore();
  const [review, recent, reviewCount, websiteCount, whatsappCount, emailCount] = await Promise.all([
    scanReviewLeads(db),
    listFirebaseLeads({ limit: 5 }),
    getFirebaseLeadCount(),
    getWebsiteLeadCount(),
    getWhatsAppLeadCount(),
    getEmailLeadCount(),
  ]);

  const value = {
    review,
    recent: recent.leads,
    counts: {
      reviewLeads: reviewCount,
      websiteLeads: websiteCount,
      whatsappLeads: whatsappCount,
      emailLeads: emailCount,
    },
  };
  cache = { at: Date.now(), value };
  return value;
}

export function invalidateOverview() {
  cache = null;
}
