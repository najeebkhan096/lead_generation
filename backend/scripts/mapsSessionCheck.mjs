/**
 * Reports whether the saved Google Maps profile is still signed in.
 *   npm run maps:session-check
 */
import { chromium } from 'playwright';
import 'dotenv/config';
import { getSessionConfig, checkSessionStatus } from '../src/scraper/mapsSession.js';
import { BROWSER_ARGS, CONTEXT_OPTIONS } from '../src/scraper/googleMapsScraper.js';

const cfg = getSessionConfig();
console.log(`Saved Google session: ${cfg.enabled ? 'in use' : 'not in use'} (mode: ${cfg.mode}; MAPS_PERSISTENT_SESSION=true/false forces it)`);
console.log(`Profile: ${cfg.profileDir}`);

const result = await checkSessionStatus({
  chromium,
  profileDir: cfg.profileDir,
  channel: cfg.channel,
  args: BROWSER_ARGS,
  contextOptions: CONTEXT_OPTIONS,
  chromePath: cfg.chromePath || undefined,
});
const meaning = {
  signed_in: 'Signed in. Scans use it automatically.',
  signed_out: 'Profile exists but is signed OUT (expired or never signed in). Run `npm run maps:login`.',
  no_profile: 'No saved profile yet. Run `npm run maps:login`.',
  locked: 'The profile is open in another browser or a running scan. Close it, or run this when no scan is running.',
  unknown: 'Could not tell (Google may have changed its page, or it did not finish loading). Try again.',
  error: 'Could not run the check.',
};
console.log(`Status: ${result.status}${result.detail ? ` (${result.detail})` : ''}`);
console.log(meaning[result.status] || '');
process.exit(result.status === 'signed_in' ? 0 : 2);
