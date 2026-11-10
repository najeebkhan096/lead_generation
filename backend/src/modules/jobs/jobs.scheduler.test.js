import { test } from 'node:test';
import assert from 'node:assert/strict';
import { isDue, localParts, createJobsScheduler } from './jobs.scheduler.js';
import { makeHarness, FakeAdapter, sampleJob, LA_SF_SEARCH } from './testing/engineHarness.js';
import { createMatcher, profileFromCv } from './matching/matcher.js';

const at = (iso) => new Date(iso);

test('local time in the search\'s own time zone decides the day and the minute', () => {
  assert.deepEqual(localParts(at('2026-11-07T22:30:00Z'), 'Asia/Qatar'), { date: '2026-11-08', minutes: 1 * 60 + 30 }, 'Qatar is UTC+3: already tomorrow');
  assert.deepEqual(localParts(at('2026-11-07T22:30:00Z'), 'America/Los_Angeles'), { date: '2026-11-07', minutes: 14 * 60 + 30 });
  assert.deepEqual(localParts(at('2026-11-07T00:05:00Z'), 'UTC'), { date: '2026-11-07', minutes: 5 });
});

test('a schedule is due once per local day, after its time, including a late catch-up', () => {
  const s = (over = {}) => ({ enabled: true, timeOfDay: '03:00', timezone: 'UTC', lastRunDate: null, ...over });
  assert.equal(isDue(s(), at('2026-11-07T02:59:00Z')), false, 'before the time');
  assert.equal(isDue(s(), at('2026-11-07T03:00:00Z')), true, 'at the time');
  assert.equal(isDue(s(), at('2026-11-07T15:00:00Z')), true, 'the server was down at 03:00: catch up');
  assert.equal(isDue(s({ lastRunDate: '2026-11-07' }), at('2026-11-07T15:00:00Z')), false, 'already ran today');
  assert.equal(isDue(s({ lastRunDate: '2026-11-06' }), at('2026-11-07T03:01:00Z')), true, 'a new day');
  assert.equal(isDue(s({ enabled: false }), at('2026-11-07T15:00:00Z')), false);
  assert.equal(isDue(s({ timezone: 'Asia/Qatar', timeOfDay: '06:00' }), at('2026-11-07T02:59:00Z')), false, '05:59 in Qatar');
  assert.equal(isDue(s({ timezone: 'Asia/Qatar', timeOfDay: '06:00' }), at('2026-11-07T03:00:00Z')), true, '06:00 in Qatar');
  assert.equal(isDue(s({ timezone: 'Not/AZone' }), at('2026-11-07T15:00:00Z')), false, 'a bad zone never crashes the tick');
  assert.equal(isDue(null, new Date()), false);
});

test('the scheduler starts due scans once, marks the day, and survives a failing search', async () => {
  let clock = at('2026-11-07T03:30:00Z');
  const src = new FakeAdapter('alpha', async (q) => [sampleJob({ sourceJobId: `${q.city}-${q.title}`, title: q.title, locationText: `${q.city}, CA` })]);
  const h = makeHarness({ adapters: [src], now: () => clock });
  const due = await h.searchStore.create({ ...LA_SF_SEARCH, name: 'due', schedule: { enabled: true, timeOfDay: '03:00', timezone: 'UTC', lastRunDate: null } });
  const notYet = await h.searchStore.create({ ...LA_SF_SEARCH, name: 'later', schedule: { enabled: true, timeOfDay: '23:00', timezone: 'UTC', lastRunDate: null } });
  const broken = await h.searchStore.create({ ...LA_SF_SEARCH, name: 'broken', limits: { ...LA_SF_SEARCH.limits, maxCombinations: 1 }, schedule: { enabled: true, timeOfDay: '01:00', timezone: 'UTC', lastRunDate: null } });
  const manual = await h.searchStore.create({ ...LA_SF_SEARCH, name: 'manual only' });

  const logs = [];
  const log = { info: () => {}, warn: () => {}, error: (m) => logs.push(m), debug: () => {}, child() { return this; } };
  const scheduler = createJobsScheduler({ searchStore: h.searchStore, engine: h.engine, log, now: () => clock });

  const started = await scheduler.tick();
  assert.equal(started.length, 1);
  await h.engine.idle();
  const runs = h.db.dump('job_scan_runs');
  assert.equal(runs.length, 1);
  assert.equal(runs[0][1].searchId, due.id);
  assert.equal(runs[0][1].trigger, 'scheduled');
  assert.equal((await h.searchStore.getApi(due.id)).schedule.lastRunDate, '2026-11-07');
  assert.equal((await h.searchStore.getApi(notYet.id)).schedule.lastRunDate, null);
  assert.equal((await h.searchStore.getApi(broken.id)).schedule.lastRunDate, '2026-11-07', 'a configuration error is not retried every minute');
  assert.ok(logs.includes('scheduled scan could not start'));
  assert.equal((await h.searchStore.getApi(manual.id)).lastRunId, null);

  assert.deepEqual(await scheduler.tick(), [], 'the same day does not start it again');
  clock = at('2026-11-08T03:05:00Z');
  assert.equal((await scheduler.tick()).length, 1, 'the next day does');
  await h.engine.idle();
});

test('a scheduled scan waits while the same search is already being scanned', async () => {
  const clock = at('2026-11-07T04:00:00Z');
  let release;
  const gate = new Promise((r) => (release = r));
  const src = new FakeAdapter('alpha', async (q) => {
    await gate;
    return [sampleJob({ sourceJobId: `${q.city}-${q.title}`, title: q.title })];
  });
  const h = makeHarness({ adapters: [src], now: () => clock });
  const s = await h.searchStore.create({ ...LA_SF_SEARCH, schedule: { enabled: true, timeOfDay: '03:00', timezone: 'UTC', lastRunDate: null } });
  await h.engine.start(s.id); // a manual scan is running
  const scheduler = createJobsScheduler({ searchStore: h.searchStore, engine: h.engine, now: () => clock });
  assert.deepEqual(await scheduler.tick(), []);
  assert.equal((await h.searchStore.getApi(s.id)).schedule.lastRunDate, null, 'not marked: it will run once the manual scan is done');
  release();
  await h.engine.idle();
  assert.equal((await scheduler.tick()).length, 1);
  await h.engine.idle();
});

// ------------------------------------------------------------------- matching

test('CV profile: skills named and the longest stated experience', () => {
  const p = profileFromCv('Mobile engineer. 6 years of experience building Flutter and Dart apps; 2 years with Firebase.');
  assert.deepEqual(p.skills, ['Flutter', 'Dart', 'Firebase']);
  assert.equal(p.years, 6);
  assert.deepEqual(profileFromCv('hello'), { skills: [], years: null });
});

test('the keyword matcher scores overlap, flags gaps and experience, and suggests CV changes', async () => {
  const matcher = createMatcher();
  const job = { requiredSkills: ['Flutter', 'Dart', 'Firebase', 'GraphQL'], preferredSkills: ['Kotlin'], experienceYearsMin: 5, description: 'Requirements\n- Flutter and Dart\n- GraphQL APIs\nNice to have\n- Kotlin' };
  const strong = await matcher.match('7 years of experience: Flutter, Dart, Firebase, GraphQL, Kotlin', job);
  assert.equal(strong.provider, 'keyword');
  assert.ok(strong.score >= 95, `${strong.score}`);
  assert.deepEqual(strong.missingSkills, []);
  assert.equal(strong.experience.compatible, true);

  const weak = await matcher.match('2 years of experience with Flutter only', job);
  assert.ok(weak.score < 40, `${weak.score}`);
  assert.deepEqual(weak.matchingSkills, ['Flutter']);
  assert.deepEqual(weak.missingSkills, ['Dart', 'Firebase', 'GraphQL']);
  assert.equal(weak.experience.compatible, false);
  assert.ok(weak.suggestions.some((s) => /Dart/.test(s)) && weak.suggestions.some((s) => /5\+ years/.test(s)));
  assert.ok(weak.relevantRequirements.some((r) => /Flutter/.test(r)));

  const unknown = await matcher.match('A person.', { requiredSkills: [], description: '' });
  assert.equal(unknown.score, 0);
  assert.equal((await matcher.match('x', {}, {})).experience.compatible, null, 'unknown experience is unknown, not a pass or fail');
});

test('matching rejects empty or oversized CVs and unknown providers; a provider can be plugged in', async () => {
  const matcher = createMatcher();
  await assert.rejects(() => matcher.match('  ', {}), (e) => e.status === 422);
  await assert.rejects(() => matcher.match('x'.repeat(60_001), {}), (e) => e.status === 422);
  await assert.rejects(() => matcher.match('cv', {}, { provider: 'gpt' }), /Unknown match provider/);
  let called = 0;
  const custom = createMatcher({ providers: [{ id: 'future-ai', async match() { called++; return { score: 42, matchingSkills: [], missingSkills: [], experience: {}, relevantRequirements: [], suggestions: [] }; } }], defaultProvider: 'future-ai' });
  assert.equal((await custom.match('cv', {})).score, 42);
  assert.equal(called, 1);
});
