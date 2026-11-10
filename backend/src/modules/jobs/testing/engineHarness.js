/**
 * Test harness for the scan engine: real stores on the fake Firestore, a
 * scripted source registry, and a real geo catalog.
 */

import { FakeFirestore } from './fakeFirestore.js';
import { createJobStore } from '../services/jobStore.js';
import { createSearchStore } from '../services/searchStore.js';
import { createRunStore } from '../services/runStore.js';
import { createQueueStore } from '../services/queueStore.js';
import { createCompanyStore } from '../services/companyStore.js';
import { createAlertStore } from '../services/alertStore.js';
import { createSourceStore } from '../services/sourceStore.js';
import { createScanEngine } from '../services/scanEngine.js';
import { geoCatalog } from '../geo/geoCatalog.js';
import { buildJob } from '../adapters/buildJob.js';

const LONG = Array.from({ length: 10 }, (_, i) => `Build mobile apps with Flutter and Dart for customers, task ${i}, working with Firebase and REST APIs daily.`).join('\n');

/** A normalized job; override anything. */
export function sampleJob(over = {}) {
  return buildJob({
    source: 'alpha',
    sourceJobId: 'a1',
    sourceUrl: 'https://alpha.test/jobs/a1',
    applyUrl: null,
    title: 'Flutter Developer',
    companyName: 'Acme Inc.',
    locationText: 'Los Angeles, CA',
    description: LONG,
    postedAt: '2026-11-05T00:00:00Z',
    ...over,
  });
}

/** A scripted source. `handler(query, ctx)` returns jobs or throws. */
export class FakeAdapter {
  constructor(id, handler, { configured = true, supports = () => true, hint = 'Set the key' } = {}) {
    this.id = id;
    this.handler = handler;
    this.configured = configured;
    this.supportsFn = supports;
    this.hint = hint;
    this.calls = [];
  }
  isConfigured() {
    return this.configured;
  }
  configurationHint() {
    return this.hint;
  }
  supports(q) {
    return this.supportsFn(q);
  }
  async search(query, opts) {
    this.calls.push(query);
    const jobs = await this.handler(query, opts, this.calls.length);
    return { jobs, pages: 1, skipped: 0, truncated: false };
  }
}

export function fakeRegistry(adapters) {
  const map = new Map(adapters.map((a) => [a.id, a]));
  return {
    async load() {},
    selected: (requested = []) => (requested.length ? requested.filter((id) => map.has(id)) : [...map.keys()]),
    adapter: (id) => map.get(id),
    isEnabled: () => true,
    async flush() {},
  };
}

export function makeHarness({ adapters = [], options = {}, now } = {}) {
  const db = new FakeFirestore();
  const clock = now || (() => new Date());
  const jobStore = createJobStore({ db, now: clock });
  const searchStore = createSearchStore({ db, now: clock });
  const runStore = createRunStore({ db, now: clock });
  const queueStore = createQueueStore({ db, now: clock });
  const companyStore = createCompanyStore({ db, now: clock });
  const alertStore = createAlertStore({ db, now: clock });
  const sourceStore = createSourceStore({ db, now: clock });
  const registry = fakeRegistry(adapters);
  const engine = createScanEngine({
    searchStore, runStore, queueStore, jobStore, companyStore, alertStore, sourceStore, registry,
    catalog: geoCatalog,
    now: clock,
    sleep: (ms) => new Promise((r) => setTimeout(r, Math.min(ms, 5))),
    options: { flushMs: 10, heartbeatMs: 30, pausePollMs: 3, comboRetryDelayMs: 1, ...options },
  });
  return { db, engine, jobStore, searchStore, runStore, queueStore, companyStore, alertStore, sourceStore, registry, adapters };
}

export const LA_SF_SEARCH = {
  name: 'Flutter in California',
  enabled: true,
  countries: [{ code: 'US', level: 'city', regions: ['California'], cities: [{ state: 'California', city: 'Los Angeles' }, { state: 'California', city: 'San Francisco' }], includeRemote: false }],
  titles: ['Flutter Developer', 'Senior Flutter Developer'],
  keywords: [],
  filters: {},
  sources: [],
  limits: { maxCombinations: 1000, maxResultsPerCombination: 50, maxPagesPerSource: 2, concurrency: 2 },
  schedule: { enabled: false, timeOfDay: '03:00', timezone: 'UTC', lastRunDate: null },
};

export async function waitFor(condition, { timeout = 3000, interval = 5 } = {}) {
  const start = Date.now();
  for (;;) {
    const value = await condition();
    if (value) return value;
    if (Date.now() - start > timeout) throw new Error('waitFor timed out');
    await new Promise((r) => setTimeout(r, interval));
  }
}
