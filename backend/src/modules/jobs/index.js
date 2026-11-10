/**
 * Jobs Finder — assembly. `createJobsModule()` builds every store, the source
 * registry, the scan engine, the scheduler and the Express router, all on the
 * real Firestore (or on a `db` you pass in — tests do).
 *
 * server wiring (src/index.js):
 *   const jobs = createJobsModule();
 *   app.use('/api/jobs', jobs.router);
 *   jobs.start();                       // after the server is listening
 */

import { geoCatalog } from './geo/geoCatalog.js';
import { createJobStore } from './services/jobStore.js';
import { createSearchStore } from './services/searchStore.js';
import { createRunStore } from './services/runStore.js';
import { createQueueStore } from './services/queueStore.js';
import { createCompanyStore } from './services/companyStore.js';
import { createApplicationStore } from './services/applicationStore.js';
import { createAlertStore } from './services/alertStore.js';
import { createSourceStore } from './services/sourceStore.js';
import { createSourceRegistry } from './services/sourceRegistry.js';
import { createScanEngine } from './services/scanEngine.js';
import { createVerifyService } from './services/verifyService.js';
import { createStatsService } from './services/statsService.js';
import { createMatcher } from './matching/matcher.js';
import { createJobsScheduler } from './jobs.scheduler.js';
import { createJobsRouter } from './routes/jobsRoutes.js';
import { createSearchController } from './controllers/searchController.js';
import { createScanController } from './controllers/scanController.js';
import { createJobController } from './controllers/jobController.js';
import { createLogger } from './utils/logger.js';
import { createHttpClient } from './utils/http.js';
import { getFirebaseStatus } from '../../firebase/admin.js';

export function createJobsModule({ db = null, env = process.env, log = createLogger('module'), routerOptions = {}, registryOptions = {}, engineOptions = {} } = {}) {
  const now = () => new Date();
  const timeoutMs = Number(env.JOBS_REQUEST_TIMEOUT_MS) || 15_000;

  const jobStore = createJobStore({ db, log: log.child({ part: 'jobs' }) });
  const searchStore = createSearchStore({ db });
  const runStore = createRunStore({ db });
  const queueStore = createQueueStore({ db });
  const companyStore = createCompanyStore({ db, jobCounter: (where) => jobStore.count(where) });
  const applicationStore = createApplicationStore({ db, jobStore });
  const alertStore = createAlertStore({ db });
  const sourceStore = createSourceStore({ db });

  const registry = createSourceRegistry({ sourceStore, env, log: log.child({ part: 'sources' }), http: createHttpClient({ timeoutMs }), ...registryOptions });
  const engine = createScanEngine({
    searchStore, runStore, queueStore, jobStore, companyStore, alertStore, sourceStore, registry,
    catalog: geoCatalog, log: log.child({ part: 'scan' }), now,
    options: { ...(env.JOBS_BREAKER_THRESHOLD ? { breakerThreshold: Number(env.JOBS_BREAKER_THRESHOLD) } : {}), ...engineOptions },
  });
  const verifyService = createVerifyService({ jobStore, registry, log: log.child({ part: 'verify' }) });
  const statsService = createStatsService({ jobStore, companyStore, applicationStore, runStore, registry });
  const matcher = createMatcher();
  const scheduler = createJobsScheduler({
    searchStore, engine, log: log.child({ part: 'scheduler' }),
    tickMs: Number(env.JOBS_SCHEDULER_TICK_MS) || 300_000,
    autoResume: env.JOBS_AUTO_RESUME !== 'false',
  });

  const controllers = {
    search: createSearchController({ catalog: geoCatalog, searchStore, runStore, registry, sourceStore }),
    scan: createScanController({ engine, runStore, queueStore, statsService }),
    job: createJobController({ jobStore, companyStore, applicationStore, alertStore, statsService, verifyService, matcher, registry, log: log.child({ part: 'api' }) }),
  };
  const router = createJobsRouter({ controllers, log: log.child({ part: 'http' }), ...routerOptions });

  return {
    router,
    engine,
    scheduler,
    registry,
    stores: { jobStore, searchStore, runStore, queueStore, companyStore, applicationStore, alertStore, sourceStore },

    /** Starts background work. Without Firebase there is nothing to schedule or resume. */
    async start() {
      if (!db && !getFirebaseStatus().configured) {
        log.warn('Jobs Finder is idle: Firebase is not configured');
        return false;
      }
      if (env.JOBS_SCHEDULER_ENABLED === 'false') {
        log.info('daily scans are off (JOBS_SCHEDULER_ENABLED=false)');
        if (env.JOBS_AUTO_RESUME !== 'false') await engine.recoverInterrupted().catch((err) => log.error('recovery failed', { error: err }));
        return true;
      }
      await scheduler.start();
      return true;
    },

    /** Graceful stop: scans pause where they are and can be resumed next start. */
    async stop() {
      scheduler.stop();
      await engine.shutdown();
      await registry.flush();
    },
  };
}
