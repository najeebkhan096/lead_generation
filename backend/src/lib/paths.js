/**
 * Filesystem anchors that must NOT depend on where a module lives.
 *
 * Runtime state — the linked WhatsApp session, the safety counters, local
 * exports — lives under `backend/` regardless of how `src/` is organized.
 * Resolving it from each module's own `__dirname` ties the data location to
 * the folder layout (move a file and the WhatsApp session is silently
 * orphaned), so every such path comes from here instead.
 */

import path from 'path';
import { fileURLToPath } from 'url';

// This file is `backend/src/lib/paths.js`.
export const BACKEND_ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../..');

export const DATA_DIR = path.join(BACKEND_ROOT, 'data');
export const EXPORTS_DIR = path.join(BACKEND_ROOT, 'exports');
export const WWEBJS_AUTH_DIR = path.join(BACKEND_ROOT, '.wwebjs_auth');
export const WWEBJS_CACHE_DIR = path.join(BACKEND_ROOT, '.wwebjs_cache');
