/**
 * Filter businesses down to those with recent 1-star reviews.
 */

import { isWithinRange, parseRelativeDate } from '../utils/dateUtils.js';

function cleanText(value) {
  if (value == null) return value;
  // Strip Google Maps icon ligatures / private-use chars
  return String(value)
    .replace(/[\uE000-\uF8FF]/g, '')
    .replace(/\s+/g, ' ')
    .trim();
}

function sortByNewest(reviews) {
  return [...reviews].sort((a, b) => {
    const da = parseRelativeDate(a.date)?.getTime() ?? 0;
    const db = parseRelativeDate(b.date)?.getTime() ?? 0;
    return db - da;
  });
}

/**
 * @param {Array} businesses - scraped businesses with reviews[]
 * @param {{ dateRange: string }} options
 * @returns {Array} lead objects shaped for the dashboard
 */
export function filterRecentOneStarLeads(businesses, { dateRange = '30' } = {}) {
  const leads = [];

  for (const business of businesses) {
    const oneStar = (business.reviews || []).filter((r) => r.stars === 1);
    const recent = sortByNewest(oneStar.filter((r) => isWithinRange(r.date, dateRange)));

    // Heuristic: if no specific recent reviews found, but the overall rating is 1.x stars,
    // it's still a very good lead.
    const isVeryLowRated = business.rating != null && business.rating > 0 && business.rating <= 2.2;

    if (recent.length === 0 && !isVeryLowRated) continue;

    const badReview = recent.length > 0 ? recent[0] : {
      stars: business.rating ? Math.floor(business.rating) : 1,
      text: `Overall rating is ${business.rating || 'very low'}. No specific recent text scraped.`,
      date: 'Recent',
      reviewer: 'System',
    };

    leads.push({
      id: `${slug(business.name)}-${leads.length + 1}`,
      business: business.name,
      category: business.category,
      location: business.location,
      address: cleanText(business.address),
      phone: cleanText(business.phone),
      website: business.website,
      mapsUrl: business.mapsUrl,
      rating: business.rating,
      totalReviews: business.totalReviews,
      source: business.source,
      badReview: {
        stars: badReview.stars,
        text: badReview.text || '',
        date: badReview.date || 'Unknown',
        reviewer: badReview.reviewer || null,
        link: badReview.link || null,
      },
      allBadReviews: recent,
    });
  }

  return leads;
}

function slug(name) {
  return String(name || 'business')
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, '-')
    .replace(/(^-|-$)/g, '')
    .slice(0, 40);
}

/**
 * Filters scraped businesses down to the ones with no website at all —
 * a separate lead signal from `filterRecentOneStarLeads` (bad reviews):
 * any business missing a website is a "website lead" regardless of its
 * rating, so this runs against the full scraped list, not the 1-star
 * subset.
 *
 * @param {Array} businesses - scraped businesses (same shape the scraper
 *   returns — see googleMapsScraper.js)
 * @returns {Array} lead-shaped objects, ready for `enrichLeadContacts` +
 *   dedupe, same as `filterRecentOneStarLeads`'s output.
 */
export function filterNoWebsiteLeads(businesses) {
  const leads = [];

  for (const business of businesses) {
    if (business.website && String(business.website).trim()) continue;

    leads.push({
      id: `${slug(business.name)}-web-${leads.length + 1}`,
      business: business.name,
      category: business.category,
      location: business.location,
      address: cleanText(business.address),
      phone: cleanText(business.phone),
      website: null,
      mapsUrl: business.mapsUrl,
      rating: business.rating,
      totalReviews: business.totalReviews,
      source: business.source,
    });
  }

  return leads;
}
