import type { Hono } from 'hono';
import { z } from 'zod';
import { loyaltyStatus, resolveCake } from '../domain/rules.js';
import { notFound } from '../errors.js';
import { body, cakeChoiceSchema, checkoutSchema, requireAuth, slotsSchema, type AppDeps, type AppEnv } from '../http.js';
import {
  canSeeOrder,
  changeStatus,
  getOrder,
  listOrdersForUser,
  placeOrder,
  prepareOrder,
  quoteView,
  slotsFor,
} from '../services/orders.js';
import { getProductsByIds, getSettings, iso, loyaltyCounts } from '../services/repo.js';

/** Signed-in customer features. Staff and admins can use them too (e.g. for testing). */
export function customerRoutes(app: Hono<AppEnv>, deps: AppDeps) {
  const { sql, bus } = deps;
  const auth = requireAuth(deps);

  // ── Favourites (synced across devices) ──
  app.get('/me/favorites', auth, async (c) => {
    const rows = await sql`select product_id from favorites where user_id = ${c.get('user').id} order by created_at desc`;
    return c.json(rows.map((r) => r.productId));
  });
  app.put('/me/favorites/:productId', auth, async (c) => {
    const productId = c.req.param('productId');
    const products = await getProductsByIds(sql, [productId]);
    if (!products.has(productId)) throw notFound('Product not found');
    await sql`insert into favorites (user_id, product_id) values (${c.get('user').id}, ${productId}) on conflict do nothing`;
    return c.json({ ok: true });
  });
  app.delete('/me/favorites/:productId', auth, async (c) => {
    await sql`delete from favorites where user_id = ${c.get('user').id} and product_id = ${c.req.param('productId')}`;
    return c.json({ ok: true });
  });

  // ── Saved cake blueprints ──
  app.get('/me/saved-cakes', auth, async (c) => {
    const rows = await sql`select * from saved_cakes where user_id = ${c.get('user').id} order by created_at desc`;
    return c.json(rows.map((r) => ({ id: Number(r.id), productId: r.productId, name: r.name, customization: r.customization, createdAt: iso(r.createdAt) })));
  });
  app.post('/me/saved-cakes', auth, async (c) => {
    const input = await body(c, z.object({ productId: z.string(), name: z.string().trim().min(1).max(80), customization: cakeChoiceSchema }));
    const product = (await getProductsByIds(sql, [input.productId])).get(input.productId);
    if (!product?.isCustomizableCake) throw notFound('Cake not found');
    const resolved = resolveCake(await getSettings(sql), product.basePrice, product.allergens, input.customization);
    const [row] = await sql`insert into saved_cakes ${sql({
      userId: c.get('user').id,
      productId: product.id,
      name: input.name,
      customization: sql.json(resolved as never),
    } as never)} returning *`;
    return c.json({ id: Number(row.id), productId: row.productId, name: row.name, customization: row.customization, createdAt: iso(row.createdAt) }, 201);
  });
  app.delete('/me/saved-cakes/:id', auth, async (c) => {
    await sql`delete from saved_cakes where id = ${Number(c.req.param('id'))} and user_id = ${c.get('user').id}`;
    return c.json({ ok: true });
  });

  // ── Loyalty ──
  app.get('/me/loyalty', auth, async (c) => {
    const counts = await loyaltyCounts(sql, c.get('user').id);
    return c.json(loyaltyStatus(await getSettings(sql), counts.earned, counts.redeemed));
  });

  // ── Checkout ──
  app.post('/orders/slots', auth, async (c) => {
    const input = await body(c, slotsSchema);
    return c.json(await slotsFor(sql, input.fulfillmentType, input.items, deps.now()));
  });

  app.post('/orders/quote', auth, async (c) => {
    const input = await body(c, checkoutSchema);
    return c.json(quoteView(await prepareOrder(sql, c.get('user'), input, deps.now())));
  });

  app.post('/orders', auth, async (c) => {
    const input = await body(c, checkoutSchema);
    return c.json(await placeOrder(sql, bus, c.get('user'), input, deps.now()), 201);
  });

  app.get('/orders', auth, async (c) => c.json(await listOrdersForUser(sql, c.get('user').id)));

  app.get('/orders/:id', auth, async (c) => {
    const order = await getOrder(sql, c.req.param('id'));
    if (!order || !canSeeOrder(c.get('user'), order)) throw notFound('Order not found');
    return c.json(order);
  });

  app.post('/orders/:id/cancel', auth, async (c) => {
    return c.json(await changeStatus(sql, bus, c.get('user'), c.req.param('id'), 'CANCELLED', deps.now(), 'Cancelled by customer'));
  });
}
