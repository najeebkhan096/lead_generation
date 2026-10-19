import fs from 'node:fs';
import fsp from 'node:fs/promises';
import path from 'node:path';
import readline from 'node:readline';

/**
 * Where a scan keeps the leads it has found, so a long scan does not hold
 * every lead in memory. Each state's leads go into one file, one lead per
 * line (NDJSON), appended as each city finishes. Only the counts stay in
 * memory; leads are read back one at a time when a workbook is written.
 *
 * With `dir: null` the leads are kept in memory instead (tests use this).
 */
export function createLeadSpool({ dir = null } = {}) {
  if (dir) fs.mkdirSync(dir, { recursive: true });

  const counts = new Map(); // key -> leads appended so far
  const writes = new Map(); // key -> last pending append, so appends to one file run in order
  const memory = new Map(); // key -> leads, memory mode only

  const keyOf = (category, state) => JSON.stringify([category, state]);
  const fileOf = (category, state) =>
    path.join(dir, `${encodeURIComponent(category)}__${encodeURIComponent(state)}.ndjson`);

  /** Adds `leads` to a state's spool. Resolves once they are on disk. */
  function append(category, state, leads) {
    if (!leads?.length) return Promise.resolve();
    const key = keyOf(category, state);
    counts.set(key, (counts.get(key) || 0) + leads.length);
    if (!dir) {
      if (!memory.has(key)) memory.set(key, []);
      memory.get(key).push(...leads);
      return Promise.resolve();
    }
    const body = leads.map((lead) => `${JSON.stringify(lead)}\n`).join('');
    const next = (writes.get(key) || Promise.resolve()).then(() => fsp.appendFile(fileOf(category, state), body));
    writes.set(key, next.catch(() => {}));
    return next;
  }

  /** Leads appended for a state so far. */
  function count(category, state) {
    return counts.get(keyOf(category, state)) || 0;
  }

  /** The leads of a state, one at a time, in the order they were appended. */
  async function* read(category, state) {
    const key = keyOf(category, state);
    if (!dir) {
      yield* memory.get(key) || [];
      return;
    }
    await writes.get(key); // every append so far is on disk first
    if (!counts.get(key)) return;
    const lines = readline.createInterface({ input: fs.createReadStream(fileOf(category, state)), crlfDelay: Infinity });
    for await (const line of lines) {
      if (line) yield JSON.parse(line);
    }
  }

  /** Deletes the spool files. The archives on disk already hold what was saved. */
  async function remove() {
    memory.clear();
    counts.clear();
    if (dir) await fsp.rm(dir, { recursive: true, force: true });
  }

  return { dir, append, count, read, remove };
}
