/**
 * An in-memory stand-in for the slice of the Firestore Admin API that the
 * Jobs module uses — so store/queue/scan logic is tested without any network
 * and, importantly, without ever touching the production database.
 *
 * It mimics the behaviours that matter for correctness:
 *   - documents missing an `orderBy` field are excluded from the result,
 *   - `create()` fails on an existing document (gRPC code 6),
 *   - `update()` fails on a missing document (code 5),
 *   - `set(..., {merge: true})` deep-merges maps and replaces arrays,
 *   - dotted field paths in `update()` / `where()`,
 *   - `startAfter(values…)` follows the `orderBy` list.
 *
 * It does NOT model indexes, security rules, or transaction contention.
 */

import { FieldPath } from 'firebase-admin/firestore';

class FakeError extends Error {
  constructor(code, message) {
    super(message);
    this.code = code;
  }
}

const isPlainObject = (v) => v && typeof v === 'object' && !Array.isArray(v) && !(v instanceof Date);
const clone = (v) => structuredClone(v);

function getPath(obj, path) {
  let cur = obj;
  for (const part of path.split('.')) {
    if (cur == null) return undefined;
    cur = cur[part];
  }
  return cur;
}

function setPath(obj, path, value) {
  const parts = path.split('.');
  let cur = obj;
  for (let i = 0; i < parts.length - 1; i++) {
    if (!isPlainObject(cur[parts[i]])) cur[parts[i]] = {};
    cur = cur[parts[i]];
  }
  cur[parts[parts.length - 1]] = value;
}

function deepMerge(target, patch) {
  for (const [k, v] of Object.entries(patch)) {
    if (isPlainObject(v) && isPlainObject(target[k])) deepMerge(target[k], v);
    else target[k] = clone(v);
  }
  return target;
}

const comparable = (v) => (v instanceof Date ? v.getTime() : v && typeof v.toMillis === 'function' ? v.toMillis() : v);

function compare(a, b) {
  const x = comparable(a);
  const y = comparable(b);
  if (x === y) return 0;
  if (x == null) return -1;
  if (y == null) return 1;
  return x < y ? -1 : 1;
}

class Snapshot {
  constructor(ref, data) {
    this.ref = ref;
    this.id = ref.id;
    this._data = data;
  }
  get exists() {
    return this._data !== undefined;
  }
  data() {
    return this._data === undefined ? undefined : clone(this._data);
  }
  get(field) {
    return this._data === undefined ? undefined : getPath(this._data, field);
  }
}

class DocRef {
  constructor(db, path) {
    this.db = db;
    this.path = path;
    this.id = path.split('/').pop();
  }
  get parent() {
    return new CollectionRef(this.db, this.path.split('/').slice(0, -1).join('/'));
  }
  collection(name) {
    return new CollectionRef(this.db, `${this.path}/${name}`);
  }
  async get() {
    return new Snapshot(this, this.db.docs.get(this.path));
  }
  async set(data, options) {
    this.db._set(this.path, data, options);
  }
  async create(data) {
    this.db._create(this.path, data);
  }
  async update(patch) {
    this.db._update(this.path, patch);
  }
  async delete() {
    this.db.docs.delete(this.path);
  }
}

class Query {
  constructor(db, collectionPath, spec = {}) {
    this.db = db;
    this.collectionPath = collectionPath;
    this.spec = { filters: [], orders: [], limit: null, cursor: null, ...spec };
  }
  _with(patch) {
    return new Query(this.db, this.collectionPath, { ...this.spec, ...patch });
  }
  where(field, op, value) {
    return this._with({ filters: [...this.spec.filters, { field, op, value }] });
  }
  orderBy(field, dir = 'asc') {
    return this._with({ orders: [...this.spec.orders, { field, dir }] });
  }
  limit(n) {
    return this._with({ limit: n });
  }
  startAfter(...values) {
    return this._with({ cursor: values });
  }
  select() {
    return this; // field masks only save bandwidth; the fake returns whole documents
  }
  count() {
    return { get: async () => ({ data: () => ({ count: this._run(false).length }) }) };
  }

  _run(applyLimit = true) {
    const { filters, orders, limit, cursor } = this.spec;
    const prefix = `${this.collectionPath}/`;
    let rows = [];
    for (const [path, data] of this.db.docs) {
      if (!path.startsWith(prefix) || path.slice(prefix.length).includes('/')) continue;
      rows.push({ path, id: path.slice(prefix.length), data });
    }
    rows = rows.filter((r) =>
      filters.every(({ field, op, value }) => {
        const actual = field instanceof FieldPath ? r.id : getPath(r.data, field);
        switch (op) {
          case '==':
            return compare(actual, value) === 0 && !(actual === undefined && value !== undefined);
          case '!=':
            return actual !== undefined && compare(actual, value) !== 0;
          case '<':
            return actual != null && compare(actual, value) < 0;
          case '<=':
            return actual != null && compare(actual, value) <= 0;
          case '>':
            return actual != null && compare(actual, value) > 0;
          case '>=':
            return actual != null && compare(actual, value) >= 0;
          case 'in':
            return value.some((v) => compare(actual, v) === 0);
          case 'array-contains':
            return Array.isArray(actual) && actual.some((v) => compare(v, value) === 0);
          case 'array-contains-any':
            return Array.isArray(actual) && actual.some((v) => value.some((w) => compare(v, w) === 0));
          default:
            throw new Error(`fake firestore: unsupported operator ${op}`);
        }
      }),
    );
    const valueOf = (row, field) => (field instanceof FieldPath ? row.id : getPath(row.data, field));
    // Firestore leaves out documents that lack an ordered field.
    for (const o of orders) rows = rows.filter((r) => o.field instanceof FieldPath || valueOf(r, o.field) !== undefined);
    const orderList = orders.length ? orders : [{ field: new FieldPath('__name__'), dir: 'asc' }];
    const effective = orders.length && !orders.some((o) => o.field instanceof FieldPath) ? [...orderList, { field: FieldPath.documentId(), dir: orderList[orderList.length - 1].dir }] : orderList;
    rows.sort((a, b) => {
      for (const o of effective) {
        const c = compare(valueOf(a, o.field), valueOf(b, o.field));
        if (c !== 0) return o.dir === 'desc' ? -c : c;
      }
      return 0;
    });
    if (cursor) {
      rows = rows.filter((r) => {
        for (let i = 0; i < cursor.length && i < effective.length; i++) {
          const c = compare(valueOf(r, effective[i].field), cursor[i]);
          if (c !== 0) return effective[i].dir === 'desc' ? c < 0 : c > 0;
        }
        return false;
      });
    }
    if (applyLimit && limit != null) rows = rows.slice(0, limit);
    return rows;
  }

  async get() {
    const docs = this._run().map((r) => new Snapshot(new DocRef(this.db, r.path), r.data));
    return { docs, size: docs.length, empty: docs.length === 0 };
  }
}

class CollectionRef extends Query {
  constructor(db, path) {
    super(db, path);
    this.path = path;
  }
  doc(id) {
    return new DocRef(this.db, `${this.path}/${id}`);
  }
}

class WriteBatch {
  constructor(db) {
    this.db = db;
    this.ops = [];
  }
  set(ref, data, options) {
    this.ops.push(() => this.db._set(ref.path, data, options));
    return this;
  }
  create(ref, data) {
    this.ops.push(() => this.db._create(ref.path, data));
    return this;
  }
  update(ref, patch) {
    this.ops.push(() => this.db._update(ref.path, patch));
    return this;
  }
  delete(ref) {
    this.ops.push(() => this.db.docs.delete(ref.path));
    return this;
  }
  async commit() {
    if (this.ops.length > 500) throw new FakeError(3, 'A batch may contain at most 500 writes');
    // All-or-nothing, as in Firestore: apply to a copy, then swap in.
    const snapshot = new Map([...this.db.docs].map(([k, v]) => [k, clone(v)]));
    try {
      this.ops.forEach((op) => op());
    } catch (err) {
      this.db.docs = snapshot;
      throw err;
    }
  }
}

export class FakeFirestore {
  constructor() {
    this.docs = new Map(); // path -> data
    this.writes = 0;
    this.reads = 0;
  }
  collection(name) {
    return new CollectionRef(this, name);
  }
  doc(path) {
    return new DocRef(this, path);
  }
  async getAll(...refs) {
    return Promise.all(refs.map((r) => r.get()));
  }
  batch() {
    return new WriteBatch(this);
  }
  async runTransaction(fn) {
    const tx = {
      get: (refOrQuery) => refOrQuery.get(),
      set: (ref, data, options) => this._set(ref.path, data, options),
      update: (ref, patch) => this._update(ref.path, patch),
      create: (ref, data) => this._create(ref.path, data),
      delete: (ref) => this.docs.delete(ref.path),
    };
    return fn(tx);
  }

  _set(path, data, options) {
    this.writes += 1;
    if (options?.merge && this.docs.has(path)) deepMerge(this.docs.get(path), data);
    else this.docs.set(path, clone(data));
  }
  _create(path, data) {
    if (this.docs.has(path)) throw new FakeError(6, `ALREADY_EXISTS: ${path}`);
    this.writes += 1;
    this.docs.set(path, clone(data));
  }
  _update(path, patch) {
    if (!this.docs.has(path)) throw new FakeError(5, `NOT_FOUND: ${path}`);
    this.writes += 1;
    const doc = this.docs.get(path);
    for (const [k, v] of Object.entries(patch)) setPath(doc, k, clone(v));
  }

  /** Test helper: all documents of a top-level collection as [id, data]. */
  dump(collection) {
    const prefix = `${collection}/`;
    return [...this.docs].filter(([p]) => p.startsWith(prefix) && !p.slice(prefix.length).includes('/')).map(([p, d]) => [p.slice(prefix.length), clone(d)]);
  }
}
