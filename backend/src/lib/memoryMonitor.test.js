import { test } from 'node:test';
import assert from 'node:assert/strict';
import { chromeResidentKb, memorySnapshot } from './memoryMonitor.js';

test('adds up the memory of every Chrome process and ignores everything else', () => {
  const ps = [
    '  2048 /Applications/Google Chrome.app/Contents/MacOS/Google Chrome --remote-debugging-port=9222',
    '  1024 /Applications/Google Chrome.app/Contents/Frameworks/Google Chrome Helper (Renderer).app/Contents/MacOS/Google Chrome Helper (Renderer)',
    '  4096 /opt/homebrew/bin/node src/index.js',
    '   512 /usr/sbin/cron',
  ].join('\n');
  assert.equal(chromeResidentKb(ps), 3072);
  assert.equal(chromeResidentKb(''), 0);
});

test('a snapshot reports this process and the Chrome total in megabytes', async () => {
  const snap = await memorySnapshot();
  assert.ok(snap.heapMB > 0);
  assert.ok(snap.rssMB >= snap.heapMB);
  assert.ok(Number.isInteger(snap.chromeMB) && snap.chromeMB >= 0);
});
