/**
 * A shared pace for opening place pages. Every worker asks before it opens a
 * page, and the answers are spaced so the whole scan stays under a requests-
 * per-minute budget however many workers there are. Staying under Google's
 * limits is what keeps a long scan alive; more workers than the budget allows
 * only wait.
 */

export function perMinuteFromEnv(env = process.env, fallback = 20) {
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
 * A pace that finds the rate Google tolerates by itself (additive increase,
 * multiplicative decrease, as in TCP): it starts moderate, creeps up while
 * things stay healthy, and halves whenever Google shows its "unusual traffic"
 * check. It never goes above `max` or below `min`.
 */
export class AdaptivePace extends PaceLimiter {
  constructor({ start = 14, min = 4, max = 20, stepEveryMs = 5 * 60 * 1000, step = 2, ...opts } = {}) {
    const first = Math.min(max, Math.max(min, start));
    super(first, opts);
    this.min = min;
    this.max = max;
    this.step = step;
    this.stepEveryMs = stepEveryMs;
    this.rate = first;
    this.changedAt = this.now();
  }

  get perMinute() {
    return this.rate;
  }

  _set(rate) {
    this.rate = Math.min(this.max, Math.max(this.min, rate));
    this.interval = 60000 / this.rate;
    this.changedAt = this.now();
  }

  /** Something went well (a city finished cleanly): speed up if it has been healthy for a while. */
  noteHealthy() {
    if (this.rate < this.max && this.now() - this.changedAt >= this.stepEveryMs) this._set(this.rate + this.step);
  }

  /** Google asked us to slow down: halve the rate. */
  noteBlocked() {
    this._set(this.rate / 2);
  }
}

/** Shared by every scan in this process. */
let shared = null;
export function sharedPace() {
  // MAPS_MAX_PLACES_PER_MINUTE is the ceiling; the pace starts below it and
  // finds its own level (see AdaptivePace).
  shared ??= new AdaptivePace({ max: perMinuteFromEnv(process.env, 20), start: 14 });
  return shared;
}
export function _resetSharedPace() {
  shared = null;
}
