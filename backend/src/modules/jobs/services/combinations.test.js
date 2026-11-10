import { test } from 'node:test';
import assert from 'node:assert/strict';
import { iterateCombinations, countCombinations, uniqueTitles, describeCombination } from './combinations.js';
import { validateSearch } from '../validators/search.js';
import { geoCatalog } from '../geo/geoCatalog.js';

const list = (search) => [...iterateCombinations(search, geoCatalog)];

test('the example from the brief: state × city × title, in a stable order', () => {
  const search = {
    countries: [{ code: 'US', level: 'city', regions: ['California', 'Texas'], cities: [
      { state: 'California', city: 'Los Angeles' }, { state: 'California', city: 'San Francisco' }, { state: 'Texas', city: 'Houston' },
    ] }],
    titles: ['Flutter Developer', 'Senior Flutter Developer'],
  };
  assert.deepEqual(list(search).map((c) => `${c.state} × ${c.city} × ${c.title}`), [
    'California × Los Angeles × Flutter Developer',
    'California × Los Angeles × Senior Flutter Developer',
    'California × San Francisco × Flutter Developer',
    'California × San Francisco × Senior Flutter Developer',
    'Texas × Houston × Flutter Developer',
    'Texas × Houston × Senior Flutter Developer',
  ]);
});

test('"all states" and "all cities" expand from the dataset; the count matches the expansion', () => {
  const allCitiesInTexas = { countries: [{ code: 'US', level: 'city', regions: ['Texas'], cities: 'all' }], titles: ['A'] };
  const items = list(allCitiesInTexas);
  assert.equal(items.length, countCombinations(allCitiesInTexas, geoCatalog).combinations);
  assert.ok(items.length > 100);
  assert.ok(items.every((c) => c.state === 'Texas' && c.city));
  assert.equal(items[0].city, 'Houston', 'largest city first');

  const allStates = { countries: [{ code: 'US', level: 'state', regions: 'all' }], titles: ['A', 'B'] };
  assert.equal(list(allStates).length, 102);
  assert.deepEqual(countCombinations(allStates, geoCatalog), { locations: 51, titles: 2, combinations: 102 });

  const whole = { countries: [{ code: 'US', level: 'city', regions: 'all', cities: 'all' }], titles: ['A'] };
  assert.equal(countCombinations(whole, geoCatalog).combinations, 7515, 'counted without expanding');
});

test('country level, remote and worldwide', () => {
  const s = { countries: [{ code: 'QA', level: 'country', includeRemote: true }, { code: 'WW' }], titles: ['Flutter Developer'] };
  const items = list(s);
  assert.deepEqual(items.map((c) => [c.countryCode, c.remoteOnly, c.state, c.city]), [
    ['QA', false, null, null],
    ['QA', true, null, null],
    ['WW', true, null, null],
  ]);
  assert.equal(countCombinations(s, geoCatalog).combinations, 3);
  assert.equal(describeCombination(items[2]), 'Worldwide (remote) · Flutter Developer');
  assert.equal(describeCombination({ country: 'United States', state: 'Texas', city: 'Austin', title: 'X' }), 'United States › Texas › Austin · X');
  assert.equal(describeCombination({ country: 'Qatar', state: 'Doha', city: 'Doha', title: 'X' }), 'Qatar › Doha · X', 'repeated names are shown once');
});

test('keys are unique per combination and identical across expansions (so a resumed run lines up)', () => {
  const s = { countries: [{ code: 'US', level: 'city', regions: ['Ohio'], cities: 'all' }], titles: ['A', 'B'] };
  const first = list(s).map((c) => c.key);
  assert.equal(new Set(first).size, first.length);
  assert.deepEqual(list(s).map((c) => c.key), first);
});

test('titles are de-duplicated ignoring case, spacing and gender suffixes', () => {
  assert.deepEqual(uniqueTitles(['Flutter Developer', ' flutter  developer ', 'Flutter Developer (m/f/d)', 'Senior Flutter Developer', '']), ['Flutter Developer', 'Senior Flutter Developer']);
});

test('validation resolves selections against the dataset', () => {
  const ok = validateSearch({
    name: 'My search',
    countries: [{ code: 'us', level: 'city', regions: ['california', 'TX'], cities: [{ state: 'california', city: 'los angeles' }] }, { code: 'WW' }],
    titles: ['Flutter Developer'],
  }, { catalog: geoCatalog, sourceIds: ['adzuna'] });
  assert.deepEqual(ok.countries[0].regions, ['California', 'Texas'], 'names and codes normalise');
  assert.deepEqual(ok.countries[0].cities, [{ state: 'California', city: 'Los Angeles' }]);
  assert.equal(ok.countries[1].includeRemote, true);
  assert.equal(ok.limits.maxCombinations, 20000);
  assert.equal(ok.schedule.enabled, false);

  const bad = (over) => assert.throws(() => validateSearch({ name: 'x1', countries: [{ code: 'US' }], titles: ['A'], ...over }, { catalog: geoCatalog, sourceIds: ['adzuna'] }), (e) => e.status === 422);
  bad({ countries: [{ code: 'US', level: 'city', regions: ['Ohio'], cities: [{ state: 'Texas', city: 'Austin' }] }] });
  bad({ countries: [{ code: 'US', level: 'city', cities: [{ state: 'Texas', city: 'Atlantis' }] }] });
  bad({ countries: [{ code: 'US' }, { code: 'US' }] });
  bad({ sources: ['nope'] });
  bad({ filters: { salaryMin: 5, salaryMax: 1 } });
  bad({ filters: { workArrangement: 'moon' } });
  bad({ schedule: { timeOfDay: '25:99' } });
  bad({ titles: [] });
});
