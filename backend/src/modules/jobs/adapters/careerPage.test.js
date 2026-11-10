import { test, before, after } from 'node:test';
import assert from 'node:assert/strict';
import http from 'node:http';
import { CareerPageAdapter } from './careerPage.js';
import { createSourceGate } from '../utils/sourceGate.js';
import { createRobotsChecker } from '../utils/safeFetch.js';
import { createBrowserPool } from '../services/browserPool.js';
import { extractJobPostings, discoverJobLinks } from '../utils/jsonld.js';
import { TtlCache } from '../utils/ttlCache.js';
import { SourceError } from '../utils/errors.js';

const posting = (over = {}) => ({
  '@context': 'https://schema.org',
  '@type': 'JobPosting',
  title: 'Flutter Developer',
  description: '<p>Build apps.</p><h3>Requirements</h3><ul><li>3+ years of experience with Flutter and Dart</li><li>Bachelor degree</li></ul>',
  identifier: { '@type': 'PropertyValue', name: 'Acme', value: 'REQ-1001' },
  datePosted: '2026-11-03',
  validThrough: '2026-12-31T23:59:00Z',
  employmentType: ['FULL_TIME'],
  hiringOrganization: { '@type': 'Organization', name: 'Acme Corp', sameAs: 'https://acme.example' },
  jobLocation: { '@type': 'Place', address: { '@type': 'PostalAddress', addressLocality: 'Doha', addressRegion: 'Doha', addressCountry: 'QA' } },
  baseSalary: { '@type': 'MonetaryAmount', currency: 'QAR', value: { '@type': 'QuantitativeValue', minValue: 20000, maxValue: 28000, unitText: 'MONTH' } },
  ...over,
});
const ld = (obj) => `<script type="application/ld+json">${JSON.stringify(obj)}</script>`;
const page = (body, head = '') => `<!doctype html><html><head><title>Careers</title>${head}</head><body>${body}<p>${'Working at Acme means building things together. '.repeat(40)}</p></body></html>`;

let server;
let origin;
const hits = [];

before(async () => {
  server = http.createServer((req, res) => {
    hits.push(req.url);
    const send = (status, body, type = 'text/html') => {
      res.writeHead(status, { 'content-type': type });
      res.end(body);
    };
    switch (req.url) {
      case '/robots.txt':
        return send(200, 'User-agent: *\nDisallow: /private\n', 'text/plain');
      case '/single':
        return send(200, page(ld(posting())));
      case '/careers':
        return send(200, page('<h1>Open roles</h1><a href="/careers/jobs/1">Flutter</a><a href="/careers/jobs/2">Designer</a><a href="/about">About</a><a href="https://elsewhere.example/jobs/9">External</a>'));
      case '/careers/jobs/1':
        return send(200, page(ld(posting({ identifier: { value: 'J1' } }))));
      case '/careers/jobs/2':
        return send(200, page(ld(posting({ title: 'Product Designer', identifier: { value: 'J2' }, jobLocationType: 'TELECOMMUTE', jobLocation: undefined, applicantLocationRequirements: { '@type': 'Country', name: 'Qatar' } }))));
      case '/graph':
        return send(200, page(ld({ '@context': 'https://schema.org', '@graph': [{ '@type': 'WebSite', name: 'x' }, posting({ identifier: { value: 'G1' } }), posting({ title: 'Data Analyst', identifier: { value: 'G2' } })] })));
      case '/spa':
        // Listings are injected by JavaScript: nothing in the static HTML.
        return send(200, `<!doctype html><html><body><div id="app">Loading…</div><script>
          setTimeout(() => {
            const s = document.createElement('script'); s.type = 'application/ld+json';
            s.textContent = ${JSON.stringify(JSON.stringify(posting({ title: 'Rendered By Script', identifier: { value: 'SPA1' } })))};
            document.head.appendChild(s);
            document.getElementById('app').textContent = 'Roles loaded. ' + 'We build things together. '.repeat(80);
          }, 50);
        </script></body></html>`);
      case '/forbidden':
        return send(403, 'no');
      case '/gone':
        return send(404, 'gone');
      case '/challenge':
        return send(200, '<html><head><title>Just a moment...</title></head><body>Checking your browser <div class="cf-challenge"></div></body></html>');
      case '/private/jobs':
        return send(200, page(ld(posting())));
      case '/redirect-private':
        res.writeHead(302, { location: 'http://10.0.0.5/secret' });
        return res.end();
      case '/empty':
        return send(200, page('<p>No openings right now.</p>'));
      default:
        return send(404, 'nope');
    }
  });
  await new Promise((r) => server.listen(0, '127.0.0.1', r));
  origin = `http://127.0.0.1:${server.address().port}`;
});

after(async () => {
  await new Promise((r) => server.close(r));
});

// The test server is on loopback, which the production URL check (rightly) refuses.
const allowLoopback = (raw) => {
  try {
    const u = new URL(raw);
    if (u.hostname === '127.0.0.1') return u.href.replace(/#.*/, '');
    if (/^(10\.|192\.168\.|127\.|169\.254\.)/.test(u.hostname) || !u.hostname.includes('.')) return null;
    return u.href;
  } catch {
    return null;
  }
};

function adapter(pages, { browser, extra = {} } = {}) {
  return new CareerPageAdapter({
    http: {},
    gate: createSourceGate({ id: 'career_page', perMinute: 600000, maxConcurrent: 4, sleep: async () => {}, jitter: 0 }),
    settings: { careerPages: pages },
    cache: new TtlCache(),
    normalizeUrl: allowLoopback,
    robots: createRobotsChecker({}),
    browserPool: browser || { enabled: false },
    ...extra,
  });
}
const Q = (over = {}) => ({ country: { code: 'QA', name: 'Qatar' }, state: 'Doha', city: 'Doha', remoteOnly: false, title: 'Flutter Developer', keywords: [], filters: {}, ...over });

test('JSON-LD: finds JobPosting in plain, @graph and list forms, and ignores broken blocks', () => {
  const html = `${ld(posting())}<script type="application/ld+json">{ broken</script>${ld({ '@graph': [posting({ title: 'B' })] })}${ld({ '@type': 'ItemList', itemListElement: [{ item: posting({ title: 'C' }) }] })}${ld({ '@type': 'Organization' })}`;
  assert.deepEqual(extractJobPostings(html).map((p) => p.title), ['Flutter Developer', 'B', 'C']);
  assert.deepEqual(extractJobPostings('<html></html>'), []);
});

test('link discovery: same-site job-looking links only, capped, no files', () => {
  const html = '<a href="/jobs/1">1</a><a href="/jobs/1#x">dup</a><a href="/jobs/doc.pdf">pdf</a><a href="/about">about</a><a href="https://other.example/jobs/2">ext</a><a href="/careers/opening/7">7</a>';
  assert.deepEqual(discoverJobLinks(html, 'https://acme.example/careers', { limit: 10 }), ['https://acme.example/jobs/1', 'https://acme.example/careers/opening/7']);
  assert.deepEqual(discoverJobLinks(html, 'https://acme.example/careers', { limit: 1 }).length, 1);
  assert.deepEqual(discoverJobLinks('<a href="/p/9">x</a><a href="/jobs/1">y</a>', 'https://acme.example/careers', { pattern: '^/p/' }), ['https://acme.example/p/9']);
});

test('a page with structured data yields a fully normalized job', async () => {
  const a = adapter([{ company: 'Acme', url: `${origin}/single`, website: 'https://acme.example' }]);
  const r = await a.search(Q());
  assert.equal(r.jobs.length, 1);
  const j = r.jobs[0];
  assert.equal(j.source, 'career_page');
  assert.equal(j.sourceJobId, 'REQ-1001');
  assert.equal(j.companyName, 'Acme Corp');
  assert.equal(j.companyWebsite, 'https://acme.example');
  assert.deepEqual([j.countryCode, j.state, j.city], ['QA', 'Doha', 'Doha']);
  assert.deepEqual([j.salaryMin, j.salaryMax, j.salaryCurrency, j.salaryPeriod], [20000, 28000, 'QAR', 'month']);
  assert.equal(j.employmentType, 'full_time');
  assert.equal(j.postedAt.toISOString().slice(0, 10), '2026-11-03');
  assert.equal(j.deadlineAt.toISOString().slice(0, 10), '2026-12-31');
  assert.equal(j.experienceYearsMin, 3);
  assert.deepEqual(j.requiredSkills, ['Flutter', 'Dart']);
  assert.equal(j.applyUrlDirect, true, "the employer's own page is a direct application link");
});

test('a listing page without structured data is followed through its job links (same site only)', async () => {
  hits.length = 0;
  const a = adapter([{ company: 'Acme', url: `${origin}/careers` }]);
  const all = await a.search(Q({ title: 'Product Designer', state: null, city: null, remoteOnly: true }));
  assert.equal(all.jobs.length, 1);
  assert.equal(all.jobs[0].title, 'Product Designer');
  assert.equal(all.jobs[0].workArrangement, 'remote');
  assert.ok(hits.includes('/careers/jobs/1') && hits.includes('/careers/jobs/2'));
  assert.ok(!hits.includes('/about'), 'non-job links are not visited');
});

test('@graph pages work and a request is made once per page however many searches ask', async () => {
  hits.length = 0;
  const a = adapter([{ company: 'Acme', url: `${origin}/graph` }]);
  const a1 = await a.search(Q({ title: 'Data Analyst' }));
  await a.search(Q({ title: 'Flutter Developer' }));
  assert.equal(a1.jobs.length, 1);
  assert.equal(hits.filter((h) => h === '/graph').length, 1);
});

test('robots.txt is obeyed: a disallowed page is never fetched', async () => {
  hits.length = 0;
  const a = adapter([{ company: 'Acme', url: `${origin}/private/jobs`, render: 'never' }]);
  await assert.rejects(() => a.search(Q()), (e) => e instanceof SourceError && e.kind === 'disallowed');
  assert.ok(!hits.includes('/private/jobs'));
});

test('access denied and bot walls are reported as blocked — never worked around', async () => {
  for (const path of ['/forbidden', '/challenge']) {
    const a = adapter([{ company: 'Acme', url: `${origin}${path}`, render: 'never' }]);
    await assert.rejects(() => a.search(Q()), (e) => e.kind === 'blocked', path);
  }
});

test('a redirect to a private address is refused', async () => {
  const a = adapter([{ company: 'Acme', url: `${origin}/redirect-private`, render: 'never' }]);
  await assert.rejects(() => a.search(Q()), (e) => e.kind === 'disallowed');
});

test('a page with no openings is not an error', async () => {
  const a = adapter([{ company: 'Acme', url: `${origin}/empty`, render: 'never' }]);
  assert.deepEqual((await a.search(Q())).jobs, []);
});

test('one bad career page is a warning when others work', async () => {
  const a = adapter([{ company: 'Gone', url: `${origin}/gone`, render: 'never' }, { company: 'Acme', url: `${origin}/single`, render: 'never' }]);
  const r = await a.search(Q());
  assert.equal(r.jobs.length, 1);
  assert.equal(r.warnings.length, 1);
});

test('private or malformed career page URLs are ignored at configuration time', () => {
  const a = adapter([{ url: 'http://10.0.0.5/jobs' }, { url: 'not a url' }, { url: `${origin}/single` }]);
  assert.equal(a.boards().length, 1);
});

test('getJobDetails: a 404 is definitive; a page that loads without structured data is "unknown"; a bot wall is an error', async () => {
  const a = adapter([]);
  assert.deepEqual(await a.getJobDetails({ sourceUrl: `${origin}/gone` }), { found: false, job: null });
  assert.deepEqual(await a.getJobDetails({ sourceUrl: `${origin}/empty` }), { found: null, job: null });
  const open = await a.getJobDetails({ sourceUrl: `${origin}/single` });
  assert.equal(open.found, true);
  assert.equal(open.job.sourceJobId, 'REQ-1001');
  await assert.rejects(() => a.getJobDetails({ sourceUrl: `${origin}/forbidden` }), (e) => e.kind === 'blocked');
});

test('a JavaScript-rendered page falls back to the shared browser (real Chrome via Playwright)', async (t) => {
  const { chromium } = await import('playwright');
  const pool = createBrowserPool({ launch: () => chromium.launch({ headless: true, channel: 'chrome' }), idleCloseMs: 200 });
  try {
    const a = adapter([{ company: 'Acme', url: `${origin}/spa` }], { browser: pool });
    // Static HTML first: nothing there, so the browser is used.
    let r;
    try {
      r = await a.search(Q({ title: 'Rendered By Script' }));
    } catch (err) {
      if (err.kind === 'not_configured') return t.skip(`no browser available: ${err.message}`);
      throw err;
    }
    assert.equal(r.jobs.length, 1);
    assert.equal(r.jobs[0].sourceJobId, 'SPA1');

    // The same browser serves several pages; asking again reuses the cache, not a second browser.
    const b = adapter([{ company: 'Acme', url: `${origin}/spa`, render: 'always' }, { company: 'Acme2', url: `${origin}/single`, render: 'always' }], { browser: pool });
    const both = await Promise.all([b.search(Q({ title: 'Rendered By Script' })), b.search(Q({ title: 'Flutter Developer' }))]);
    assert.equal(both[0].jobs.length, 1);
    assert.equal(both[1].jobs.length, 1);
    assert.ok(pool.stats().running);
    assert.ok(pool.stats().active <= 2);
  } finally {
    await pool.close();
  }
});

test('the browser pool launches once for concurrent callers, relaunches after a crash, and closes when idle', async () => {
  let launches = 0;
  const fakeBrowser = () => {
    let connected = true;
    const listeners = {};
    return {
      isConnected: () => connected,
      on: (e, f) => (listeners[e] = f),
      crash: () => { connected = false; listeners.disconnected?.(); },
      close: async () => { connected = false; },
      newContext: async () => ({
        newPage: async () => ({
          setDefaultTimeout() {}, route: async () => {}, goto: async () => ({ status: () => 200 }),
          waitForLoadState: async () => {}, content: async () => '<html>ok</html>', url: () => 'https://x.test/',
        }),
        close: async () => {},
      }),
    };
  };
  let current;
  const pool = createBrowserPool({ launch: async () => { launches += 1; current = fakeBrowser(); return current; }, idleCloseMs: 30, maxPages: 2 });
  await Promise.all([pool.render('https://x.test/1'), pool.render('https://x.test/2'), pool.render('https://x.test/3')]);
  assert.equal(launches, 1, 'one shared browser');
  current.crash();
  await pool.render('https://x.test/4');
  assert.equal(launches, 2, 'relaunched after the crash');
  await new Promise((r) => setTimeout(r, 120));
  assert.equal(pool.stats().running, false, 'closed after the idle period');
  await assert.rejects(() => createBrowserPool({ enabled: false }).render('https://x.test/'), (e) => e.kind === 'not_configured');
});
