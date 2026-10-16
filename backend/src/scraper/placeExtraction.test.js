import { test, beforeEach } from 'node:test';
import assert from 'node:assert/strict';
import { readRatingAndReviewCount, collectOneStarReviews } from './googleMapsScraper.js';
import { SORT_STATUS, resetSortDiagnostics } from './reviewSort.js';
import { placeHtml, manyReviews } from './mapsFixture.js';
import { isWithinRange } from '../lib/dateUtils.js';
import { useChromium } from './domTestHarness.js';

const domTest = useChromium();
beforeEach(() => resetSortDiagnostics());

domTest('rating and review count are read from their own labels, not the rating bars', async (page) => {
  await page.setContent(placeHtml({ rating: 4.5, totalReviews: 10976 }));
  assert.deepEqual(await readRatingAndReviewCount(page), { rating: 4.5, totalReviews: 10976 });
});

domTest('a label with trailing whitespace and thousands separators still parses', async (page) => {
  await page.setContent(`<span aria-label="3.8 stars ">3.8</span><span aria-label="1,234 reviews">(1,234)</span>
    <tr aria-label="5 stars, 900 reviews"></tr><tr aria-label="1 stars, 80 reviews"></tr>`);
  assert.deepEqual(await readRatingAndReviewCount(page), { rating: 3.8, totalReviews: 1234 });
});

domTest('a single review is "1 review", and the older button markup still works as a fallback', async (page) => {
  await page.setContent('<span aria-label="5.0 stars ">5.0</span><span aria-label="1 review">(1)</span>');
  assert.deepEqual(await readRatingAndReviewCount(page), { rating: 5, totalReviews: 1 });
  await page.setContent('<span aria-label="4.1 stars ">4.1</span><button aria-label="Reviews for 87 reviews" >x</button>');
  const r = await readRatingAndReviewCount(page);
  assert.equal(r.rating, 4.1);
  assert.equal(r.totalReviews, 87);
});

domTest('missing rating and count come back as null rather than the rating-bar numbers', async (page) => {
  await page.setContent('<table><tr aria-label="5 stars, 7,658 reviews"></tr><tr aria-label="1 stars, 298 reviews"></tr></table>');
  const r = await readRatingAndReviewCount(page);
  assert.equal(r.totalReviews, null);
  assert.notEqual(r.rating, 5);
});

const complete = (a) => a.complete === true && a.sorted === true;

domTest('a busy business is read Newest-first back to the window; only its 1-star reviews come back', async (page) => {
  await page.setContent(placeHtml({ sort: 'works' }));
  const { reviews, access } = await collectOneStarReviews(page, { totalReviews: 10976, dateRange: '28' });
  assert.equal(access.strategy, 'newest', '298 one-star reviews is too many to read all of');
  assert.equal(complete(access), true);
  assert.equal(access.boundary, 'older_than_window');
  assert.ok(reviews.every((r) => r.stars === 1));
  assert.deepEqual(
    reviews.filter((r) => isWithinRange(r.date, '28')).map((r) => r.reviewer),
    ['Di'],
    'the only 1-star review inside 28 days (older ones that happened to load are dropped by the date filter)',
  );
});

domTest('a business with few 1-star reviews is read Lowest-first and gets every one of them', async (page) => {
  await page.setContent(placeHtml({ sort: 'works', histogram: { 5: 900, 4: 50, 3: 20, 2: 5, 1: 2 } }));
  const { reviews, access } = await collectOneStarReviews(page, { totalReviews: 977, dateRange: '28' });
  assert.equal(access.strategy, 'lowest');
  assert.equal(complete(access), true);
  assert.equal(access.boundary, 'non_one_star');
  assert.deepEqual(reviews.map((r) => r.reviewer).sort(), ['Di', 'Ed'], 'old ones too: the date filter runs downstream');
  assert.deepEqual(access.sampleStars.slice(0, 2), [1, 1], 'proof the list is lowest-first');
});

domTest('nothing is missed on a large list that loads a page at a time', async (page) => {
  // 100 one-star reviews inside the window, 25 shown per scroll.
  await page.setContent(placeHtml({ reviews: manyReviews(100, { date: '5 days ago' }), pageSize: 25, histogram: { 1: 100 } }));
  const { reviews, access } = await collectOneStarReviews(page, { totalReviews: 100, dateRange: '28' });
  assert.equal(reviews.length, 100);
  assert.equal(complete(access), true);
});

domTest('Newest missing from the menu: falls back to Lowest-first and still reads every 1-star review', async (page) => {
  const reviews = [...manyReviews(60, { stars: 1, date: '1 week ago', prefix: 'One' }), ...manyReviews(20, { stars: 4, prefix: 'Four' })];
  await page.setContent(placeHtml({ sort: 'nonewest', reviews, pageSize: 20, histogram: { 1: 60, 4: 20 } }));
  const result = await collectOneStarReviews(page, { dateRange: '28' });
  assert.equal(result.access.strategy, 'lowest');
  assert.equal(complete(result.access), true);
  assert.equal(result.reviews.length, 60);
});

domTest('sign-in wall: visible 1-star reviews are still returned but flagged unsorted and incomplete', async (page) => {
  await page.setContent(placeHtml({ sort: 'signin' }));
  const { reviews, access } = await collectOneStarReviews(page, { totalReviews: 10976, dateRange: '28' });
  assert.equal(access.sorted, false);
  assert.equal(access.status, SORT_STATUS.SIGN_IN_REQUIRED);
  assert.equal(access.complete, false, 'unsorted reviews are not "all" the 1-star reviews');
  assert.deepEqual(reviews.map((r) => r.reviewer), ['Di', 'Ed'], 'what is visible is kept');
});

domTest('a sort that silently does nothing leaves the business flagged incomplete', async (page) => {
  await page.setContent(placeHtml({ sort: 'broken' }));
  const { access } = await collectOneStarReviews(page, { totalReviews: 10976, dateRange: '28' });
  assert.equal(access.sorted, false);
  assert.equal(access.status, SORT_STATUS.NOT_VERIFIED);
  assert.equal(access.complete, false);
});

domTest('a business with no 1-star reviews is complete without sorting', async (page) => {
  await page.setContent(placeHtml({ sort: 'signin', histogram: { 5: 90, 4: 10, 3: 0, 2: 0, 1: 0 } }));
  const { reviews, access } = await collectOneStarReviews(page, { dateRange: '28' });
  assert.deepEqual(reviews, []);
  assert.equal(access.complete, true);
  assert.equal(access.status, SORT_STATUS.NO_ONE_STAR);
});

domTest('a small business whose every review is on screen is complete even without a Sort control', async (page) => {
  await page.setContent(placeHtml({ sort: 'nocontrol', totalReviews: 6, histogram: { 5: 2, 4: 0, 3: 1, 2: 1, 1: 2 } }));
  const { access } = await collectOneStarReviews(page, { totalReviews: 6, dateRange: '28' });
  assert.equal(access.sorted, false);
  assert.equal(access.complete, true);
});

domTest('no Reviews tab: nothing is invented and the status says why', async (page) => {
  await page.setContent('<h1>Place</h1>');
  const { reviews, access } = await collectOneStarReviews(page);
  assert.deepEqual(reviews, []);
  assert.equal(access.status, SORT_STATUS.REVIEWS_TAB_MISSING);
  assert.equal(access.complete, false);
});
