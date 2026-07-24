/**
 * SQLite persistence (better-sqlite3). File: backend/data/leads.db
 */

import Database from 'better-sqlite3';
import fs from 'fs';
import path from 'path';
import { fileURLToPath } from 'url';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const DATA_DIR = path.resolve(__dirname, '../../data');
const DB_PATH = process.env.DB_PATH || path.join(DATA_DIR, 'leads.db');

let db;

function migrate(database) {
  database.exec(`
    CREATE TABLE IF NOT EXISTS searches (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      category TEXT,
      location TEXT,
      date_range TEXT,
      nationwide INTEGER DEFAULT 0,
      lead_count INTEGER DEFAULT 0,
      created_at TEXT NOT NULL DEFAULT (datetime('now'))
    );

    CREATE TABLE IF NOT EXISTS leads (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      search_id INTEGER,
      external_id TEXT,
      business TEXT NOT NULL,
      category TEXT,
      location TEXT,
      address TEXT,
      phone TEXT,
      website TEXT,
      maps_url TEXT UNIQUE,
      rating REAL,
      total_reviews INTEGER,
      has_whatsapp INTEGER DEFAULT 0,
      wa_link TEXT,
      bad_review_stars INTEGER,
      bad_review_text TEXT,
      bad_review_date TEXT,
      bad_review_reviewer TEXT,
      raw_json TEXT,
      created_at TEXT NOT NULL DEFAULT (datetime('now')),
      updated_at TEXT NOT NULL DEFAULT (datetime('now')),
      FOREIGN KEY (search_id) REFERENCES searches(id)
    );

    CREATE INDEX IF NOT EXISTS idx_leads_phone ON leads(phone);
    CREATE INDEX IF NOT EXISTS idx_leads_search_id ON leads(search_id);
  `);
}

export function getDb() {
  if (db) return db;
  fs.mkdirSync(DATA_DIR, { recursive: true });
  db = new Database(DB_PATH);
  db.pragma('journal_mode = WAL');
  db.pragma('foreign_keys = ON');
  migrate(db);
  return db;
}

export function getDbPath() {
  return DB_PATH;
}

export function closeDb() {
  if (db) {
    db.close();
    db = null;
  }
}
