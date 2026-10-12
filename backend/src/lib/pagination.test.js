import { test } from 'node:test';
import assert from 'node:assert/strict';
import { Timestamp } from 'firebase-admin/firestore';
import {
  pagedList,
  encodeCursor,
  decodeCursor,
  buildMatcher,
  parsePageSize,
  listCategories,
  invalidateCategories,
} from './pagination.js';

// ---- a just-enough in-memory Firestore ------------------------------------

class FakeDoc {
  constructor(id, data) {
    this.id = id;
    this._data = data;
    this.exists = true;
    this.ref = { id };
  }
  data() {
    return this._data;
  }
  get(field) {
    return this._data[field];
  }
}

class FakeQuery {
  constructor(store, state = {}) {
    this.store = store;
    this.s = { wheres: [], orders: [], start: null, max: null, ...state };
  }
  _with(patch) {
    return new FakeQuery(this.store, { ...this.s, ...patch });
  }
  where(field, op, value) {
    assert.equal(op, '==');
    if (this.store.requireIndexFor === field) {
      const err = new Error('9 FAILED_PRECONDITION: The query requires an index.');
      err.code = 9;
      this._boom = err;
    }
    const q = this._with({ wheres: [...this.s.wheres, [field, value]] });
    q._boom = this._boom;
    if (this.store.requireIndexFor === field) q._boom = Object.assign(new Error('requires an index'), { code: 9 });
    return q;
  }
  orderBy(field, dir = 'asc') {
    // a FieldPath.documentId() is a non-string
    return this._with({ orders: [...this.s.orders, [typeof field === 'string' ? field : '__id', dir]] });
  }
  startAfter(...vals) {
    return this._with({ start: vals });
  }
  limit(n) {
    return this._with({ max: n });
  }
  select() {
    return this;
  }
  _rows() {
    this.store.reads += 0;
    let rows = this.store.docs.filter((d) => this.s.wheres.every(([f, v]) => d.data()[f] === v));
    const val = (d, f) => (f === '__id' ? d.id : f === 'updatedAt' ? d.get(f).toMillis() : d.get(f));
    const orders = this.s.orders.length ? this.s.orders : [['__id', 'asc']];
    const cmp = (a, b) => {
      for (const [f, dir] of orders) {
        const x = val(a, f);
        const y = val(b, f);
        if (x < y) return dir === 'desc' ? 1 : -1;
        if (x > y) return dir === 'desc' ? -1 : 1;
      }
      return 0;
    };
    rows = [...rows].sort(cmp);
    if (this.s.start) {
      const probe = new FakeDoc(
        this.s.start[this.s.orders.findIndex(([f]) => f === '__id')],
        { updatedAt: this.s.start[0] instanceof Timestamp ? this.s.start[0] : null }
      );
      rows = rows.filter((d) => cmp(d, probe) > 0);
    }
    if (this.s.max != null) rows = rows.slice(0, this.s.max);
    return rows;
  }
  async get() {
    if (this._boom) throw this._boom;
    const rows = this._rows();
    this.store.reads += rows.length;
    return { docs: rows, size: rows.length };
  }
  count() {
    return { get: async () => ({ data: () => ({ count: this._rowsNoLimit().length }) }) };
  }
  _rowsNoLimit() {
    return this.store.docs.filter((d) => this.s.wheres.every(([f, v]) => d.data()[f] === v));
  }
}

function fakeDb(rows, { requireIndexFor = null } = {}) {
  const store = {
    reads: 0,
    requireIndexFor,
    docs: rows.map((r) => new FakeDoc(r.id, { ...r, updatedAt: Timestamp.fromMillis(r.ms) })),
  };
  return {
    store,
    collection: () => new FakeQuery(store),
    getAll: async (...refs) => refs.map((r) => store.docs.find((d) => d.id === r.id)),
  };
}

const map = (doc) => ({ id: doc.id, business: doc.get('business') });

function dataset(n, { sameTimestamp = false } = {}) {
  return Array.from({ length: n }, (_, i) => ({
    id: `d${String(i).padStart(4, '0')}`,
    ms: sameTimestamp ? 1000 : 1_000_000 - i * 1000,
    business: `Business ${i}`,
    category: i % 3 === 0 ? 'Cafe' : i % 3 === 1 ? 'Bakery' : 'Garage',
    phone: `+1 (512) 555-${String(i).padStart(4, '0')}`,
  }));
}

async function allPages(db, opts) {
  const ids = [];
  let cursor;
  let pages = 0;
  do {
    const res = await pagedList({ db, collection: 'x', mapDoc: map, cursor, ...opts });
    ids.push(...res.leads.map((l) => l.id));
    cursor = res.nextCursor;
    pages += 1;
    assert.ok(pages < 500, 'runaway pagination');
  } while (cursor);
  return { ids, pages };
}

// ---- tests ----------------------------------------------------------------

test('parsePageSize clamps and defaults', () => {
  assert.equal(parsePageSize(undefined), 50);
  assert.equal(parsePageSize('0'), 50);
  assert.equal(parsePageSize('25'), 25);
  assert.equal(parsePageSize('99999'), 200);
});

test('cursors round-trip and reject garbage', () => {
  const doc = new FakeDoc('abc', { updatedAt: Timestamp.fromMillis(1234) });
  assert.deepEqual(decodeCursor(encodeCursor(doc)), { ms: 1234, id: 'abc' });
  assert.equal(decodeCursor(undefined), null);
  assert.throws(() => decodeCursor('not-a-cursor'), (e) => e.status === 400);
});

test('indexed path: every document exactly once, newest first, with a total', async () => {
  const db = fakeDb(dataset(237));
  const first = await pagedList({ db, collection: 'x', mapDoc: map, limit: 50 });
  assert.equal(first.leads.length, 50);
  assert.equal(first.total, 237);
  assert.equal(first.leads[0].id, 'd0000');
  assert.ok(first.nextCursor);

  const { ids, pages } = await allPages(db, { limit: 50 });
  assert.equal(ids.length, 237);
  assert.equal(new Set(ids).size, 237, 'no duplicates across pages');
  assert.deepEqual(ids, [...ids].sort(), 'newest first');
  assert.equal(pages, 5);
});

test('indexed path reads one page, not the collection', async () => {
  const db = fakeDb(dataset(1000));
  await pagedList({ db, collection: 'x', mapDoc: map, limit: 25 });
  assert.ok(db.store.reads <= 26, `read ${db.store.reads} docs for a 25-doc page`);
});

test('documents sharing an updatedAt are neither skipped nor repeated', async () => {
  const db = fakeDb(dataset(120, { sameTimestamp: true }));
  const { ids } = await allPages(db, { limit: 30 });
  assert.equal(ids.length, 120);
  assert.equal(new Set(ids).size, 120);
});

test('last page has no cursor', async () => {
  const db = fakeDb(dataset(10));
  const res = await pagedList({ db, collection: 'x', mapDoc: map, limit: 10 });
  assert.equal(res.nextCursor, null);
  assert.equal(res.leads.length, 10);
});

test('category filter is applied server-side with its own total', async () => {
  const db = fakeDb(dataset(90));
  const res = await pagedList({ db, collection: 'x', mapDoc: map, limit: 20, category: 'Cafe' });
  assert.equal(res.total, 30);
  const { ids } = await allPages(db, { limit: 20, category: 'Cafe' });
  assert.equal(ids.length, 30);
  assert.ok(ids.every((id) => Number(id.slice(1)) % 3 === 0));
});

test('missing composite index falls back to filtering by category in memory', async () => {
  const db = fakeDb(dataset(90), { requireIndexFor: 'category' });
  const { ids } = await allPages(db, { limit: 20, category: 'Bakery' });
  assert.equal(ids.length, 30);
  assert.ok(ids.every((id) => Number(id.slice(1)) % 3 === 1));
});

test('search scans server-side, fills a page, and resumes without gaps', async () => {
  const rows = dataset(2000);
  const db = fakeDb(rows);
  // "business 19": the word 19 may hit the name or the phone digits.
  const expected = rows.filter(
    (r) => r.business.toLowerCase().includes('19') || r.phone.replace(/\D/g, '').includes('19')
  ).length;
  assert.ok(expected > 100, 'sanity: enough matches to need several pages');

  const { ids, pages } = await allPages(db, { limit: 50, q: 'business 19' });
  assert.equal(new Set(ids).size, ids.length, 'no duplicates');
  assert.equal(ids.length, expected);
  assert.ok(pages > 1);
});

test('search matches phone digits in any formatting', async () => {
  const db = fakeDb(dataset(300));
  const res = await pagedList({ db, collection: 'x', mapDoc: map, q: '5550123', limit: 50 });
  assert.deepEqual(res.leads.map((l) => l.id), ['d0123']);
});

test('search: a rare term scans past the budget and the client can resume', async () => {
  const rows = dataset(12000);
  rows[11990].business = 'Zebra Zoo';
  const db = fakeDb(rows);
  const first = await pagedList({ db, collection: 'x', mapDoc: map, q: 'zebra', limit: 10 });
  // scan budget exhausted before reaching the match: no results yet, but a cursor
  assert.equal(first.leads.length, 0);
  assert.ok(first.nextCursor, 'cursor to continue the scan');
  const { ids } = await allPages(db, { limit: 10, q: 'zebra' });
  assert.deepEqual(ids, ['d11990']);
});

test('memory filter combines with search and category', async () => {
  const db = fakeDb(dataset(60));
  const res = await pagedList({
    db,
    collection: 'x',
    mapDoc: map,
    limit: 100,
    category: 'Garage',
    memoryFilter: (d) => Number(d.id.slice(1)) % 2 === 0,
  });
  assert.ok(res.leads.length > 0);
  assert.ok(res.leads.every((l) => Number(l.id.slice(1)) % 3 === 2 && Number(l.id.slice(1)) % 2 === 0));
});

test('buildMatcher needs every word, across fields', () => {
  const m = buildMatcher('joe austin', ['business', 'address']);
  assert.equal(m({ business: "Joe's Pizza", address: '12 Main, Austin' }), true);
  assert.equal(m({ business: "Joe's Pizza", address: '12 Main, Dallas' }), false);
  assert.equal(buildMatcher('  ', ['business']), null);
});

test('categories: counted once, cached, and rescanned after invalidation', async () => {
  const db = fakeDb(dataset(30));
  const first = await listCategories(db, 'catcol');
  assert.deepEqual(first.map((c) => c.count), [10, 10, 10]);
  const reads = db.store.reads;
  await listCategories(db, 'catcol');
  assert.equal(db.store.reads, reads, 'second call served from cache');
  invalidateCategories('catcol');
  await listCategories(db, 'catcol');
  assert.ok(db.store.reads > reads, 'rescanned after invalidation');
});
