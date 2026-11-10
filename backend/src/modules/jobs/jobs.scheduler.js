/**
 * Daily scans and crash recovery for the Jobs module.
 *
 * Every few minutes (JOBS_SCHEDULER_TICK_MS, default 5) the scheduler looks at the searches that have a daily schedule
 * (`schedule: { enabled, timeOfDay: "03:00", timezone: "Asia/Qatar" }`) and
 * starts those that are due: it is past that time in that time zone today and
 * the search has not run on today's date. A server that was down at 03:00 and
 * comes up at 09:00 therefore still runs today's scan, once.
 *
 * At start it also picks up scans a previous process left running (see
 * scanEngine.recoverInterrupted).
 *
 * Environment:
 *   JOBS_SCHEDULER_ENABLED=false   no daily scans (manual scans still work)
 *   JOBS_AUTO_RESUME=false         leave interrupted scans for a person to resume
 *   JOBS_SCHEDULER_TICK_MS=300000
 */

import { silentLogger } from './utils/logger.js';

/** {date: 'YYYY-MM-DD', minutes} of [date] as seen in [timeZone]. */
export function localParts(date, timeZone = 'UTC') {
  const parts = new Intl.DateTimeFormat('en-CA', { timeZone, year: 'numeric', month: '2-digit', day: '2-digit', hour: '2-digit', minute: '2-digit', hourCycle: 'h23' }).formatToParts(date);
  const get = (type) => parts.find((p) => p.type === type)?.value;
  return { date: `${get('year')}-${get('month')}-${get('day')}`, minutes: Number(get('hour')) * 60 + Number(get('minute')) };
}

export function isDue(schedule, now = new Date()) {
  if (!schedule?.enabled) return false;
  const [h, m] = String(schedule.timeOfDay || '03:00').split(':').map(Number);
  let local;
  try {
    local = localParts(now, schedule.timezone || 'UTC');
  } catch {
    return false; // a bad stored time zone must not crash the tick
  }
  return schedule.lastRunDate !== local.date && local.minutes >= h * 60 + m;
}

export function createJobsScheduler({ searchStore, engine, log = silentLogger, now = () => new Date(), tickMs = 300_000, autoResume = true } = {}) {
  let timer = null;
  let ticking = false;

  async function tick() {
    if (ticking) return [];
    ticking = true;
    const started = [];
    try {
      // A scan whose server died is noticed here once its heartbeat goes stale.
      if (autoResume) {
        const resumed = await engine.recoverInterrupted({ autoResume }).catch((err) => (log.error('recovery check failed', { error: err }), []));
        if (resumed.length) log.info('resumed interrupted scans', { runs: resumed });
      }
      for (const search of await searchStore.listScheduled()) {
        if (!isDue(search.schedule, now())) continue;
        const today = localParts(now(), search.schedule.timezone || 'UTC').date;
        try {
          const run = await engine.start(search.id, { trigger: 'scheduled' });
          await searchStore.markRun(search.id, { runId: run.id, status: 'running', date: today });
          started.push(run.id);
          log.info('scheduled scan started', { searchId: search.id, runId: run.id });
        } catch (err) {
          if (err.status === 409) {
            log.info('scheduled scan postponed: the search is already being scanned', { searchId: search.id });
            continue; // try again next tick
          }
          // A configuration problem won't fix itself within the minute: don't retry until tomorrow.
          log.error('scheduled scan could not start', { searchId: search.id, error: err });
          await searchStore.markRun(search.id, { runId: null, status: 'failed', date: today }).catch(() => {});
        }
      }
    } catch (err) {
      log.error('scheduler tick failed', { error: err });
    } finally {
      ticking = false;
    }
    return started;
  }

  return {
    tick,

    async start() {
      if (timer) return;
      timer = setInterval(tick, tickMs);
      timer.unref?.();
      tick();
    },

    stop() {
      clearInterval(timer);
      timer = null;
    },
  };
}
