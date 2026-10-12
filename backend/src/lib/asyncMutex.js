/**
 * Minimal async mutex. Node has no OS threads here — concurrent "workers"
 * are just interleaved async tasks on one event loop — so the risk isn't
 * torn writes, it's two categories racing through a read-check-write
 * sequence (e.g. "does this lead doc already exist?") and both deciding
 * to insert. This serializes any critical section that needs to run as
 * one atomic unit from the app's point of view.
 */
export class Mutex {
  #queue = Promise.resolve();

  /**
   * @returns {Promise<() => void>} resolves once this caller holds the
   *   lock; call the returned function to release it.
   */
  acquire() {
    let release;
    const held = new Promise((resolve) => {
      release = resolve;
    });
    const acquired = this.#queue.then(() => release);
    this.#queue = this.#queue.then(() => held);
    return acquired;
  }

  /** Runs `fn` inside the lock and releases it even if `fn` throws. */
  async runExclusive(fn) {
    const release = await this.acquire();
    try {
      return await fn();
    } finally {
      release();
    }
  }
}
