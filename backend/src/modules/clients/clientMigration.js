import { clientNameKey, normalizeMapsUrl } from '../../lib/mapsUrl.js';

/**
 * Turns existing sales into the client list: one entry per business (same
 * name ignoring case and spacing) with its Google Maps link.
 *
 * - The link comes from the most recent sale that has a *valid* Google link;
 *   any other valid links are reported as alternates, never merged.
 * - A link that is not a Google link (typed junk) is never stored; the
 *   client is created without one so it can be filled in properly.
 * - Nothing is invented: a client with no valid link has `mapsUrl: null`.
 */
export function planClients(sales) {
  const groups = new Map();
  for (const sale of sales) {
    const name = String(sale.businessName || '').trim().replace(/\s+/g, ' ');
    const key = clientNameKey(name);
    if (!key) continue;
    if (!groups.has(key)) groups.set(key, []);
    groups.get(key).push({ ...sale, businessName: name });
  }

  const byNewest = (a, b) => String(b.createdAt || '').localeCompare(String(a.createdAt || ''));

  const clients = [];
  for (const [key, group] of groups) {
    group.sort(byNewest);
    const valid = [];
    const rejected = [];
    for (const sale of group) {
      const raw = (sale.reviewLink || '').trim();
      if (!raw) continue;
      const url = normalizeMapsUrl(raw);
      if (url) {
        if (!valid.includes(url)) valid.push(url);
      } else if (!rejected.includes(raw)) {
        rejected.push(raw);
      }
    }
    clients.push({
      nameKey: key,
      businessName: group[0].businessName,
      mapsUrl: valid[0] || null,
      alternateUrls: valid.slice(1),
      rejectedLinks: rejected,
      orders: group.length,
    });
  }
  clients.sort((a, b) => a.businessName.localeCompare(b.businessName, undefined, { sensitivity: 'base' }));
  return clients;
}
