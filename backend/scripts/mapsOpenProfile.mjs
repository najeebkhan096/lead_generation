/**
 * Opens the scanner's own Chrome profile as an ordinary window on Google Maps,
 * for a PERSON to deal with anything Google asks (for example its "unusual
 * traffic" check). Nothing here solves or skips a check: you do it, in the
 * window, the way you would in any browser. Quit that Chrome (Cmd+Q) when done.
 *
 *   npm run maps:open
 *
 * Stop the backend's scan first (a profile can only be open in one browser).
 */
import fs from 'node:fs';
import path from 'node:path';
import 'dotenv/config';
import { getSessionConfig, findChrome, launchManualLogin, ensureProfileDir } from '../src/scraper/mapsSession.js';

const cfg = getSessionConfig();
const chrome = findChrome();
if (!chrome) {
  console.error('Google Chrome was not found. Set MAPS_CHROME_PATH to its location.');
  process.exit(1);
}

// A profile can only be open once; Chrome leaves "host-pid" in SingletonLock.
let busy = false;
try {
  const pid = Number(fs.readlinkSync(path.join(cfg.profileDir, 'SingletonLock')).split('-').pop());
  if (pid) {
    process.kill(pid, 0);
    busy = true;
  }
} catch {
  // not running
}
if (busy) {
  console.error('The scanner profile is already open (a scan or another window). Stop the scan / close that window first.');
  process.exit(1);
}

ensureProfileDir(cfg.profileDir);
console.log('Opening the scanner\'s Chrome on Google Maps. Complete anything Google asks, then quit that Chrome (Cmd+Q).');
const { closed } = launchManualLogin({ executable: chrome, profileDir: cfg.profileDir, url: 'https://www.google.com/maps' });
await closed;
console.log('Closed. A paused scan checks Google again by itself; a new scan checks before it starts.');
