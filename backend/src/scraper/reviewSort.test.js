import { test, beforeEach } from 'node:test';
import assert from 'node:assert/strict';
import {
  SORT_STATUS,
  verifyLowestFirst,
  verifyNewestFirst,
  sortReviews,
  sortReviewsWithRetry,
  loadReviewsToBoundary,
  isSortSuccess,
  sortLowestFirst,
  readReviewCards,
  readOneStarCount,
  openReviewsPanel,
  detectSignInPrompt,
  resetSortDiagnostics,
  getSortDiagnostics,
  describeSortDiagnostics,
  setSessionMode,
} from './reviewSort.js';
import { placeHtml, manyReviews } from './mapsFixture.js';
import { useChromium } from './domTestHarness.js';

const domTest = useChromium();

beforeEach(() => {
  resetSortDiagnostics();
  setSessionMode(false);
});

// ---- pure: is this list really lowest-first? ------------------------------

test('verifyLowestFirst accepts a list that opens with the 1-star reviews', () => {
  assert.equal(verifyLowestFirst([1, 1, 2, 3, 5], 298).verified, true);
});

test('verifyLowestFirst rejects an unsorted (most-relevant) list', () => {
  const r = verifyLowestFirst([5, 5, 3, 1, 1, 2], 298);
  assert.equal(r.verified, false);
  assert.equal(r.reason, 'not_ascending');
});

test('verifyLowestFirst: business has 1-star reviews but the list does not open with one', () => {
  const r = verifyLowestFirst([3, 4, 5], 12);
  assert.equal(r.verified, false);
  assert.equal(r.reason, 'first_review_not_one_star');
});

test('verifyLowestFirst cannot confirm a run of identical high ratings', () => {
  assert.equal(verifyLowestFirst([5, 5, 5, 5]).verified, false);
  assert.equal(verifyLowestFirst([5, 5, 5, 5]).reason, 'cannot_confirm_order');
});

test('verifyLowestFirst with an unknown 1-star count falls back to the order itself', () => {
  assert.equal(verifyLowestFirst([1, 1, 4]).verified, true);
  assert.equal(verifyLowestFirst([3, 4, 5]).verified, true, 'rising ratings prove the order');
  assert.equal(verifyLowestFirst([]).verified, false);
});

test('only verified or not-needed sorts count as success', () => {
  assert.equal(isSortSuccess(SORT_STATUS.OK), true);
  assert.equal(isSortSuccess(SORT_STATUS.NO_ONE_STAR), true);
  for (const bad of [SORT_STATUS.SIGN_IN_REQUIRED, SORT_STATUS.SORT_CONTROL_MISSING, SORT_STATUS.SORT_OPTION_MISSING, SORT_STATUS.NOT_VERIFIED, SORT_STATUS.ERROR, SORT_STATUS.REVIEWS_TAB_MISSING]) {
    assert.equal(isSortSuccess(bad), false, bad);
  }
});

// ---- DOM fixtures ----------------------------------------------------------

domTest('sorting succeeds: Lowest rating is chosen and the order is verified', async (page) => {
  await page.setContent(placeHtml({ sort: 'works' }));
  assert.equal((await openReviewsPanel(page)).opened, true);
  const oneStar = await readOneStarCount(page);
  assert.equal(oneStar, 298);

  const res = await sortLowestFirst(page, { oneStarCount: oneStar });
  assert.equal(res.ok, true);
  assert.equal(res.status, SORT_STATUS.OK);
  assert.deepEqual(res.sampleStars, [1, 1, 2, 3, 5, 5], 'lowest first');

  const cards = await readReviewCards(page);
  assert.deepEqual(cards.map((c) => c.stars), [1, 1, 2, 3, 5, 5]);
  assert.equal(getSortDiagnostics().ok, 1);
});

domTest('sort controls missing: reported, not treated as sorted', async (page) => {
  await page.setContent(placeHtml({ sort: 'nocontrol' }));
  await openReviewsPanel(page);
  const res = await sortLowestFirst(page, { oneStarCount: 298 });
  assert.equal(res.ok, false);
  assert.equal(res.status, SORT_STATUS.SORT_CONTROL_MISSING);
  assert.match(res.detail, /no Sort control/i);
});

domTest('the Sort menu without "Lowest rating" is reported as such', async (page) => {
  await page.setContent(placeHtml({ sort: 'nooption' }));
  await openReviewsPanel(page);
  const res = await sortLowestFirst(page, { oneStarCount: 298 });
  assert.equal(res.ok, false);
  assert.equal(res.status, SORT_STATUS.SORT_OPTION_MISSING);
});

domTest('Google sign-in prompt: detected, dismissed, and reported as unsorted', async (page) => {
  await page.setContent(placeHtml({ sort: 'signin' }));
  await openReviewsPanel(page);
  assert.equal(await detectSignInPrompt(page), false, 'no prompt before Sort is clicked');

  const res = await sortLowestFirst(page, { oneStarCount: 298 });
  assert.equal(res.ok, false);
  assert.equal(res.status, SORT_STATUS.SIGN_IN_REQUIRED);
  assert.equal(await detectSignInPrompt(page), false, 'the prompt was closed, not left covering the page');
  assert.equal(getSortDiagnostics().signin_required, 1);
  assert.match(describeSortDiagnostics(), /npm run maps:login/);
});

domTest('a sort that silently does nothing is caught by verification', async (page) => {
  await page.setContent(placeHtml({ sort: 'broken' }));
  await openReviewsPanel(page);
  const res = await sortLowestFirst(page, { oneStarCount: 298 });
  assert.equal(res.ok, false, 'unsorted reviews must not be accepted as sorted');
  assert.equal(res.status, SORT_STATUS.NOT_VERIFIED);
  assert.deepEqual(res.sampleStars, [5, 5, 3, 1, 1, 2]);
});

domTest('a business with no 1-star reviews is not sorted at all (no sign-in risked)', async (page) => {
  await page.setContent(placeHtml({ sort: 'signin', histogram: { 5: 90, 4: 10, 3: 0, 2: 0, 1: 0 } }));
  await openReviewsPanel(page);
  const oneStar = await readOneStarCount(page);
  assert.equal(oneStar, 0);
  const res = await sortLowestFirst(page, { oneStarCount: oneStar });
  assert.equal(res.ok, true);
  assert.equal(res.status, SORT_STATUS.NO_ONE_STAR);
  assert.equal(await detectSignInPrompt(page), false, 'Sort was never clicked');
});

domTest('review cards are found without relying on the old class names', async (page) => {
  // Same cards, but Google renamed every class: only data-review-id remains.
  const html = placeHtml({ sort: 'works', withTabs: false })
    .replace(/class="jftiEf fontBodyMedium"/g, 'class="x1"')
    .replace(/class="rsqaWe"/g, 'class="y1"')
    .replace(/class="d4r55"/g, 'class="z1"');
  await page.setContent(html);
  const cards = await readReviewCards(page);
  assert.equal(cards.length, 6);
  assert.equal(cards[3].stars, 1);
  assert.equal(cards[3].date, '2 weeks ago', 'date found by its "… ago" text');
});

// ---- newest-first ------------------------------------------------------------

test('verifyNewestFirst accepts dates that run newest to oldest, rejects the rest', () => {
  assert.equal(verifyNewestFirst(['1 day ago', '2 weeks ago', '2 weeks ago', '3 months ago']).verified, true);
  const bad = verifyNewestFirst(['2 months ago', '3 weeks ago', '4 months ago', '2 weeks ago']);
  assert.equal(bad.verified, false);
  assert.equal(bad.reason, 'not_newest_first');
  assert.equal(verifyNewestFirst([]).verified, false);
  assert.equal(verifyNewestFirst(['Unknown']).verified, false);
});

domTest('sorting Newest works and is verified by the dates', async (page) => {
  await page.setContent(placeHtml({ sort: 'works' }));
  await openReviewsPanel(page);
  const res = await sortReviews(page, { order: 'newest', oneStarCount: 298 });
  assert.equal(res.ok, true);
  assert.deepEqual(res.sampleDates, ['1 week ago', '2 weeks ago', '3 weeks ago', '2 months ago', '4 months ago', '5 months ago']);
});

domTest('a Newest sort that does nothing is caught', async (page) => {
  await page.setContent(placeHtml({ sort: 'broken' }));
  await openReviewsPanel(page);
  const res = await sortReviews(page, { order: 'newest', oneStarCount: 298 });
  assert.equal(res.ok, false);
  assert.equal(res.status, SORT_STATUS.NOT_VERIFIED);
});

domTest('a Sort menu without Newest is reported', async (page) => {
  await page.setContent(placeHtml({ sort: 'nonewest' }));
  await openReviewsPanel(page);
  const res = await sortReviews(page, { order: 'newest', oneStarCount: 298 });
  assert.equal(res.status, SORT_STATUS.SORT_OPTION_MISSING);
});

domTest('a sign-in prompt is final: it is not retried', async (page) => {
  await page.setContent(placeHtml({ sort: 'signin' }));
  await openReviewsPanel(page);
  const res = await sortReviewsWithRetry(page, { order: 'newest', oneStarCount: 298, attempts: 3 });
  assert.equal(res.status, SORT_STATUS.SIGN_IN_REQUIRED);
  assert.equal(getSortDiagnostics().signin_required, 1, 'asked once, not three times');
});

// ---- reading to the boundary --------------------------------------------------

domTest('newest: scrolls through every review in the window and stops at the first older one', async (page) => {
  const reviews = [...manyReviews(40, { date: '1 week ago', prefix: 'In' }), ...manyReviews(30, { date: '3 months ago', prefix: 'Old' })];
  await page.setContent(placeHtml({ reviews, pageSize: 10, histogram: { 1: 70, 5: 100 } }));
  await openReviewsPanel(page);
  await sortReviews(page, { order: 'newest', oneStarCount: 70 });
  const { cards, boundary } = await loadReviewsToBoundary(page, { order: 'newest', windowDays: '28' });
  assert.equal(boundary, 'older_than_window');
  assert.equal(cards.filter((c) => c.reviewer.startsWith('In')).length, 40, 'all 40 in-window reviews were read');
  assert.ok(cards.length < 70, 'it did not read the old ones it did not need');
});

domTest('lowest: reads every 1-star review and stops at the first higher rating', async (page) => {
  const reviews = [...manyReviews(30, { stars: 5, prefix: 'Five' }), ...manyReviews(25, { stars: 1, prefix: 'One' })];
  await page.setContent(placeHtml({ reviews, pageSize: 10, histogram: { 1: 25, 5: 30 } }));
  await openReviewsPanel(page);
  await sortReviews(page, { order: 'lowest', oneStarCount: 25 });
  const { cards, boundary } = await loadReviewsToBoundary(page, { order: 'lowest', windowDays: '28' });
  assert.equal(boundary, 'non_one_star');
  assert.equal(cards.filter((c) => c.stars === 1).length, 25);
});

domTest('a list that simply ends is reported as exhausted, not as a cap', async (page) => {
  await page.setContent(placeHtml({ reviews: manyReviews(12, { date: '2 days ago' }), pageSize: 5, histogram: { 1: 12 } }));
  await openReviewsPanel(page);
  await sortReviews(page, { order: 'newest', oneStarCount: 12 });
  const { cards, boundary } = await loadReviewsToBoundary(page, { order: 'newest', windowDays: '28' });
  assert.equal(cards.length, 12);
  assert.equal(boundary, 'exhausted');
});

domTest('the card cap stops a runaway list and says so', async (page) => {
  await page.setContent(placeHtml({ reviews: manyReviews(60, { date: '2 days ago' }), pageSize: 20, histogram: { 1: 60 } }));
  await openReviewsPanel(page);
  await sortReviews(page, { order: 'newest', oneStarCount: 60 });
  const { boundary } = await loadReviewsToBoundary(page, { order: 'newest', windowDays: '28', maxCards: 30 });
  assert.equal(boundary, 'capped');
});
