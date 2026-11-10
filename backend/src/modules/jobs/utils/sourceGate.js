/**
 * Per-source traffic control, shared by every worker in the process.
 *
 *  - a spacing between requests (`perMinute`, with a little jitter),
 *  - a cap on requests in flight (`maxConcurrent`),
 *  - a daily budget (`perDay`) so a scan can't burn an API quota.
 *
 * Spent budget is reported as a `quota` [SourceError] — the scan records the
 * source as out of quota and carries on with the others; it is not a failure.
 */

import { SourceError } from './errors.js';

const utcDay = (ms) => new Date(ms).toISOString().slice(0, 10);

export function createSourceGate({
  id,
  perMinute = 60,
  perDay = Infinity,
  maxConcurrent = 2,
  jitter = 0.15,
  initialUsage = null, // { date, requests }
  onUsage = () => {}, // called with { date, requests } after every acquire
  now = Date.now,
  sleep = (ms) => new Promise((r) => setTimeout(r, ms)),
  random = Math.random,
} = {}) {
  const interval = perMinute > 0 ? 60_000 / perMinute : 0;
  let nextAt = 0;
  let inFlight = 0;
  const waiters = [];
  let usage = initialUsage && initialUsage.date === utcDay(now()) ? { ...initialUsage } : { date: utcDay(now()), requests: 0 };

  function rollDay() {
    const today = utcDay(now());
    if (usage.date !== today) usage = { date: today, requests: 0 };
  }

  async function takeSlot() {
    if (inFlight < maxConcurrent) {
      inFlight += 1;
      return;
    }
    await new Promise((resolve) => waiters.push(resolve));
    inFlight += 1;
  }

  function releaseSlot() {
    inFlight -= 1;
    waiters.shift()?.();
  }

  return {
    id,

    /** Requests used today (UTC) and what is left. */
    usage() {
      rollDay();
      return { ...usage, limit: Number.isFinite(perDay) ? perDay : null, remaining: Number.isFinite(perDay) ? Math.max(0, perDay - usage.requests) : null };
    },

    /**
     * Waits for this caller's turn, then runs [fn]. The budget is charged
     * when the request is *attempted*, so retries count — as they do for the
     * provider.
     */
    async run(fn) {
      rollDay();
      if (usage.requests >= perDay) {
        throw new SourceError('quota', `Daily request budget for ${id} is used up (${perDay})`, { retryable: false, source: id });
      }
      await takeSlot();
      try {
        rollDay();
        if (usage.requests >= perDay) {
          throw new SourceError('quota', `Daily request budget for ${id} is used up (${perDay})`, { retryable: false, source: id });
        }
        const t = now();
        const at = Math.max(t, nextAt);
        nextAt = at + interval * (1 + random() * jitter);
        if (at > t) await sleep(at - t);
        usage.requests += 1;
        onUsage({ ...usage });
        return await fn();
      } finally {
        releaseSlot();
      }
    },
  };
}
