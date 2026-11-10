import { test } from 'node:test';
import assert from 'node:assert/strict';
import {
  companyKey, titleKey, locationKey, fingerprintOf, canonicalUrl, applyUrlKey, isAggregatorUrl,
  descriptionSignature, signatureSimilarity, locationsCompatible,
} from './normalize.js';
import { parseSalaryText, extractSkills, extractExperience, extractEducation, parseSections, classifySkills, detectWorkArrangement, detectEmploymentType, detectExperienceLevel, annualApprox } from './extract.js';
import { htmlToText, foldAccents, fold, dateOrNull, numberOrNull, textOrNull } from './text.js';
import { titleMatches, keywordsMatch, locationMatches, remoteOpenTo, cityKey } from './match.js';
import { csvCell, csvRow } from './csv.js';
import { TtlCache } from './ttlCache.js';
import { createHttpClient, parseRetryAfter, backoffDelay } from './http.js';
import { createSourceGate } from './sourceGate.js';
import { SourceError, scrub } from './errors.js';
import { createLogger } from './logger.js';

// ------------------------------------------------------------- normalization

test('company names compare without legal suffixes, punctuation or accents', () => {
  assert.equal(companyKey('Acme, Inc.'), 'acme');
  assert.equal(companyKey('ACME GmbH & Co. KG'), 'acme');
  assert.equal(companyKey('Müller AG'), 'muller');
  assert.equal(companyKey('Qatar Airways Group (Q.C.S.C.)'), companyKey('qatar airways group'));
  assert.equal(companyKey('Co'), 'co', 'a name that is only a suffix is kept');
  assert.notEqual(companyKey('Acme Labs'), companyKey('Acme'));
});

test('titles ignore gender markers and work-mode noise but keep seniority and meaning', () => {
  assert.equal(titleKey('Sr. Flutter Developer (m/f/d) - Remote'), 'senior flutter developer');
  assert.equal(titleKey('Flutter Developer'), 'flutter developer');
  assert.notEqual(titleKey('Senior Flutter Developer'), titleKey('Flutter Developer'));
  assert.equal(titleKey('Senior Engineer (Backend)'), 'senior engineer backend', 'a meaningful bracket is kept');
  assert.equal(titleKey('Software Engineer [Hybrid]'), 'software engineer');
  assert.equal(titleKey('Jr Dev'), 'junior developer');
});

test('the fingerprint is stable across spelling differences and differs by place', () => {
  const a = { companyName: 'Acme Inc.', title: 'Flutter Developer', countryCode: 'US', city: 'Los Angeles' };
  const b = { companyName: 'ACME', title: 'Flutter Developer (m/f/d)', countryCode: 'US', city: 'los angeles' };
  assert.equal(fingerprintOf(a), fingerprintOf(b));
  assert.notEqual(fingerprintOf(a), fingerprintOf({ ...a, city: 'Houston' }));
  assert.notEqual(fingerprintOf(a), fingerprintOf({ ...a, countryCode: 'CA' }));
  assert.equal(locationKey({ countryCode: 'DE', workArrangement: 'remote' }), 'de|remote');
  assert.equal(locationKey({}), 'xx|');
});

test('URLs: tracking noise and ordering do not change identity; aggregator links are not keys', () => {
  assert.equal(canonicalUrl('http://www.Example.com/jobs/1/?utm_source=x&b=2&a=1#frag'), 'https://example.com/jobs/1?a=1&b=2');
  assert.equal(canonicalUrl('https://example.com/jobs/1?gh_jid=77&utm_medium=y'), 'https://example.com/jobs/1?gh_jid=77', 'gh_jid identifies the posting and is kept');
  assert.equal(canonicalUrl('ftp://x.test/a'), null);
  assert.equal(canonicalUrl('not a url'), null);
  assert.equal(applyUrlKey('https://www.adzuna.com/land/ad/123'), null);
  assert.equal(applyUrlKey('https://jooble.org/desc/9'), null);
  assert.ok(applyUrlKey('https://boards.greenhouse.io/acme/jobs/55'));
  assert.equal(isAggregatorUrl('https://www.linkedin.com/jobs/view/1'), true);
  assert.equal(isAggregatorUrl('https://acme.com/careers/1'), false);
});

test('description similarity: the same text matches, different text does not, short text is not compared', () => {
  const base = Array.from({ length: 30 }, (_, i) => `We are looking for an engineer to design reliable systems number ${i} across our platform.`).join(' ');
  const edited = base.replace('number 3 ', 'number three ').replace('platform.', 'platform and tools.');
  const other = Array.from({ length: 30 }, (_, i) => `Seasonal warehouse staff needed for packing orders and loading trucks shift ${i} weekends.`).join(' ');
  const [s1, s2, s3] = [base, edited, other].map(descriptionSignature);
  assert.ok(signatureSimilarity(s1, s1) === 1);
  assert.ok(signatureSimilarity(s1, s2) > 0.8, `edited copy ${signatureSimilarity(s1, s2)}`);
  assert.ok(signatureSimilarity(s1, s3) < 0.2);
  assert.equal(descriptionSignature('too short to compare'), null);
  assert.equal(signatureSimilarity(null, s1), 0);
});

test('location compatibility: unknown is compatible, known-and-different is not', () => {
  assert.equal(locationsCompatible({ countryCode: 'US', city: 'Austin' }, { countryCode: 'US', city: 'austin' }), true);
  assert.equal(locationsCompatible({ countryCode: 'US', city: 'Austin' }, { countryCode: 'US', city: 'Dallas' }), false);
  assert.equal(locationsCompatible({ countryCode: 'US', city: 'Austin' }, { countryCode: 'US', state: 'Texas' }), true);
  assert.equal(locationsCompatible({ countryCode: 'US' }, { countryCode: 'CA' }), false);
  assert.equal(locationsCompatible({ countryCode: 'US', workArrangement: 'remote' }, { countryCode: 'US', workArrangement: 'onsite', city: 'Austin' }), false);
  assert.equal(locationsCompatible({ state: 'Texas' }, { state: 'Ohio' }), false);
});

// ---------------------------------------------------------------- extraction

test('pay text: ranges, currencies, periods, k-suffix, German formatting; nothing from vague text', () => {
  const p = parseSalaryText;
  assert.deepEqual(p('$80,000 - $100,000 per year'), { min: 80000, max: 100000, currency: 'USD', period: 'year' });
  assert.deepEqual(p('£45k–55k'), { min: 45000, max: 55000, currency: 'GBP', period: null });
  assert.deepEqual(p('AED 10,000 - 15,000 monthly'), { min: 10000, max: 15000, currency: 'AED', period: 'month' });
  assert.deepEqual(p('€55.000 - €70.000 pro Jahr'), { min: 55000, max: 70000, currency: 'EUR', period: 'year' });
  assert.deepEqual(p('$35/hr'), { min: 35, max: 35, currency: 'USD', period: 'hour' });
  for (const vague of ['Competitive', 'DOE', '3 years', '', null, 'negotiable']) assert.deepEqual(p(vague), { min: null, max: null, currency: null, period: null }, String(vague));
  assert.equal(annualApprox(5000, 'month'), 60000);
  assert.equal(annualApprox(5000, null), null);
});

test('skills: word-boundary matches, no Java inside JavaScript, no Go inside Google', () => {
  assert.deepEqual(extractSkills('We use JavaScript and Node.js'), ['JavaScript', 'Node.js']);
  assert.deepEqual(extractSkills('Java and Go and C++ and C#'), ['Java', 'C++', 'C#', 'Go']);
  assert.deepEqual(extractSkills('Google Cloud and Googling'), ['Google Cloud'], 'Go is not found inside Google');
  assert.deepEqual(extractSkills('We write golang services'), ['Go']);
  assert.deepEqual(extractSkills('Experience with Flutter/Dart and REST APIs'), ['Flutter', 'Dart', 'REST APIs']);
  assert.deepEqual(extractSkills(''), []);
});

test('required vs preferred skills follow the posting sections; unstructured postings list mentions', () => {
  const text = 'About us\nWe use Docker everywhere.\nRequirements\n- Flutter and Dart\n- Firebase\nNice to have\n- Kotlin\n- Flutter widgets';
  const c = classifySkills(text);
  assert.deepEqual(c.requiredSkills, ['Flutter', 'Dart', 'Firebase']);
  assert.deepEqual(c.preferredSkills, ['Kotlin']);
  assert.equal(c.skillsBasis, 'sections');
  const loose = classifySkills('We build with Flutter and Firebase.');
  assert.deepEqual(loose.requiredSkills, ['Flutter', 'Firebase']);
  assert.equal(loose.skillsBasis, 'mentions');
  assert.deepEqual(classifySkills('Great culture.', ['Remote Work']).requiredSkills, ['Remote Work'], 'source tags are kept');
  assert.equal(classifySkills('Great culture.').skillsBasis, null);
});

test('experience, education, level, arrangement and employment type', () => {
  assert.equal(extractExperience('Minimum 3+ years of experience in sales.').years, 3);
  assert.equal(extractExperience('2-4 years’ professional experience').years, 2);
  assert.equal(extractExperience('Friendly team').years, null);
  assert.match(extractEducation('Intro\n- Bachelor degree in CS or equivalent\n- Other'), /Bachelor/);
  assert.equal(extractEducation('Nothing here'), null);
  assert.equal(detectExperienceLevel('Senior Flutter Developer'), 'senior');
  assert.equal(detectExperienceLevel('Junior Designer'), 'entry');
  assert.equal(detectExperienceLevel('Head of Engineering'), 'executive');
  assert.equal(detectExperienceLevel('Flutter Developer'), null, 'no level is guessed');
  assert.equal(detectWorkArrangement('Remote - US'), 'remote');
  assert.equal(detectWorkArrangement('Hybrid (3 days)'), 'hybrid');
  assert.equal(detectWorkArrangement('On-site in Doha'), 'onsite');
  assert.equal(detectWorkArrangement('Doha, Qatar'), null);
  assert.equal(detectEmploymentType('Full-time'), 'full_time');
  assert.equal(detectEmploymentType('Praktikum'), 'internship');
  assert.equal(detectEmploymentType(''), null);
});

test('sections are found by heading, including German ones; bullet text is cleaned', () => {
  const s = parseSections('Deine Aufgaben:\n- Apps bauen\n- Reviews\nDein Profil\n- Flutter\nWir bieten\n- Obst');
  assert.deepEqual(s.responsibilities, ['Apps bauen', 'Reviews']);
  assert.deepEqual(s.required, ['Flutter']);
  assert.equal(parseSections('Just a paragraph of text.').hasStructure, false);
});

// ---------------------------------------------------------------------- text

test('html to text keeps structure, drops scripts, decodes doubly-escaped content', () => {
  assert.equal(htmlToText('<p>Hello</p><ul><li>One</li><li>Two</li></ul><script>evil()</script>'), 'Hello\n- One\n- Two');
  assert.equal(htmlToText('&lt;p&gt;A &amp;amp; B&lt;/p&gt;'), 'A & B');
  assert.equal(htmlToText(''), '');
  assert.equal(foldAccents('Zürich Straße São'), 'Zurich Strasse Sao');
  assert.equal(fold('C++ / Node.js & Ünï'), 'c++ node.js and uni');
});

test('value coercion: missing is null, never a made-up default', () => {
  assert.equal(textOrNull('  '), null);
  assert.equal(textOrNull(undefined), null);
  assert.equal(numberOrNull(''), null);
  assert.equal(numberOrNull('1,200'), 1200);
  assert.equal(dateOrNull('garbage'), null);
  assert.equal(dateOrNull(0), null, 'epoch zero is not a posting date');
  assert.equal(dateOrNull('2999-01-01'), null, 'far future is not a posting date');
  assert.equal(dateOrNull(1786469891368)?.getUTCFullYear(), 2026, 'epoch milliseconds');
  assert.equal(dateOrNull('2026-11-03')?.toISOString().slice(0, 10), '2026-11-03');
});

// ------------------------------------------------------------------ matching

test('title matching: all searched words, developer ~ engineer, seniority only when searched', () => {
  assert.equal(titleMatches('Flutter Developer', 'Senior Flutter Engineer'), true);
  assert.equal(titleMatches('Flutter Developer', 'Flutter Developer (m/f/d)'), true);
  assert.equal(titleMatches('Senior Flutter Developer', 'Flutter Developer'), false);
  assert.equal(titleMatches('Flutter Developer', 'Dart Developer'), false);
  assert.equal(titleMatches('Product Manager', 'Product Marketing Manager'), true, 'all words present');
  assert.equal(titleMatches('Data Analyst', 'Sr. Data Analyst'), true);
  assert.equal(titleMatches('', 'Anything'), true);
  assert.equal(keywordsMatch(['dart', 'firebase'], 'Flutter, Dart and Firebase'), true);
  assert.equal(keywordsMatch(['dart', 'swift'], 'Flutter, Dart and Firebase'), false);
  assert.equal(keywordsMatch([], 'x'), true);
});

test('city keys treat "New York City" and "New York", "St. Louis" and "Saint Louis" alike', () => {
  assert.equal(cityKey('New York City'), cityKey('New York'));
  assert.equal(cityKey('St. Louis'), cityKey('Saint Louis'));
  assert.notEqual(cityKey('York'), cityKey('New York'));
});

test('location matching across city, state, country and remote searches', () => {
  const US = { code: 'US', name: 'United States' };
  const job = (locationText, extra = {}) => ({ locationText, ...extra });
  assert.equal(locationMatches(job('San Francisco, CA'), { country: US, state: 'California', city: 'San Francisco' }), true);
  assert.equal(locationMatches(job('San Francisco, CA'), { country: US, state: 'California', city: 'Los Angeles' }), false);
  assert.equal(locationMatches(job('New York, NY'), { country: US, state: 'New York', city: 'New York City' }), true);
  assert.equal(locationMatches(job('Washington, D.C.'), { country: US, state: 'Washington', city: 'Washington' }), false, 'DC is not Washington state');
  assert.equal(locationMatches(job('Austin, TX'), { country: US, state: 'California' }), false);
  assert.equal(locationMatches(job('Austin, TX'), { country: US, state: 'Texas' }), true);
  assert.equal(locationMatches(job('Austin, TX'), { country: US }), true);
  assert.equal(locationMatches(job('Toronto, ON'), { country: US }), false);
  assert.equal(locationMatches(job('Toronto, ON'), { country: { code: 'CA', name: 'Canada' } }), true);
  // remote
  const remote = (loc) => job(loc, { workArrangement: 'remote' });
  assert.equal(locationMatches(remote('Remote'), { country: US, remoteOnly: true }), true);
  assert.equal(locationMatches(remote('Remote - US'), { country: US, remoteOnly: true }), true);
  assert.equal(locationMatches(remote('Remote - Germany'), { country: US, remoteOnly: true }), false);
  assert.equal(locationMatches(remote('Worldwide'), { country: US, remoteOnly: true }), true);
  assert.equal(locationMatches(job('Austin, TX', { workArrangement: 'onsite' }), { country: US, remoteOnly: true }), false);
  assert.equal(locationMatches(remote('Remote - Germany'), { country: { code: 'WW', name: 'Worldwide / Remote' }, remoteOnly: true }), true);
  assert.equal(remoteOpenTo({ locationText: 'Anywhere' }, 'DE'), true);
});

// ----------------------------------------------------------------------- csv

test('csv: escapes quotes/newlines/commas and neutralises spreadsheet formulas', () => {
  assert.equal(csvCell('plain'), 'plain');
  assert.equal(csvCell('a,b'), '"a,b"');
  assert.equal(csvCell('say "hi"'), '"say ""hi"""');
  assert.equal(csvCell('line1\nline2'), '"line1\nline2"');
  assert.equal(csvCell('=HYPERLINK("http://evil")'), '"\'=HYPERLINK(""http://evil"")"');
  assert.equal(csvCell('+1 555'), "'+1 555");
  assert.equal(csvCell(null), '');
  assert.equal(csvCell(['Flutter', 'Dart']), 'Flutter; Dart');
  assert.equal(csvCell(new Date('2026-11-07T10:00:00Z')), '2026-11-07T10:00:00.000Z');
  assert.equal(csvRow(['a', 'b,c', null]), 'a,"b,c",');
});

// ---------------------------------------------------------------------- cache

test('ttl cache: expiry, and concurrent loads share one request; failures are not cached', async () => {
  let now = 0;
  const cache = new TtlCache({ now: () => now });
  let loads = 0;
  const load = async () => {
    loads += 1;
    await new Promise((r) => setTimeout(r, 5));
    return 'v';
  };
  assert.deepEqual(await Promise.all([cache.getOrLoad('k', load, 100), cache.getOrLoad('k', load, 100)]), ['v', 'v']);
  assert.equal(loads, 1);
  now = 99;
  await cache.getOrLoad('k', load, 100);
  assert.equal(loads, 1);
  now = 101;
  await cache.getOrLoad('k', load, 100);
  assert.equal(loads, 2);
  await assert.rejects(() => cache.getOrLoad('bad', async () => { throw new Error('x'); }, 100));
  assert.equal(cache.get('bad'), undefined);
});

// ----------------------------------------------------------------- http client

const res = (status, body = '{}', headers = {}) => ({ status, headers: new Headers(headers), text: async () => body, body: { cancel: async () => {} } });

test('http: retries 5xx/429/network with backoff, honours Retry-After, never retries other 4xx', async () => {
  const sleeps = [];
  const script = [res(503), res(429, '{}', { 'retry-after': '2' }), res(200, '{"ok":true}')];
  let calls = 0;
  const client = createHttpClient({ fetchImpl: async () => script[calls++], sleep: async (ms) => sleeps.push(ms), random: () => 0.5, baseDelayMs: 100, maxAttempts: 3 });
  assert.deepEqual(await client.getJson('https://x.test/a'), { ok: true });
  assert.equal(calls, 3);
  assert.equal(sleeps[0], 75, 'exponential backoff with jitter: 100 * (0.5 + 0.5*0.5)');
  assert.equal(sleeps[1], 2000, 'Retry-After wins when longer');

  for (const [status, kind] of [[400, 'http_error'], [401, 'auth'], [403, 'auth'], [404, 'not_found']]) {
    let n = 0;
    const c = createHttpClient({ fetchImpl: async () => (n++, res(status)), sleep: async () => {} });
    await assert.rejects(() => c.getJson('https://x.test/'), (e) => e.kind === kind && e.status === status);
    assert.equal(n, 1, `${status} is final`);
  }
});

test('http: timeouts and network errors are retried then reported; a long Retry-After is not waited out', async () => {
  let n = 0;
  const c = createHttpClient({ fetchImpl: async () => { n++; throw Object.assign(new Error('boom'), { name: 'TimeoutError' }); }, sleep: async () => {}, maxAttempts: 3 });
  await assert.rejects(() => c.getJson('https://x.test/'), (e) => e.kind === 'timeout');
  assert.equal(n, 3);

  let m = 0;
  const limited = createHttpClient({ fetchImpl: async () => (m++, res(429, '', { 'retry-after': '3600' })), sleep: async () => { throw new Error('should not sleep'); } });
  await assert.rejects(() => limited.getJson('https://x.test/'), (e) => e.kind === 'rate_limited' && e.retryAfterMs === 3_600_000);
  assert.equal(m, 1);
});

test('http: invalid JSON and oversized bodies are parse errors; query values are dropped when empty', async () => {
  const bad = createHttpClient({ fetchImpl: async () => res(200, 'not json') });
  await assert.rejects(() => bad.getJson('https://x.test/'), (e) => e.kind === 'parse');
  const big = createHttpClient({ fetchImpl: async () => res(200, 'x'.repeat(100)), maxBodyBytes: 10 });
  await assert.rejects(() => big.getText('https://x.test/'), (e) => e.kind === 'parse');
  let seen;
  const q = createHttpClient({ fetchImpl: async (url) => { seen = url; return res(200); } });
  await q.getJson('https://x.test/s', { query: { what: 'dart', where: '', page: 2, none: undefined } });
  assert.equal(seen, 'https://x.test/s?what=dart&page=2');
  assert.equal(parseRetryAfter('120'), 120000);
  assert.ok(parseRetryAfter(new Date(Date.now() + 5000).toUTCString()) <= 5000);
  assert.equal(parseRetryAfter('soon'), null);
  assert.ok(backoffDelay(10, { baseDelayMs: 100, maxDelayMs: 1000, random: () => 1 }) <= 1000);
});

test('secrets are scrubbed from errors and logs', () => {
  assert.equal(scrub('GET https://api.x.test/s?app_id=1&app_key=SECRET123&what=dart'), 'GET https://api.x.test/s?app_id=***&app_key=***&what=dart');
  assert.match(scrub('POST https://jooble.org/api/abcdef0123456789abcdef'), /api\/\*\*\*/);
  const lines = [];
  const log = createLogger('t', { sink: { log: (l) => lines.push(l), warn: (l) => lines.push(l), error: (l) => lines.push(l) }, level: 'debug' });
  log.info('called', { url: 'https://x.test/?api_key=TOPSECRET', apiKey: 'TOPSECRET', nested: { token: 'TOPSECRET', ok: 1 } });
  assert.ok(!lines[0].includes('TOPSECRET'));
  const parsed = JSON.parse(lines[0]);
  assert.equal(parsed.scope, 'jobs.t');
  assert.equal(parsed.nested.ok, 1);
});

// ----------------------------------------------------------------------- gate

test('source gate: spaces requests, caps concurrency, and enforces the daily budget with rollover', async () => {
  let clock = Date.parse('2026-11-07T10:00:00Z');
  const sleeps = [];
  const g = createSourceGate({ id: 's', perMinute: 60, perDay: 3, maxConcurrent: 1, jitter: 0, now: () => clock, sleep: async (ms) => { sleeps.push(ms); clock += ms; } });
  await g.run(async () => 1);
  await g.run(async () => 2);
  assert.deepEqual(sleeps, [1000], 'one second between requests at 60/min');
  await g.run(async () => 3);
  await assert.rejects(() => g.run(async () => 4), (e) => e instanceof SourceError && e.kind === 'quota');
  assert.equal(g.usage().remaining, 0);
  clock += 24 * 3_600_000;
  assert.equal(await g.run(async () => 'next day'), 'next day');
  assert.equal(g.usage().requests, 1);

  let running = 0;
  let peak = 0;
  const g2 = createSourceGate({ id: 'c', perMinute: 600000, maxConcurrent: 2, jitter: 0, sleep: async () => {} });
  await Promise.all(Array.from({ length: 8 }, () => g2.run(async () => { running++; peak = Math.max(peak, running); await new Promise((r) => setTimeout(r, 5)); running--; })));
  assert.equal(peak, 2);
});

test('source gate reports usage so it can be persisted, and restores today\'s count', async () => {
  const seen = [];
  const today = new Date().toISOString().slice(0, 10);
  const g = createSourceGate({ id: 's', perMinute: 600000, perDay: 10, initialUsage: { date: today, requests: 7 }, onUsage: (u) => seen.push(u.requests), sleep: async () => {} });
  await g.run(async () => {});
  assert.deepEqual(seen, [8]);
  const stale = createSourceGate({ id: 's', perDay: 10, initialUsage: { date: '2020-01-01', requests: 9 } });
  assert.equal(stale.usage().requests, 0, "yesterday's count does not carry over");
});
