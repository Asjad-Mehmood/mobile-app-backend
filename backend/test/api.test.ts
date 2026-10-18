import { afterAll, beforeAll, describe, expect, it } from 'vitest';
import { ADMIN, cake, createTestContext, KOHSAR, MURREE, pickup, STAFF_PASSWORD, TODAY, TOMORROW, type TestContext, waitFor } from './helpers.js';

let t: TestContext;
let customer: string;
let adminToken: string;
let staffF7: string;
let staffSaddar: string;

beforeAll(async () => {
  t = await createTestContext();
  customer = (await t.register('sara@test.pk')).token;
  adminToken = await t.login(ADMIN.email, ADMIN.password);
  staffF7 = await t.login('staff.f7@crumbandcraft.pk', STAFF_PASSWORD);
  staffSaddar = await t.login('staff.saddar@crumbandcraft.pk', STAFF_PASSWORD);
});
afterAll(() => t.close());

const stockOf = async (productId: string, hubId = 'hub-f7') => {
  const res = await t.call('GET', `/catalog?hubId=${hubId}`);
  return res.json.products.find((p: any) => p.id === productId).stock;
};

describe('auth', () => {
  it('registers, rejects duplicates and wrong passwords, returns me', async () => {
    expect((await t.call('POST', '/auth/register', { email: 'SARA@test.pk', password: 'whatever1', name: 'Dup' })).status).toBe(409);
    expect((await t.call('POST', '/auth/login', { email: 'sara@test.pk', password: 'nope' })).status).toBe(401);
    const me = await t.call('GET', '/auth/me', undefined, customer);
    expect(me.json.user).toMatchObject({ email: 'sara@test.pk', role: 'customer' });
    expect((await t.call('GET', '/auth/me')).status).toBe(401);
  });
  it('keeps customers out of staff and admin tools', async () => {
    expect((await t.call('GET', '/staff/orders', undefined, customer)).status).toBe(403);
    expect((await t.call('GET', '/admin/products', undefined, staffF7)).status).toBe(403);
  });
});

describe('public catalog', () => {
  it('serves branches, settings, catalog with per-branch stock, and zone checks', async () => {
    expect((await t.call('GET', '/hubs')).json).toHaveLength(3);
    expect((await t.call('GET', '/config')).json).toMatchObject({ currencySymbol: 'Rs', timezone: 'Asia/Karachi', deliveryFee: 250 });
    const catalog = await t.call('GET', '/catalog?hubId=hub-f7');
    expect(catalog.json.products).toHaveLength(15);
    const almond = catalog.json.products.find((p: any) => p.id === 'pastry-almond-croissant');
    expect(almond.stock).toMatchObject({ remainingBatchStock: 2, currentBatchNumber: 3 });
    expect(Date.parse(almond.stock.nextBatchReadyAt) - t.clock.now()).toBe(14 * 60_000);
    expect((await t.call('POST', '/zone-check', { latitude: KOHSAR.lat, longitude: KOHSAR.lng })).json).toMatchObject({ inZone: true, hub: { id: 'hub-f7' } });
    expect((await t.call('POST', '/zone-check', { latitude: MURREE.lat, longitude: MURREE.lng })).json.inZone).toBe(false);
  });
});

describe('checkout', () => {
  it('quotes server-side and flags missing slot', async () => {
    const q = await t.call('POST', '/orders/quote', pickup([{ productId: 'pastry-butter-croissant', quantity: 2 }], null), customer);
    expect(q.status).toBe(200);
    expect(q.json.pricing.total).toBe(1100 + 50);
    expect(q.json).toMatchObject({ canPlace: false, blockingIssue: 'Choose a time slot' });
  });

  it('places a same-day order, reserves stock, earns a stamp and emits order.created', async () => {
    const before = (await stockOf('pastry-butter-croissant')).remainingBatchStock;
    const res = await t.call('POST', '/orders', pickup([{ productId: 'pastry-butter-croissant', quantity: 2 }], { date: TODAY, startMinute: 720 }), customer);
    expect(res.status).toBe(201);
    expect(res.json).toMatchObject({ status: 'ORDER_CONFIRMED', stampsEarned: 1, hubName: 'F-7 Markaz Bakehouse', slot: { label: '12:00 PM - 02:00 PM' } });
    expect(res.json.id).toMatch(/^CC-[A-Z0-9]{6}$/);
    expect(res.json.pickupCode).toMatch(/^PU-\d{4}$/);
    expect((await stockOf('pastry-butter-croissant')).remainingBatchStock).toBe(before - 2);
    await waitFor(() => t.events.some((e) => e.type === 'order.created' && e.orderId === res.json.id));
  });

  it('enforces the 24-hour lead time and prices custom cakes', async () => {
    const items = [{ productId: 'cake-belgian-dark-truffle', quantity: 1, customization: cake() }];
    const today = await t.call('POST', '/orders', pickup(items, { date: TODAY, startMinute: 1080 }), customer);
    expect(today.status).toBe(422);
    expect(today.json.error.code).toBe('SLOT_UNAVAILABLE');
    const ok = await t.call('POST', '/orders', pickup(items, { date: TOMORROW, startMinute: 600 }), customer);
    expect(ok.status).toBe(201);
    expect(ok.json.lines[0]).toMatchObject({ unitPrice: 3800 + 4618, customization: { pipedMessage: 'Happy Birthday Ammi', sizeLabel: '1 kg' } });
    expect(ok.json.pricing).toMatchObject({ subtotal: 3800, customCakeSurcharge: 4618, packagingFee: 200 });
    const unconfigured = await t.call('POST', '/orders/quote', pickup([{ productId: 'cake-black-forest', quantity: 1 }], null), customer);
    expect(unconfigured.json.error.code).toBe('CAKE_NOT_CONFIGURED');
  });

  it('guards same-day batch stock but allows future days', async () => {
    const items = [{ productId: 'pastry-almond-croissant', quantity: 3 }];
    const today = await t.call('POST', '/orders', pickup(items, { date: TODAY, startMinute: 720 }), customer);
    expect(today.status).toBe(409);
    expect(today.json.error.message).toMatch(/Only 2 Almond Croissants left today/);
    const tomorrow = await t.call('POST', '/orders', pickup(items, { date: TOMORROW, startMinute: 720 }), customer);
    expect(tomorrow.status).toBe(201);
    expect((await stockOf('pastry-almond-croissant')).remainingBatchStock).toBe(2);
  });

  it('never oversells the last items to concurrent customers', async () => {
    const other = (await t.register()).token;
    const order = (token: string) =>
      t.call('POST', '/orders', pickup([{ productId: 'pastry-pistachio-raspberry', quantity: 2 }], { date: TODAY, startMinute: 840 }), token);
    const results = await Promise.all([order(customer), order(other)]); // stock is 3
    expect(results.map((r) => r.status).sort()).toEqual([201, 409]);
    expect((await stockOf('pastry-pistachio-raspberry')).remainingBatchStock).toBe(1);
  });

  it('checks the delivery radius against the branch', async () => {
    const items = [{ productId: 'cookie-sea-salt-dark', quantity: 2 }];
    const base = { hubId: 'hub-f7', fulfillmentType: 'DELIVERY', slot: { date: TOMORROW, startMinute: 660 }, items };
    const far = await t.call('POST', '/orders', { ...base, deliveryAddress: 'Mall Road, Murree', deliveryLat: MURREE.lat, deliveryLng: MURREE.lng }, customer);
    expect(far.status).toBe(422);
    expect(far.json.error.code).toBe('DELIVERY_ADDRESS');
    const near = await t.call('POST', '/orders', { ...base, deliveryAddress: 'Kohsar Market, F-6', deliveryLat: KOHSAR.lat, deliveryLng: KOHSAR.lng }, customer);
    expect(near.status).toBe(201);
    expect(near.json.pricing.deliveryFee).toBe(250);
    expect(near.json.pickupCode).toBeNull();
  });

  it('validates promo codes', async () => {
    const items = [{ productId: 'cookie-sea-salt-dark', quantity: 2 }];
    const slot = { date: TOMORROW, startMinute: 720 };
    const low = await t.call('POST', '/orders', pickup(items, slot, { promoCode: 'WELCOME500' }), customer);
    expect(low.json.error).toMatchObject({ code: 'PROMO_INVALID' });
    const q = await t.call('POST', '/orders/quote', pickup(items, slot, { promoCode: 'fresh10' }), customer);
    expect(q.json.promo.code).toBe('FRESH10');
    expect(q.json.pricing.promoDiscount).toBe(90);
  });

  it('serves slot grids with reasons', async () => {
    const res = await t.call('POST', '/orders/slots', { fulfillmentType: 'PICKUP', items: [{ productId: 'cake-black-forest', customization: cake() }] }, customer);
    expect(res.json[0].options.every((o: any) => !o.available)).toBe(true);
    expect(res.json[1].options.some((o: any) => o.available)).toBe(true);
  });
});

describe('staff workflow', () => {
  let orderId: string;
  let stockBefore: number;

  beforeAll(async () => {
    stockBefore = (await stockOf('cookie-vegan-choc-chip')).remainingBatchStock;
    const res = await t.call('POST', '/orders', pickup([{ productId: 'cookie-vegan-choc-chip', quantity: 4 }], { date: TODAY, startMinute: 960 }), customer);
    orderId = res.json.id;
  });

  it('shows branch orders to that branch only', async () => {
    const f7 = await t.call('GET', '/staff/orders?scope=active', undefined, staffF7);
    expect(f7.json.some((o: any) => o.id === orderId)).toBe(true);
    expect(f7.json[0].customer).toMatchObject({ name: 'Test Customer' });
    const saddar = await t.call('GET', '/staff/orders?scope=active', undefined, staffSaddar);
    expect(saddar.json.some((o: any) => o.id === orderId)).toBe(false);
    expect((await t.call('POST', `/staff/orders/${orderId}/status`, { status: 'IN_THE_OVEN' }, staffSaddar)).status).toBe(403);
  });

  it('moves orders forward only and notifies', async () => {
    const res = await t.call('POST', `/staff/orders/${orderId}/status`, { status: 'IN_THE_OVEN' }, staffF7);
    expect(res.json.status).toBe('IN_THE_OVEN');
    expect(res.json.statusHistory.map((h: any) => h.status)).toEqual(['ORDER_CONFIRMED', 'IN_THE_OVEN']);
    expect((await t.call('POST', `/staff/orders/${orderId}/status`, { status: 'MIXING_AND_PROOFING' }, staffF7)).status).toBe(409);
    await waitFor(() => t.events.some((e) => e.type === 'order.updated' && e.orderId === orderId));
    // Customer can no longer cancel once baking has started.
    expect((await t.call('POST', `/orders/${orderId}/cancel`, {}, customer)).status).toBe(409);
  });

  it('restores same-day stock when staff cancel', async () => {
    expect((await stockOf('cookie-vegan-choc-chip')).remainingBatchStock).toBe(stockBefore - 4);
    const res = await t.call('POST', `/staff/orders/${orderId}/status`, { status: 'CANCELLED', reason: 'Oven fault' }, staffF7);
    expect(res.json.status).toBe('CANCELLED');
    expect((await stockOf('cookie-vegan-choc-chip')).remainingBatchStock).toBe(stockBefore);
  });

  it('runs batches: start (countdown) and out (stock)', async () => {
    const started = await t.call('POST', '/staff/stock/bread-seeded-rye/start-batch', { readyInMinutes: 25 }, staffF7);
    expect(started.json).toMatchObject({ hubId: 'hub-f7', currentBatchNumber: 2 });
    expect(Date.parse(started.json.nextBatchReadyAt) - t.clock.now()).toBe(25 * 60_000);
    const out = await t.call('POST', '/staff/stock/bread-seeded-rye/batch-out', { quantity: 10 }, staffF7);
    expect(out.json).toMatchObject({ remainingBatchStock: 17, nextBatchReadyAt: null });
    expect((await t.call('POST', '/staff/stock/bread-seeded-rye/batch-out', { hubId: 'hub-saddar', quantity: 1 }, staffF7)).status).toBe(403);
    await waitFor(() => t.events.some((e) => e.type === 'stock.updated' && e.productIds.includes('bread-seeded-rye')));
  });

  it('lets a customer cancel while still confirmed', async () => {
    const res = await t.call('POST', '/orders', pickup([{ productId: 'drink-flat-white', quantity: 1 }], { date: TOMORROW, startMinute: 720 }), customer);
    expect((await t.call('POST', `/orders/${res.json.id}/cancel`, {}, customer)).json.status).toBe('CANCELLED');
    const stranger = (await t.register()).token;
    expect((await t.call('GET', `/orders/${res.json.id}`, undefined, stranger)).status).toBe(404);
  });
});

describe('customer sync data', () => {
  it('stores favourites, saved cakes and loyalty server-side', async () => {
    await t.call('PUT', '/me/favorites/bread-baguette', {}, customer);
    expect((await t.call('GET', '/me/favorites', undefined, customer)).json).toEqual(['bread-baguette']);
    const saved = await t.call('POST', '/me/saved-cakes', { productId: 'cake-black-forest', name: 'Ammi birthday', customization: cake({ sizeId: 'HALF_KG' }) }, customer);
    expect(saved.json.customization).toMatchObject({ sizeLabel: '0.5 kg', extraPrice: 750 });
    const loyalty = await t.call('GET', '/me/loyalty', undefined, customer);
    expect(loyalty.json.stampsEarned).toBeGreaterThan(0);
  });

  it('redeems a reward for the cheapest pastry once 12 stamps are earned', async () => {
    const { token, userId } = await t.register();
    await t.deps.sql`insert into orders (id, user_id, hub_id, fulfillment_type, slot_date, slot_start_minute, slot_end_minute, slot_label, payment_method, pricing, stamps_earned, status)
      values ('CC-LOYAL1', ${userId}, 'hub-f7', 'PICKUP', ${TOMORROW}, 600, 720, 'x', 'CARD', '{"total":1000}', 12, 'COMPLETED')`;
    const items = [{ productId: 'pastry-blueberry-muffin', quantity: 1 }, { productId: 'cookie-sea-salt-dark', quantity: 1 }];
    const q = await t.call('POST', '/orders/quote', pickup(items, { date: TOMORROW, startMinute: 720 }, { redeemReward: true }), token);
    expect(q.json.loyalty).toMatchObject({ rewardsAvailable: 1, rewardValue: 450, redeemed: true });
    expect(q.json.pricing.loyaltyDiscount).toBe(450);
  });
});

describe('admin', () => {
  it('manages the menu and the change reaches the catalog', async () => {
    const created = await t.call('POST', '/admin/products', {
      id: 'pastry-chai-bun', name: 'Doodh Patti Chai Bun', subtitle: 'Cardamom · brown sugar', basePrice: 400, category: 'PASTRY',
      allergens: ['GLUTEN', 'DAIRY'], bakeSchedule: 'MORNING_BAKE',
    }, adminToken);
    expect(created.status).toBe(201);
    expect((await t.call('GET', '/catalog?hubId=hub-bahria')).json.products.some((p: any) => p.id === 'pastry-chai-bun')).toBe(true);
    await t.call('PUT', '/admin/products/pastry-chai-bun', { name: 'Chai Bun', basePrice: 450, category: 'PASTRY' }, adminToken);
    expect((await stockOf('pastry-chai-bun', 'hub-bahria'))).toMatchObject({ remainingBatchStock: 0 });
    await t.call('DELETE', '/admin/products/pastry-chai-bun', undefined, adminToken);
    expect((await t.call('GET', '/catalog')).json.products.some((p: any) => p.id === 'pastry-chai-bun')).toBe(false);
    await waitFor(() => t.events.some((e) => e.type === 'catalog.updated'));
  });

  it('changes business settings used by pricing', async () => {
    await t.call('PUT', '/admin/settings', { deliveryFee: 300 }, adminToken);
    const q = await t.call('POST', '/orders/quote', {
      hubId: 'hub-f7', fulfillmentType: 'DELIVERY', items: [{ productId: 'cookie-sea-salt-dark', quantity: 1 }],
      deliveryAddress: 'F-6', deliveryLat: KOHSAR.lat, deliveryLng: KOHSAR.lng,
    }, customer);
    expect(q.json.pricing.deliveryFee).toBe(300);
    expect((await t.call('PUT', '/admin/settings', { pickupWindows: [[600, 500]] }, adminToken)).status).toBe(400);
  });

  it('manages branches, promos and the team', async () => {
    const hub = await t.call('POST', '/admin/hubs', { id: 'hub-g11', name: 'G-11 Markaz', address: 'G-11 Markaz, Islamabad', latitude: 33.668, longitude: 72.997 }, adminToken);
    expect(hub.status).toBe(201);
    const promo = await t.call('POST', '/admin/promos', { code: 'eid25', description: '25% off for Eid', type: 'PERCENT_OFF', value: 25, maxDiscount: 2000 }, adminToken);
    expect(promo.json.code).toBe('EID25');
    const user = await t.call('POST', '/admin/users', { email: 'ali@crumbandcraft.pk', password: 'password-123', name: 'Ali', role: 'staff', hubId: 'hub-g11' }, adminToken);
    expect(user.json).toMatchObject({ role: 'staff', hubId: 'hub-g11' });
    const aliToken = await t.login('ali@crumbandcraft.pk', 'password-123');
    expect((await t.call('GET', '/staff/stock', undefined, aliToken)).json.hubId).toBe('hub-g11');
    await t.call('PATCH', `/admin/users/${user.json.id}`, { isActive: false }, adminToken);
    expect((await t.call('GET', '/staff/stock', undefined, aliToken)).status).toBe(401);
    const meId = (await t.call('GET', '/auth/me', undefined, adminToken)).json.user.id;
    expect((await t.call('PATCH', `/admin/users/${meId}`, { role: 'staff' }, adminToken)).status).toBe(400);
  });

  it('reports sales', async () => {
    const r = await t.call('GET', `/admin/reports?from=${TODAY}&to=${TODAY}`, undefined, adminToken);
    expect(r.json.totals.orders).toBeGreaterThan(3);
    expect(r.json.totals.revenue).toBeGreaterThan(0);
    expect(r.json.byHub[0].hubName).toBeTruthy();
    expect(r.json.topProducts.length).toBeGreaterThan(0);
  });
});
