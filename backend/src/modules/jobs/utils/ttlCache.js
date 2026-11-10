/**
 * A small in-memory cache with expiry that also *coalesces* concurrent loads:
 * if several scan workers ask for the same ATS board at once, one request is
 * made and all of them wait for it. Failures are not cached.
 */
export class TtlCache {
  #entries = new Map(); // key -> { value, expiresAt }
  #loading = new Map(); // key -> Promise

  constructor({ now = Date.now, maxEntries = 500 } = {}) {
    this.now = now;
    this.maxEntries = maxEntries;
  }

  get(key) {
    const hit = this.#entries.get(key);
    if (!hit) return undefined;
    if (hit.expiresAt <= this.now()) {
      this.#entries.delete(key);
      return undefined;
    }
    return hit.value;
  }

  set(key, value, ttlMs) {
    if (this.#entries.size >= this.maxEntries) this.#entries.delete(this.#entries.keys().next().value);
    this.#entries.set(key, { value, expiresAt: this.now() + ttlMs });
  }

  /** The cached value, or the (shared) result of [loader]. */
  async getOrLoad(key, loader, ttlMs) {
    const cached = this.get(key);
    if (cached !== undefined) return cached;
    if (this.#loading.has(key)) return this.#loading.get(key);
    const promise = (async () => {
      try {
        const value = await loader();
        this.set(key, value, ttlMs);
        return value;
      } finally {
        this.#loading.delete(key);
      }
    })();
    this.#loading.set(key, promise);
    return promise;
  }

  clear() {
    this.#entries.clear();
  }
}
