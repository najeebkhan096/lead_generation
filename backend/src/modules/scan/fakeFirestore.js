// Test helper: an in-memory stand-in for the slice of Firestore the run store uses.

/** An in-memory stand-in for the slice of Firestore the store uses. */
export function fakeDb() {
  const data = new Map();
  const ref = (collection, id) => ({
    async get() {
      const value = data.get(`${collection}/${id}`);
      return { id, exists: value !== undefined, data: () => (value === undefined ? undefined : structuredClone(value)) };
    },
    async set(patch, opts = {}) {
      const prior = opts.merge ? data.get(`${collection}/${id}`) || {} : {};
      data.set(`${collection}/${id}`, { ...prior, ...structuredClone(patch) });
    },
    async delete() {
      data.delete(`${collection}/${id}`);
    },
  });
  return {
    data,
    collection: (c) => ({
      doc: (id) => ref(c, id),
      async get() {
        const docs = [...data.entries()]
          .filter(([k]) => k.startsWith(`${c}/`))
          .map(([k, v]) => ({ id: k.slice(c.length + 1), data: () => structuredClone(v) }));
        return { docs };
      },
    }),
  };
}
