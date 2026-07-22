/**
 * Diagnostic: force English + inspect review DOM for 1-star extraction.
 */
import { chromium } from 'playwright';
import fs from 'fs/promises';
import path from 'path';

const outDir = path.resolve('scripts/debug-out');
await fs.mkdir(outDir, { recursive: true });

const browser = await chromium.launch({
  headless: true,
  args: ['--disable-blink-features=AutomationControlled', '--no-sandbox'],
});

const context = await browser.newContext({
  userAgent:
    'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36',
  locale: 'en-US',
  extraHTTPHeaders: { 'Accept-Language': 'en-US,en;q=0.9' },
  viewport: { width: 1366, height: 900 },
});

const page = await context.newPage();
const url =
  'https://www.google.com/maps/search/Dentist+in+New+York?hl=en&gl=us';
console.log('goto', url);
await page.goto(url, { waitUntil: 'domcontentloaded', timeout: 60000 });
await page.waitForTimeout(4000);

for (const sel of ['button:has-text("Accept all")', 'button:has-text("Accept")', 'button:has-text("I agree")']) {
  try {
    const btn = page.locator(sel).first();
    if (await btn.isVisible({ timeout: 1500 })) {
      console.log('consent', sel);
      await btn.click();
      await page.waitForTimeout(2000);
      break;
    }
  } catch {}
}

const hrefs = await page.locator('div[role="feed"] a[href*="/maps/place"]').evaluateAll((as) =>
  [...new Map(as.map((a) => [a.href, a.href])).values()].slice(0, 5)
);
console.log('places', hrefs.length, hrefs[0]);

// Pick a place that likely has bad reviews — open sort lowest on a few
let target = hrefs[0];
// Prefer a URL with hl=en
target = target.includes('?') ? `${target}&hl=en` : `${target}?hl=en`;
target = target.replace(/hl=ar/g, 'hl=en');

await page.goto(target, { waitUntil: 'domcontentloaded', timeout: 45000 });
await page.waitForTimeout(3000);
console.log('place url', page.url());
console.log('h1', await page.locator('h1').first().innerText().catch(() => null));

// Click Reviews tab
const reviewTab = page.getByRole('tab', { name: /reviews/i }).or(page.locator('button[aria-label*="Reviews"]')).first();
try {
  if (await reviewTab.isVisible({ timeout: 3000 })) {
    await reviewTab.click();
    console.log('clicked reviews tab');
    await page.waitForTimeout(2500);
  }
} catch (e) {
  console.log('reviews tab', e.message);
}

// Sort
try {
  const sortBtn = page.locator('button[aria-label*="Sort reviews"], button[aria-label*="Sort"], button:has-text("Sort")').first();
  if (await sortBtn.isVisible({ timeout: 3000 })) {
    await sortBtn.click();
    await page.waitForTimeout(800);
    const opt = page.getByRole('menuitemradio', { name: /lowest/i }).or(page.getByText('Lowest rating'));
    await opt.first().click({ timeout: 3000 });
    await page.waitForTimeout(2500);
    console.log('sorted lowest');
  } else {
    console.log('no sort button');
  }
} catch (e) {
  console.log('sort err', e.message);
}

// Scroll reviews
for (let i = 0; i < 6; i++) {
  await page.mouse.wheel(0, 2000);
  await page.waitForTimeout(600);
}

await page.screenshot({ path: path.join(outDir, '03-reviews-en.png') });

const info = await page.evaluate(() => {
  const starEls = [...document.querySelectorAll('[aria-label*="star" i], [aria-label*="Star"]')];
  const labels = starEls.slice(0, 30).map((e) => e.getAttribute('aria-label'));

  const reviewRoots = [...document.querySelectorAll('div[data-review-id], div.jftiEf')];
  const samples = reviewRoots.slice(0, 8).map((root) => {
    const aria =
      root.querySelector('[aria-label*="star" i]')?.getAttribute('aria-label') ||
      root.querySelector('span[role="img"]')?.getAttribute('aria-label');
    const date = root.querySelector('.rsqaWe, span[class*="rsqa"]')?.textContent?.trim();
    const text = root.querySelector('.wiI7hc, span[class*="wiI7"]')?.textContent?.trim()?.slice(0, 120);
    const name = root.querySelector('.d4r55, div[class*="d4r"]')?.textContent?.trim();
    return { aria, date, name, text, htmlClass: root.className };
  });

  return {
    title: document.title,
    starLabelCount: labels.length,
    labels,
    reviewRootCount: reviewRoots.length,
    samples,
  };
});

console.log(JSON.stringify(info, null, 2));
await fs.writeFile(path.join(outDir, 'reviews.json'), JSON.stringify(info, null, 2));
await browser.close();
