import type { Context, Hono } from 'hono';
import { z } from 'zod';
import { ORDER_STATUSES } from '../domain/types.js';
import { badRequest, forbidden, notFound } from '../errors.js';
import { body, requireAuth, type AppDeps, type AppEnv } from '../http.js';
import { canSeeOrder, changeStatus, getOrder, listOrdersForStaff } from '../services/orders.js';
import { EMPTY_STOCK, getSettings, iso, listHubs, listProducts, stockForHub } from '../services/repo.js';

/** Kitchen & counter tools: live order board, status updates, batch stock. Staff + admin. */
export function staffRoutes(app: Hono<AppEnv>, deps: AppDeps) {
  const { sql, bus } = deps;
  const staff = requireAuth(deps, ['staff', 'admin']);

  /** Staff are pinned to their branch; admins (and staff with no branch) can pick any. */
  async function resolveHubId(c: Context<AppEnv>, requested?: string | null): Promise<string> {
    const user = c.get('user');
    if (user.role === 'staff' && user.hubId) {
      if (requested && requested !== user.hubId) throw forbidden('You can only manage your own branch');
      return user.hubId;
    }
    const hubs = await listHubs(sql, true);
    const id = requested || hubs[0]?.id;
    if (!id || !hubs.some((h) => h.id === id)) throw badRequest('Unknown branch', 'INVALID_HUB');
    return id;
  }

  // ── Orders ──
  app.get('/staff/orders', staff, async (c) => {
    const user = c.get('user');
    const scope = (c.req.query('scope') ?? 'active') as 'active' | 'today' | 'all';
    if (!['active', 'today', 'all'].includes(scope)) throw badRequest('scope must be active, today or all');
    const requested = c.req.query('hubId');
    const hubId = user.role === 'staff' && user.hubId ? user.hubId : requested || null;
    const settings = await getSettings(sql);
    return c.json(await listOrdersForStaff(sql, { hubId, scope, tz: settings.timezone, nowMs: deps.now() }));
  });

  app.get('/staff/orders/:id', staff, async (c) => {
    const order = await getOrder(sql, c.req.param('id'));
    if (!order || !canSeeOrder(c.get('user'), order)) throw notFound('Order not found');
    return c.json(order);
  });

  app.post('/staff/orders/:id/status', staff, async (c) => {
    const input = await body(c, z.object({ status: z.enum(ORDER_STATUSES), reason: z.string().max(200).nullish() }));
    return c.json(await changeStatus(sql, bus, c.get('user'), c.req.param('id'), input.status, deps.now(), input.reason ?? undefined));
  });

  // ── Batch stock ──
  app.get('/staff/stock', staff, async (c) => {
    const hubId = await resolveHubId(c, c.req.query('hubId'));
    const [products, stock] = await Promise.all([listProducts(sql), stockForHub(sql, hubId)]);
    return c.json({
      hubId,
      items: products
        .filter((p) => !p.isCustomizableCake)
        .map((p) => ({ product: p, stock: stock.get(p.id) ?? EMPTY_STOCK })),
    });
  });

  async function upsertStock(productId: string, hubId: string, patch: Record<string, unknown>) {
    const [exists] = await sql`select 1 from products where id = ${productId}`;
    if (!exists) throw notFound('Product not found');
    await sql`insert into product_stock (product_id, hub_id) values (${productId}, ${hubId}) on conflict do nothing`;
    const [row] = await sql`update product_stock set ${sql(patch as never)}, updated_at = now()
                            where product_id = ${productId} and hub_id = ${hubId} returning *`;
    await bus.publish({ type: 'stock.updated', hubId, productIds: [productId] });
    return { productId, hubId, remainingBatchStock: row.remainingBatchStock, currentBatchNumber: row.currentBatchNumber, nextBatchReadyAt: iso(row.nextBatchReadyAt) };
  }

  /** Set exact values (e.g. after a stock count). */
  app.patch('/staff/stock/:productId', staff, async (c) => {
    const input = await body(
      c,
      z.object({
        hubId: z.string().nullish(),
        remainingBatchStock: z.number().int().min(0).max(10_000).optional(),
        currentBatchNumber: z.number().int().min(1).max(10_000).optional(),
        nextBatchReadyAt: z.iso.datetime().nullish(),
      }),
    );
    const hubId = await resolveHubId(c, input.hubId);
    const patch: Record<string, unknown> = {};
    if (input.remainingBatchStock !== undefined) patch.remainingBatchStock = input.remainingBatchStock;
    if (input.currentBatchNumber !== undefined) patch.currentBatchNumber = input.currentBatchNumber;
    if (input.nextBatchReadyAt !== undefined) patch.nextBatchReadyAt = input.nextBatchReadyAt ? new Date(input.nextBatchReadyAt) : null;
    if (Object.keys(patch).length === 0) throw badRequest('Nothing to update');
    return c.json(await upsertStock(c.req.param('productId'), hubId, patch));
  });

  /** A batch goes into the oven: drives the customer app's live countdown banner. */
  app.post('/staff/stock/:productId/start-batch', staff, async (c) => {
    const input = await body(c, z.object({ hubId: z.string().nullish(), readyInMinutes: z.number().int().min(1).max(600) }));
    const hubId = await resolveHubId(c, input.hubId);
    const productId = c.req.param('productId');
    await sql`insert into product_stock (product_id, hub_id) values (${productId}, ${hubId}) on conflict do nothing`;
    const [current] = await sql`select current_batch_number from product_stock where product_id = ${productId} and hub_id = ${hubId}`;
    return c.json(
      await upsertStock(productId, hubId, {
        currentBatchNumber: (current?.currentBatchNumber ?? 0) + 1,
        nextBatchReadyAt: new Date(deps.now() + input.readyInMinutes * 60_000),
      }),
    );
  });

  /** The batch is out: add it to the shelf and clear the countdown. */
  app.post('/staff/stock/:productId/batch-out', staff, async (c) => {
    const input = await body(c, z.object({ hubId: z.string().nullish(), quantity: z.number().int().min(0).max(1000) }));
    const hubId = await resolveHubId(c, input.hubId);
    const productId = c.req.param('productId');
    await sql`insert into product_stock (product_id, hub_id) values (${productId}, ${hubId}) on conflict do nothing`;
    const [current] = await sql`select remaining_batch_stock from product_stock where product_id = ${productId} and hub_id = ${hubId}`;
    return c.json(
      await upsertStock(productId, hubId, {
        remainingBatchStock: (current?.remainingBatchStock ?? 0) + input.quantity,
        nextBatchReadyAt: null,
      }),
    );
  });
}
