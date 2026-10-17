import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';

/**
 * A shared pace for opening place pages. Every worker asks before it opens a
 * page, and the answers are spaced so the whole scan stays under a requests-
 * per-minute budget however many workers there are. Staying under Google's
 * limits is what keeps a long scan alive; more workers than the budget allows
 * only wait.
 */

export function perMinuteFromEnv(env = process.env, fallback = 40) {
  const n = Number(env.MAPS_MAX_PLACES_PER_MINUTE);
  return Number.isFinite(n) && n > 0 ? Math.min(n, 120) : fallback;
}

export class PaceLimiter {
  /** @param {number} perMinute  @param {{ now?: () => number, sleep?: (ms: number) => Promise<void>, jitter?: number }} [opts] */
  constructor(perMinute, { now = Date.now, sleep = (ms) => new Promise((r) => setTimeout(r, ms)), jitter = 0.25 } = {}) {
    this.interval = 60000 / perMinute;
    this.now = now;
    this.sleep = sleep;
    this.jitter = jitter;
    this.next = 0;
  }

  /** Resolves when it is this caller's turn. Callers are served in order. */
  async acquire() {
    const t = this.now();
    // Slightly uneven spacing (never below the budget) rather than a metronome.
    const gap = this.interval * (1 + Math.random() * this.jitter);
    const at = Math.max(t, this.next);
    this.next = at + gap;
    if (at > t) await this.sleep(at - t);
  }
}

/**
 * A pace that finds the rate Google tolerates by itself, and stays under it.
 *
 *  - It starts moderate and creeps up (+2 a minute every 5 healthy minutes) to
 *    `max`.
 *  - EARLY BRAKE: when listings start failing more than usual (the pages stop
 *    loading before Google shows its explicit check), it slows by a quarter and
 *    holds, instead of waiting to be blocked.
 *  - When Google DOES show its check it halves, and remembers: the rate it was
 *    running at becomes a ceiling (75% of it) for the next hours, and the rate
 *    it held without trouble becomes the starting point of later scans.
 *
 * `store` ({ load(), save(obj) }) keeps that memory between scans.
 */
export class AdaptivePace extends PaceLimiter {
  constructor({
    start = 14,
    min = 4,
    max = 30,
    stepEveryMs = 5 * 60 * 1000,
    step = 2,
    store = null,
    capHoldMs = 12 * 60 * 60 * 1000,
    window = 60,
    failureLimit = 0.08,
    ...opts
  } = {}) {
    const memory = (() => {
      try {
        return store?.load?.() || {};
      } catch {
        return {};
      }
    })();
    const now = opts.now || Date.now;
    // A rate that recently got us blocked caps this scan; one that ran clean is where we start.
    const cap = memory.blockedAt && now() - memory.blockedAt.at < capHoldMs ? Math.max(min, Math.round(memory.blockedAt.rate * 0.75)) : null;
    const ceiling = cap ? Math.min(max, cap) : max;
    const healthyStart = memory.healthy && now() - memory.healthy.at < 7 * 24 * 60 * 60 * 1000 ? Math.round(memory.healthy.rate * 0.85) : start;
    const first = Math.min(ceiling, Math.max(min, healthyStart));
    super(first, opts);
    this.min = min;
    this.max = ceiling;
    this.configuredMax = max;
    this.learnedCap = cap;
    this.step = step;
    this.stepEveryMs = stepEveryMs;
    this.rate = first;
    this.store = store;
    this.windowSize = window;
    this.failureLimit = failureLimit;
    this.outcomes = []; // 1 = failed read, 0 = read, newest last
    this.changedAt = this.now();
    this.healthySince = this.now();
  }

  get perMinute() {
    return this.rate;
  }

  _set(rate) {
    this.rate = Math.min(this.max, Math.max(this.min, rate));
    this.interval = 60000 / this.rate;
    this.changedAt = this.now();
  }

  _remember(patch) {
    try {
      this.store?.save?.({ ...(this.store.load?.() || {}), ...patch });
    } catch {
      // memory is a convenience
    }
  }

  /** Something went well (a city finished cleanly): speed up if it has been healthy for a while. */
  noteHealthy() {
    if (this.rate < this.max && this.now() - this.changedAt >= this.stepEveryMs) this._set(this.rate + this.step);
    // Sustained half an hour at this rate without trouble: worth starting from next time.
    if (this.now() - this.healthySince >= 30 * 60 * 1000) {
      this._remember({ healthy: { rate: this.rate, at: this.now() } });
      this.healthySince = this.now();
    }
  }

  /**
   * Record a city's reads: how many pages were read and how many could not be
   * opened. Returns true if this tripped the early brake (and slowed down).
   */
  noteOutcome(read, failed) {
    for (let i = 0; i < read; i++) this.outcomes.push(0);
    for (let i = 0; i < failed; i++) this.outcomes.push(1);
    if (this.outcomes.length > this.windowSize) this.outcomes.splice(0, this.outcomes.length - this.windowSize);
    const total = this.outcomes.length;
    if (total < 20) return false;
    const rate = this.outcomes.reduce((a, b) => a + b, 0) / total;
    if (rate < this.failureLimit) return false;
    this.outcomes = []; // judge the new, slower rate on fresh evidence
    this._set(this.rate * 0.75);
    this.healthySince = this.now();
    return true;
  }

  /** Google asked us to slow down: halve the rate, and remember how fast we were going. */
  noteBlocked() {
    this._remember({ blockedAt: { rate: this.rate, at: this.now() } });
    this._set(this.rate / 2);
    this.outcomes = [];
    this.healthySince = this.now();
  }
}

/** Shared by every scan in this process. */
let shared = null;
export function sharedPace() {
  // MAPS_MAX_PLACES_PER_MINUTE is the ceiling; the pace starts below it and
  // finds its own level (see AdaptivePace), remembering between scans.
  shared ??= new AdaptivePace({ max: perMinuteFromEnv(), start: 14, store: fileStore() });
  return shared;
}

/** The pace's memory, kept in a small file next to the browser profile. */
function fileStore(file = process.env.MAPS_PACE_FILE || path.join(os.homedir(), '.leadfinder', 'pace.json')) {
  return {
    load() {
      try {
        return JSON.parse(fs.readFileSync(file, 'utf8'));
      } catch {
        return {};
      }
    },
    save(obj) {
      fs.mkdirSync(path.dirname(file), { recursive: true });
      fs.writeFileSync(file, JSON.stringify(obj));
    },
  };
}
export function _resetSharedPace() {
  shared = null;
}
