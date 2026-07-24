/**
 * Persist search session leads into SQLite.
 */

import { getDb } from '../db/database.js';
import { getStore } from '../utils/memoryStore.js';

function upsertLeadStmt(database) {
  return database.prepare(`
    INSERT INTO leads (
      search_id, external_id, business, category, location, address,
      phone, website, maps_url, rating, total_reviews,
      has_whatsapp, wa_link,
      bad_review_stars, bad_review_text, bad_review_date, bad_review_reviewer,
      raw_json, created_at, updated_at
    ) VALUES (
      @search_id, @external_id, @business, @category, @location, @address,
      @phone, @website, @maps_url, @rating, @total_reviews,
      @has_whatsapp, @wa_link,
      @bad_review_stars, @bad_review_text, @bad_review_date, @bad_review_reviewer,
      @raw_json, datetime('now'), datetime('now')
    )
    ON CONFLICT(maps_url) DO UPDATE SET
      search_id = excluded.search_id,
      external_id = excluded.external_id,
      business = excluded.business,
      category = excluded.category,
      location = excluded.location,
      address = excluded.address,
      phone = excluded.phone,
      website = excluded.website,
      rating = excluded.rating,
      total_reviews = excluded.total_reviews,
      has_whatsapp = excluded.has_whatsapp,
      wa_link = excluded.wa_link,
      bad_review_stars = excluded.bad_review_stars,
      bad_review_text = excluded.bad_review_text,
      bad_review_date = excluded.bad_review_date,
      bad_review_reviewer = excluded.bad_review_reviewer,
      raw_json = excluded.raw_json,
      updated_at = datetime('now')
  `);
}

function insertLeadNoMapsStmt(database) {
  return database.prepare(`
    INSERT INTO leads (
      search_id, external_id, business, category, location, address,
      phone, website, maps_url, rating, total_reviews,
      has_whatsapp, wa_link,
      bad_review_stars, bad_review_text, bad_review_date, bad_review_reviewer,
      raw_json, created_at, updated_at
    ) VALUES (
      @search_id, @external_id, @business, @category, @location, @address,
      @phone, @website, @maps_url, @rating, @total_reviews,
      @has_whatsapp, @wa_link,
      @bad_review_stars, @bad_review_text, @bad_review_date, @bad_review_reviewer,
      @raw_json, datetime('now'), datetime('now')
    )
  `);
}

function toRow(lead, searchId) {
  const bad = lead.badReview || {};
  const mapsUrl =
    lead.mapsUrl && String(lead.mapsUrl).trim()
      ? String(lead.mapsUrl).trim()
      : null;
  return {
    search_id: searchId,
    external_id: lead.id || null,
    business: lead.business || 'Unknown',
    category: lead.category || null,
    location: lead.location || null,
    address: lead.address || null,
    phone: lead.phone || null,
    website: lead.website || null,
    maps_url: mapsUrl,
    rating: lead.rating ?? null,
    total_reviews: lead.totalReviews ?? null,
    has_whatsapp: lead.hasWhatsApp ? 1 : 0,
    wa_link: lead.waLink || null,
    bad_review_stars: bad.stars ?? 1,
    bad_review_text: bad.text || null,
    bad_review_date: bad.date || null,
    bad_review_reviewer: bad.reviewer || null,
    raw_json: JSON.stringify(lead),
  };
}

function rowToLead(row) {
  if (row.raw_json) {
    try {
      return { ...JSON.parse(row.raw_json), dbId: row.id, savedAt: row.updated_at || row.created_at };
    } catch {
      // fall through
    }
  }
  return {
    dbId: row.id,
    id: row.external_id || String(row.id),
    business: row.business,
    category: row.category,
    location: row.location,
    address: row.address,
    phone: row.phone,
    website: row.website,
    mapsUrl: row.maps_url,
    rating: row.rating,
    totalReviews: row.total_reviews,
    hasWhatsApp: !!row.has_whatsapp,
    waLink: row.wa_link,
    badReview: {
      stars: row.bad_review_stars ?? 1,
      text: row.bad_review_text || '',
      date: row.bad_review_date || 'Unknown',
      reviewer: row.bad_review_reviewer,
    },
    savedAt: row.updated_at || row.created_at,
  };
}

/**
 * Save current in-memory leads (or provided list) to SQLite.
 */
export function saveLeadsToDatabase(leadsInput) {
  const store = getStore();
  const leads = Array.isArray(leadsInput) && leadsInput.length
    ? leadsInput
    : store.leads;

  if (!leads.length) {
    const err = new Error('No leads to save. Run a search first.');
    err.status = 400;
    throw err;
  }

  const database = getDb();
  const last = store.lastSearch || {};

  const insertSearch = database.prepare(`
    INSERT INTO searches (category, location, date_range, nationwide, lead_count)
    VALUES (@category, @location, @date_range, @nationwide, @lead_count)
  `);

  const upsert = upsertLeadStmt(database);
  const insertPlain = insertLeadNoMapsStmt(database);

  const tx = database.transaction((list) => {
    const info = insertSearch.run({
      category: last.category || list[0]?.category || null,
      location: last.location || 'All US states',
      date_range: last.dateRange || null,
      nationwide: last.nationwide ? 1 : 0,
      lead_count: list.length,
    });
    const searchId = info.lastInsertRowid;

    let inserted = 0;
    let updated = 0;

    for (const lead of list) {
      const row = toRow(lead, searchId);
      if (row.maps_url) {
        const before = database
          .prepare('SELECT id FROM leads WHERE maps_url = ?')
          .get(row.maps_url);
        upsert.run(row);
        if (before) updated += 1;
        else inserted += 1;
      } else {
        insertPlain.run(row);
        inserted += 1;
      }
    }

    return { searchId, inserted, updated, total: list.length };
  });

  const result = tx(leads);
  const totalInDb = database.prepare('SELECT COUNT(*) AS c FROM leads').get().c;

  return {
    ...result,
    totalInDb,
    message: `Saved ${result.total} leads (${result.inserted} new, ${result.updated} updated). Database has ${totalInDb} total.`,
  };
}

export function listSavedLeads({ limit = 200, offset = 0 } = {}) {
  const database = getDb();
  const rows = database
    .prepare(
      `SELECT * FROM leads ORDER BY updated_at DESC, id DESC LIMIT ? OFFSET ?`
    )
    .all(Math.min(Number(limit) || 200, 1000), Number(offset) || 0);

  const total = database.prepare('SELECT COUNT(*) AS c FROM leads').get().c;
  return {
    total,
    leads: rows.map(rowToLead),
  };
}

export function listSavedSearches({ limit = 50 } = {}) {
  const database = getDb();
  const rows = database
    .prepare(
      `SELECT * FROM searches ORDER BY created_at DESC, id DESC LIMIT ?`
    )
    .all(Math.min(Number(limit) || 50, 200));
  return { searches: rows };
}

export function getSavedLeadCount() {
  return getDb().prepare('SELECT COUNT(*) AS c FROM leads').get().c;
}
