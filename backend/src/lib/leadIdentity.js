/**
 * How a business is identified across the lead collections.
 *
 * `leads`, `websiteLeads`, `whatsappLeads` and `emailLeads` all derive a
 * document id from the same signals, so one business scanned twice — or
 * validated from two different archives — is one document, and the same
 * business has the same id in every collection.
 */

import crypto from 'crypto';
import { COUNTRIES, countryMeta } from '../data/countries.js';

function hash(prefix, value) {
  return crypto.createHash('sha256').update(`${prefix}:${value}`).digest('hex').slice(0, 40);
}

/** Maps URL first (most stable), then phone, then name+address+location. */
export function leadDocId(lead) {
  const maps = (lead.mapsUrl || '').split('?')[0].trim().toLowerCase();
  if (maps) return hash('maps', maps);

  const phone = String(lead.phone || '').replace(/\D/g, '');
  if (phone) return hash('phone', phone);

  const key = `${lead.business || ''}|${lead.address || ''}|${lead.location || ''}`.toLowerCase();
  return hash('name', key);
}

/**
 * Tags a category with its country ("cleaning services" -> "cleaning
 * services USA") so the same category searched in different countries
 * doesn't collide. A falsy `countrySuffix` leaves the category as is — used
 * for data (e.g. archives) whose categories already carry the tag.
 */
export function withCountrySuffix(category, countrySuffix) {
  const trimmed = String(category || '').trim();
  if (!trimmed) return null;
  if (!countrySuffix || trimmed.endsWith(countrySuffix)) return trimmed;
  return `${trimmed} ${countrySuffix}`;
}

const COUNTRY_TAGS = [...new Set(Object.values(COUNTRIES).map((c) => c.shortName))];

/** True when a category already ends in a country tag ("Car Dealer USA"). */
export function hasCountryTag(category) {
  const text = String(category || '').trim();
  return COUNTRY_TAGS.some((tag) => text.endsWith(` ${tag}`));
}

/**
 * The category as every lead collection stores it: tagged with its country.
 *
 * Scans tag categories as they save them, but an Excel archive's sheet
 * names don't carry the tag — so a lead validated out of an archive arrives
 * as "Car Dealer" while the same category is "Car Dealer USA" everywhere
 * else, and category filters across collections stop lining up. Untagged
 * categories get [country]'s tag (the live scan engine is U.S.-only, so
 * the default is `USA`); already-tagged ones are left alone.
 */
export function normalizeCategory(category, country) {
  const text = String(category || '').trim();
  if (!text) return null;
  if (hasCountryTag(text)) return text;
  return withCountrySuffix(text, countryMeta(country).shortName);
}
