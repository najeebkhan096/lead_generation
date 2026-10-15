import { test } from 'node:test';
import assert from 'node:assert/strict';
import { planClients } from './clientMigration.js';

const sale = (businessName, reviewLink, createdAt) => ({ businessName, reviewLink, createdAt });

test('one client per business, case and spacing ignored', () => {
  const plan = planClients([
    sale('Titan Collision center', 'sjjsj', '2026-10-01T00:00:00Z'),
    sale('Titan Collision Center', 'https://goo.gl/maps/AAA', '2026-10-02T00:00:00Z'),
    sale('Holy  Moly', 'defssf', '2026-10-03T00:00:00Z'),
  ]);
  assert.deepEqual(plan.map((c) => c.businessName), ['Holy Moly', 'Titan Collision Center']);
  assert.equal(plan.find((c) => c.nameKey === 'titan collision center').orders, 2);
});

test('takes the newest valid link, keeps the others as alternates, drops junk', () => {
  const [titan] = planClients([
    sale('Titan', 'maps.app.goo.gl/OLD', '2026-10-01T00:00:00Z'),
    sale('Titan', 'sjjsj', '2026-10-03T00:00:00Z'),
    sale('Titan', 'https://goo.gl/maps/NEW?g_st=aw', '2026-10-02T00:00:00Z'),
  ]);
  assert.equal(titan.mapsUrl, 'https://goo.gl/maps/NEW?g_st=aw');
  assert.deepEqual(titan.alternateUrls, ['https://maps.app.goo.gl/OLD']);
  assert.deepEqual(titan.rejectedLinks, ['sjjsj']);
});

test('a client with only junk links is kept without a link — never invented', () => {
  const [c] = planClients([sale('Holy Moly', 'jdjdjd', '2026-10-01T00:00:00Z'), sale('Holy Moly', 'defssf', '2026-10-02T00:00:00Z')]);
  assert.equal(c.mapsUrl, null);
  assert.deepEqual(c.rejectedLinks.sort(), ['defssf', 'jdjdjd']);
});

test('sales without a name are skipped', () => {
  assert.deepEqual(planClients([sale('  ', 'https://goo.gl/maps/x', null), sale('', null, null)]), []);
});
