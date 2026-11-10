/** Geography, source configuration and saved searches. */

import { validateSearch } from '../validators/search.js';
import { parseSourceUpdate } from '../validators/jobs.js';
import { countCombinations } from '../services/combinations.js';
import { notFound, conflict } from '../utils/errors.js';
import { q } from '../validators/validate.js';

export function createSearchController({ catalog, searchStore, runStore, registry, sourceStore }) {
  const validate = (body) => validateSearch(body, { catalog, sourceIds: registry.ids() });
  const cacheable = (res) => res.setHeader('Cache-Control', 'public, max-age=3600');

  return {
    // ------------------------------------------------------------------ geo
    countries(_req, res) {
      cacheable(res);
      res.json({ countries: catalog.listCountries() });
    },

    regions(req, res) {
      const country = catalog.getCountry(req.params.code);
      if (!country) throw notFound('Unknown country');
      cacheable(res);
      res.json({ country: { code: country.code, name: country.name, adminLabel: country.adminLabel, remoteOnly: Boolean(country.remoteOnly) }, regions: catalog.listRegions(country.code) });
    },

    cities(req, res) {
      const result = catalog.listCities(req.params.code, req.params.region, { q: q.str(req.query, 'q'), limit: Math.min(q.int(req.query, 'limit') ?? 500, 2000), offset: q.int(req.query, 'offset') ?? 0 });
      if (!result) throw notFound('Unknown country or region');
      cacheable(res);
      res.json(result);
    },

    // -------------------------------------------------------------- sources
    async sources(_req, res) {
      await registry.load();
      res.json({ sources: registry.describeAll() });
    },

    async updateSource(req, res) {
      if (!registry.has(req.params.id)) throw notFound('Unknown source');
      const patch = parseSourceUpdate(req.body);
      await sourceStore.update(req.params.id, patch);
      await registry.load();
      res.json({ source: registry.describeAll().find((s) => s.id === req.params.id) });
    },

    // ------------------------------------------------------------- searches
    async list(req, res) {
      res.json(await searchStore.list({ limit: q.int(req.query, 'limit'), cursor: q.str(req.query, 'cursor') }));
    },

    async create(req, res) {
      res.status(201).json({ search: await searchStore.create(validate(req.body)) });
    },

    async get(req, res) {
      res.json({ search: await searchStore.getApi(req.params.id) });
    },

    async update(req, res) {
      res.json({ search: await searchStore.update(req.params.id, validate(req.body)) });
    },

    async remove(req, res) {
      await searchStore.get(req.params.id); // 404 first
      if (await runStore.findActiveForSearch(req.params.id)) throw conflict('Stop the active scan before deleting this search', 'SCAN_ALREADY_ACTIVE');
      await searchStore.remove(req.params.id);
      res.json({ deleted: true, id: req.params.id });
    },

    /** How many searches a draft expands to — shown before anyone starts a scan. */
    async estimate(req, res) {
      const draft = validate({ name: 'draft', ...req.body });
      const total = countCombinations(draft, catalog);
      await registry.load();
      const usable = registry.selected(draft.sources).filter((id) => registry.adapter(id).isConfigured());
      res.json({
        ...total,
        withinLimit: total.combinations <= draft.limits.maxCombinations,
        maxCombinations: draft.limits.maxCombinations,
        sources: { selected: registry.selected(draft.sources), usable },
      });
    },
  };
}
