/**
 * Local stand-in for a Google Maps place page, for tests only. It reproduces
 * the parts the scraper touches: the overview/reviews tabs, the overall rating
 * and review count, the rating bars, review cards that load a page at a time as
 * the list is scrolled, the Sort button and its menu, and Google's "Sign in to
 * get the best of Google Maps" prompt.
 *
 * `sort` selects how the page behaves:
 *   'works'     Sort menu lists the options; choosing one reorders the cards
 *   'broken'    the menu works but choosing an option changes nothing
 *   'signin'    clicking Sort shows the sign-in prompt
 *   'nocontrol' no Sort button at all
 *   'nooption'  the menu has no "Lowest rating"
 *   'nonewest'  the menu has no "Newest"
 *
 * `pageSize` > 0 makes the list show that many reviews at first and add more
 * each time it is scrolled to the bottom (like Maps); 0 shows them all.
 */
import { parseRelativeDate } from '../lib/dateUtils.js';

const esc = (s) => String(s).replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/"/g, '&quot;');

const NOW = new Date();
const ageDays = (date) => {
  const d = parseRelativeDate(date, NOW);
  return d ? (NOW.getTime() - d.getTime()) / 86400000 : 9999;
};

/** Reviews in Google's default ("most relevant") order. */
export const DEFAULT_REVIEWS = [
  { stars: 5, date: '2 months ago', reviewer: 'Ann', text: 'Lovely' },
  { stars: 5, date: '3 weeks ago', reviewer: 'Bob', text: 'Great' },
  { stars: 3, date: '4 months ago', reviewer: 'Cy', text: 'Fine' },
  { stars: 1, date: '2 weeks ago', reviewer: 'Di', text: 'Rude staff' },
  { stars: 1, date: '5 months ago', reviewer: 'Ed', text: 'Cold coffee' },
  { stars: 2, date: '1 week ago', reviewer: 'Flo', text: 'Slow' },
];

export function placeHtml({
  name = 'Test Cafe',
  rating = 4.5,
  totalReviews = 10976,
  histogram = { 5: 7658, 4: 2133, 3: 628, 2: 259, 1: 298 },
  reviews = DEFAULT_REVIEWS,
  sort = 'works',
  withTabs = true,
  pageSize = 0,
  // Review snippets on the Overview tab, which carry data-review-id like real cards.
  overviewSnippets = false,
  // Like a restaurant page: a tall header pushes the cards below the visible
  // area, they are drawn only once the panel is scrolled to them, and choosing
  // a sort scrolls back to the top and empties the list again.
  lazyBelowFold = false,
} = {}) {
  const bars = Object.entries(histogram)
    .sort((a, b) => b[0] - a[0])
    .map(([s, n]) => `<tr aria-label="${s} stars, ${n.toLocaleString('en-US')} reviews"><td>${s}</td></tr>`)
    .join('');

  const data = reviews.map((r, i) => ({ ...r, id: `rev-${i}`, age: ageDays(r.date) }));

  const sortControl =
    sort === 'nocontrol'
      ? ''
      : `<button aria-label="Sort reviews" id="sort">Sort</button>
         <div role="menu" id="menu" style="display:none">
           <div role="menuitemradio" data-sort="relevant">Most relevant</div>
           ${sort === 'nonewest' ? '' : '<div role="menuitemradio" data-sort="newest">Newest</div>'}
           <div role="menuitemradio" data-sort="highest">Highest rating</div>
           ${sort === 'nooption' ? '' : '<div role="menuitemradio" data-sort="lowest">Lowest rating</div>'}
         </div>`;

  const listStyle = lazyBelowFold ? 'min-height:900px' : 'height:200px;overflow-y:auto'; // lazy: Maps reserves the list's height
  const panelInner = lazyBelowFold
    ? `<div style="height:300px">header: order online, summary</div><table>${bars}</table>${sortControl}<div style="height:900px">topic chips</div><div id="list" style="${listStyle}"></div>`
    : `<table>${bars}</table>${sortControl}<div id="list" style="${listStyle}"></div>`;

  return `<!doctype html><html><body>
  <h1 class="DUwDvf">${esc(name)}</h1>
  <span role="img" aria-label="${rating} stars "></span>
  <span aria-label="${totalReviews.toLocaleString('en-US')} reviews">(${totalReviews.toLocaleString('en-US')})</span>
  ${withTabs ? '<div role="tablist"><button role="tab" aria-label="Overview of Test">Overview</button><button role="tab" id="reviewsTab" aria-label="Reviews for Test">Reviews</button></div>' : ''}
  ${overviewSnippets ? '<div id="overview"><div data-review-id="snippet-1"><span>Order: brownie, latte</span></div></div>' : ''}
  <!-- like Maps, the review list does not exist until the Reviews tab is opened -->
  <div id="reviewsPanel" ${lazyBelowFold ? 'style="height:700px;overflow-y:auto"' : ''}></div>
  <div role="dialog" id="signin" style="display:none">
    <p>Sign-in to get the best of Google Maps</p>
    <button id="dismiss">Dismiss</button><button>Sign in</button>
  </div>
  <script>
    const mode = ${JSON.stringify(sort)};
    const PAGE = ${JSON.stringify(pageSize)};
    const LAZY = ${JSON.stringify(lazyBelowFold)};
    const PANEL = ${JSON.stringify(panelInner)};
    let ordered = ${JSON.stringify(data)};
    let shown = PAGE > 0 ? PAGE : ordered.length;

    function render() {
      const list = document.getElementById('list');
      if (!list) return;
      if (LAZY) {
        const panel = document.getElementById('reviewsPanel');
        // Cards exist only once the panel has been scrolled near them.
        if (panel.scrollTop + panel.clientHeight < 1450) { list.innerHTML = ''; return; }
      }
      list.innerHTML = ordered.slice(0, shown).map((r) =>
        '<div class="jftiEf fontBodyMedium" data-review-id="' + r.id + '">' +
        '<button aria-label="Actions" data-review-id="' + r.id + '"></button>' +
        '<div class="d4r55">' + r.reviewer + '</div>' +
        '<span role="img" aria-label="' + r.stars + ' star' + (r.stars === 1 ? '' : 's') + ' "></span>' +
        '<span class="rsqaWe">' + r.date + '</span>' +
        '<span class="wiI7hc">' + r.text + '</span></div>').join('');
    }
    function mount() {
      document.getElementById('reviewsPanel').innerHTML = PANEL;
      if (LAZY) document.getElementById('reviewsPanel').addEventListener('scroll', render);
      render();
      document.getElementById('list').addEventListener('scroll', (e) => {
        const el = e.target;
        if (PAGE > 0 && el.scrollTop + el.clientHeight >= el.scrollHeight - 5 && shown < ordered.length) {
          shown = Math.min(ordered.length, shown + PAGE);
          render();
        }
      });
    }
    ${withTabs ? '' : 'mount();'}

    document.addEventListener('click', (e) => {
      const t = e.target;
      if (t.closest('#reviewsTab')) {
        t.closest('#reviewsTab').setAttribute('aria-selected', 'true');
        const ov = document.getElementById('overview'); if (ov) ov.style.display = 'none';
        mount();
      } else if (t.closest('#sort')) {
        if (mode === 'signin') document.getElementById('signin').style.display = 'block';
        else document.getElementById('menu').style.display = 'block';
      } else if (t.closest('#dismiss')) {
        document.getElementById('signin').style.display = 'none';
      } else if (t.closest('[data-sort]')) {
        const by = t.closest('[data-sort]').dataset.sort;
        document.getElementById('menu').style.display = 'none';
        if (mode === 'broken') return; // the choice is ignored: order unchanged
        const base = ${JSON.stringify(data)};
        if (by === 'lowest') ordered = base.slice().sort((a, b) => a.stars - b.stars || a.age - b.age);
        else if (by === 'highest') ordered = base.slice().sort((a, b) => b.stars - a.stars);
        else if (by === 'newest') ordered = base.slice().sort((a, b) => a.age - b.age);
        else ordered = base.slice();
        shown = PAGE > 0 ? PAGE : ordered.length;
        if (LAZY) document.getElementById('reviewsPanel').scrollTop = 0; // back to the top: list empties
        render();
        if (!LAZY) document.getElementById('list').scrollTop = 0;
      }
    });
  </script></body></html>`;
}

/** Maps' header with or without a signed-in account, for session detection. */
export function accountHtml(state) {
  if (state === 'signed_in') return '<html><body><a aria-label="Google Account: Test User (t@example.com)" href="#">T</a></body></html>';
  if (state === 'signed_out') return '<html><body><a aria-label="Sign in" href="https://accounts.google.com/ServiceLogin?x=1">Sign in</a></body></html>';
  return '<html><body><p>loading</p></body></html>';
}

/** `count` reviews of `stars`, all `date`, for building large lists. */
export function manyReviews(count, { stars = 1, date = '1 week ago', prefix = 'R' } = {}) {
  return Array.from({ length: count }, (_, i) => ({ stars, date, reviewer: `${prefix}${i}`, text: `${prefix} text ${i}` }));
}
