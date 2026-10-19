import { execFile } from 'node:child_process';

const MB = 1024 * 1024;

/** Total resident memory in KB of every Chrome process, from `ps -axo rss=,command=` output. */
export function chromeResidentKb(psOutput) {
  let kb = 0;
  for (const line of String(psOutput).split('\n')) {
    const m = line.trim().match(/^(\d+)\s+(.*)$/);
    if (m && /chrome/i.test(m[2])) kb += Number(m[1]);
  }
  return kb;
}

function psOutput() {
  return new Promise((resolve) => {
    execFile('ps', ['-axo', 'rss=,command='], { maxBuffer: 16 * 1024 * 1024 }, (err, stdout) => resolve(err ? '' : stdout));
  });
}

/** Memory now: this process's heap and resident size, and every Chrome's together. */
export async function memorySnapshot() {
  const m = process.memoryUsage();
  return {
    heapMB: Math.round(m.heapUsed / MB),
    rssMB: Math.round(m.rss / MB),
    chromeMB: Math.round(chromeResidentKb(await psOutput()) / 1024),
  };
}

/**
 * Calls `onSnapshot` every `everyMs` until the returned `stop()` runs. The
 * timer does not keep the process alive.
 */
export function startMemoryLog(onSnapshot, { everyMs = 5 * 60 * 1000 } = {}) {
  let stopped = false;
  const tick = async () => {
    if (stopped) return;
    try {
      onSnapshot(await memorySnapshot());
    } catch {
      // a failed sample is not worth stopping the scan for
    }
  };
  const timer = setInterval(tick, everyMs);
  timer.unref?.();
  return () => {
    stopped = true;
    clearInterval(timer);
  };
}
