import { chromium } from 'playwright';
console.log('PLAYWRIGHT_BROWSERS_PATH=', process.env.PLAYWRIGHT_BROWSERS_PATH);
console.log('launching...', Date.now());
const t0 = Date.now();
try {
  const browser = await Promise.race([
    chromium.launch({ headless: true }),
    new Promise((_, rej) => setTimeout(() => rej(new Error('timeout 8s')), 8000)),
  ]);
  console.log('launched OK in', Date.now() - t0, 'ms');
  await browser.close();
} catch (err) {
  console.log('FAILED after', Date.now() - t0, 'ms:', err.message);
}
process.exit(0);
