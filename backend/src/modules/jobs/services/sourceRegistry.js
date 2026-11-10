/**
 * The set of job-source adapters, wired to their settings, the shared HTTP
 * client and — importantly — to ONE rate gate per source for the whole
 * process, so that two scans running together still respect each source's
 * requests-per-minute and daily budget.
 *
 * Adding a source = writing an adapter class (extending JobSourceAdapter or
 * BoardAdapter) and adding it to [ADAPTER_CLASSES]; nothing else in the
 * engine names a source.
 */

import { AdzunaAdapter } from '../adapters/adzuna.js';
import { JoobleAdapter } from '../adapters/jooble.js';
import { RemotiveAdapter } from '../adapters/remotive.js';
import { GreenhouseAdapter } from '../adapters/greenhouse.js';
import { LeverAdapter } from '../adapters/lever.js';
import { AshbyAdapter } from '../adapters/ashby.js';
import { WorkableAdapter } from '../adapters/workable.js';
import { CareerPageAdapter } from '../adapters/careerPage.js';
import { createSourceGate } from '../utils/sourceGate.js';
import { createHttpClient } from '../utils/http.js';
import { TtlCache } from '../utils/ttlCache.js';
import { silentLogger } from '../utils/logger.js';
import { notFound } from '../utils/errors.js';
import { serialize } from './firestoreUtil.js';

export const ADAPTER_CLASSES = [AdzunaAdapter, JoobleAdapter, RemotiveAdapter, GreenhouseAdapter, LeverAdapter, AshbyAdapter, WorkableAdapter, CareerPageAdapter];

const USAGE_FLUSH_MS = 3000;

export function createSourceRegistry({
  sourceStore,
  http = createHttpClient(),
  env = process.env,
  log = silentLogger,
  now = () => new Date(),
  classes = ADAPTER_CLASSES,
  adapterDeps = {}, // per-adapter extra dependencies, by id (tests inject fetch/browser here)
  sleep,
} = {}) {
  const byId = new Map(classes.map((c) => [c.meta.id, c]));
  const cache = new TtlCache();
  const gates = new Map(); // id -> { gate, key }
  const pendingUsage = new Map(); // id -> usage
  let flushTimer = null;
  let stored = new Map();

  function scheduleFlush() {
    if (flushTimer || !sourceStore) return;
    flushTimer = setTimeout(async () => {
      flushTimer = null;
      const batch = [...pendingUsage.entries()];
      pendingUsage.clear();
      for (const [id, usage] of batch) await sourceStore.saveUsage(id, usage).catch((err) => log.warn('could not save source usage', { source: id, error: err }));
    }, USAGE_FLUSH_MS);
    flushTimer.unref?.();
  }

  const limitsOf = (Cls, doc) => ({ ...Cls.meta.defaultLimits, ...(doc?.limits || {}) });

  function gateFor(id) {
    const Cls = byId.get(id);
    const doc = stored.get(id);
    const limits = limitsOf(Cls, doc);
    const key = JSON.stringify(limits);
    const hit = gates.get(id);
    if (hit && hit.key === key) return hit.gate;
    const gate = createSourceGate({
      id,
      ...limits,
      initialUsage: hit ? hit.gate.usage() : doc?.usage || null,
      onUsage: (usage) => {
        pendingUsage.set(id, usage);
        scheduleFlush();
      },
      ...(sleep ? { sleep } : {}),
    });
    gates.set(id, { gate, key });
    return gate;
  }

  const registry = {
    ids: () => [...byId.keys()],

    has: (id) => byId.has(id),

    /** (Re)reads stored settings. Call before using adapters for a run. */
    async load() {
      stored = sourceStore ? await sourceStore.all() : new Map();
      return registry;
    },

    /** An adapter wired to its current settings and the shared gate. */
    adapter(id) {
      const Cls = byId.get(id);
      if (!Cls) throw notFound(`Unknown source "${id}"`);
      const doc = stored.get(id);
      return new Cls({ http, gate: gateFor(id), log: log.child ? log.child({ source: id }) : log, settings: doc?.settings || {}, env, cache, now, ...(adapterDeps[id] || {}) });
    },

    isEnabled(id) {
      return stored.get(id)?.enabled !== false;
    },

    /** Sources a run may use: enabled, and (if the search names some) the named ones. */
    selected(requested = []) {
      const ids = requested.length ? requested.filter((id) => byId.has(id)) : [...byId.keys()];
      return ids.filter((id) => registry.isEnabled(id));
    },

    /** Public description of every source (no secrets). */
    describeAll() {
      return [...byId.values()].map((Cls) => {
        const id = Cls.meta.id;
        const adapter = registry.adapter(id);
        const doc = stored.get(id) || {};
        const limits = limitsOf(Cls, doc);
        return serialize({
          ...adapter.describe(),
          enabled: registry.isEnabled(id),
          limits,
          defaultLimits: Cls.meta.defaultLimits,
          settings: {
            boards: doc.settings?.boards ?? [],
            careerPages: doc.settings?.careerPages ?? [],
            maxPages: doc.settings?.maxPages ?? null,
          },
          usageToday: gateFor(id).usage(),
          status: doc.status ?? null,
        });
      });
    },

    async flush() {
      clearTimeout(flushTimer);
      flushTimer = null;
      const batch = [...pendingUsage.entries()];
      pendingUsage.clear();
      for (const [id, usage] of batch) await sourceStore?.saveUsage(id, usage).catch(() => {});
    },

    cache,
  };
  return registry;
}
