/**
 * What happens to the businesses a city scan has already read, beyond its
 * 1-star reviews:
 *
 *   no website (confirmed)        → saved to `websiteLeads`
 *   website                        → handed to the email queue
 *   website could not be told      → remembered as `unknown`, never as missing
 *
 * It only looks at data the review scan collected; it opens no Google Maps
 * page of its own. `recordCityWebsites` never throws: a failure here is
 * logged and the scan carries on, so review results cannot be lost to it.
 */

import { getFirebaseStatus } from '../../firebase/admin.js';
import { saveWebsiteLeads } from '../leads/websiteLeadStore.js';
import { recordWebsiteUnknown } from '../validation/leadChecks.js';
import { normalizePhone, waMeLink } from '../validation/whatsapp/whatsappChecker.js';
import { getEmailQueue } from './emailQueue.js';

const TAG = '[website-leads]';

let warnedUnconfigured = false;

const mapsKey = (url) => String(url || '').split('?')[0].trim().toLowerCase();

/**
 * Website status of one scraped business: `missing` only when the scraper
 * proved it (the listing was fully read and had no website link). A business
 * from a scraper that does not say gets `unknown`, never `missing`.
 */
export function websiteStatusOf(business) {
  if (business?.websiteStatus === 'missing' || business?.websiteStatus === 'available' || business?.websiteStatus === 'unknown') {
    return business.websiteStatus;
  }
  return business?.website ? 'available' : 'unknown';
}

/** The lead-shaped record for a scraped business. */
export function toSiteRecord(business, { state, country = 'US', reviewLeadKeys = new Set() } = {}) {
  const e164 = normalizePhone(business.phone, country);
  return {
    business: business.name,
    category: business.category,
    location: state || business.location,
    address: business.address || null,
    phone: e164 ? `+${e164}` : business.phone || null,
    waLink: waMeLink(e164) || null,
    website: business.website || null,
    mapsUrl: business.mapsUrl || null,
    rating: business.rating ?? null,
    totalReviews: business.totalReviews ?? null,
    source: business.source || 'google_maps',
    country,
    // One business can be several kinds of lead; this is how they are linked.
    leadTypes: reviewLeadKeys.has(mapsKey(business.mapsUrl)) ? ['review'] : [],
  };
}

/** Splits a city's businesses by website status. */
export function classifyBusinesses(businesses, options = {}) {
  const out = { missing: [], available: [], unknown: [] };
  for (const business of businesses || []) {
    if (!business?.name) continue;
    out[websiteStatusOf(business)].push(toSiteRecord(business, options));
  }
  return out;
}

/**
 * @param {object[]} businesses - what the city scan read (scrapeOneCity's `businesses`)
 * @param {object} ctx
 * @param {string} ctx.state
 * @param {string} [ctx.country]
 * @param {object[]} [ctx.reviewLeads] - the city's 1-star leads, to link lead types
 * @param {(message: string, level?: string) => void} [ctx.log] - scan activity log
 * @returns {Promise<{missing: number, available: number, unknown: number, saved: number, queued: number}>}
 */
export async function recordCityWebsites(businesses, {
  state,
  country = 'US',
  reviewLeads = [],
  log = () => {},
  saveWebsiteLeadsFn = saveWebsiteLeads,
  recordUnknownFn = recordWebsiteUnknown,
  queue,
  // A no-website scan only files businesses WITHOUT a website; it does not
  // crawl the sites of the others for emails (that is the 1-star scan's add-on).
  queueEmails = true,
  // Nowhere to store website / email leads without Firebase, so skip the lot
  // (and never start crawling sites whose results would be thrown away).
  enabled = getFirebaseStatus().configured,
} = {}) {
  const summary = { missing: 0, available: 0, unknown: 0, saved: 0, queued: 0 };
  if (!enabled) {
    if (!warnedUnconfigured) {
      warnedUnconfigured = true;
      console.warn(`${TAG} Firebase is not configured: website and email leads are not being collected.`);
    }
    return summary;
  }
  try {
    if (queueEmails) queue = queue || getEmailQueue();
    const reviewLeadKeys = new Set(reviewLeads.map((l) => mapsKey(l.mapsUrl)));
    const { missing, available, unknown } = classifyBusinesses(businesses, { state, country, reviewLeadKeys });
    summary.missing = missing.length;
    summary.available = available.length;
    summary.unknown = unknown.length;

    if (missing.length) {
      try {
        const { inserted, updated } = await saveWebsiteLeadsFn(missing);
        summary.saved = inserted;
        console.log(`${TAG} ${state}: ${missing.length} without a website — ${inserted} saved, ${updated} already on file (updated)`);
      } catch (err) {
        console.warn(`${TAG} ${state}: could not save ${missing.length} website lead(s): ${err?.message || err}`);
        log(`Website leads: could not save ${missing.length} (${err?.message || err}); the review scan is unaffected.`, 'warn');
      }
    }

    if (unknown.length) {
      console.warn(`${TAG} ${state}: website status could not be determined for ${unknown.length} business(es)`);
      for (const site of unknown) await recordUnknownFn(site, { reason: 'listing_not_fully_read' }).catch(() => {});
    }

    if (queueEmails) {
      for (const site of available) {
        if (queue.enqueue(site) === 'queued') summary.queued += 1;
      }
    }

    if (summary.missing || summary.available || summary.unknown) {
      log(
        `Websites: ${summary.missing} without a website${summary.saved ? ` (${summary.saved} new)` : ''}, ` +
          `${summary.available} with one${queueEmails ? ` (${summary.queued} queued for email lookup)` : ' (excluded)'}` +
          (summary.unknown ? `, ${summary.unknown} could not be determined` : '')
      );
    }
  } catch (err) {
    console.warn(`${TAG} ${state}: website processing failed: ${err?.message || err}`);
  }
  return summary;
}
