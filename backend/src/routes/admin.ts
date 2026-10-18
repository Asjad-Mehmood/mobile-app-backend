import type { Hono } from 'hono';
import { z } from 'zod';
import { ALLERGENS } from '../domain/types.js';
import { addDays, todayIn } from '../domain/time.js';
import { badRequest, conflict, notFound } from '../errors.js';
import { body, productBodySchema, requireAuth, slug, type AppDeps, type AppEnv } from '../http.js';
import { getSettings, listHubs, listProducts, mapHub, mapProduct, mapPromo, mapUser } from '../services/repo.js';

const hubBodySchema = z.object({
  name: z.string().trim().min(2).max(80),
  address: z.string().trim().min(3).max(200),
  latitude: z.number().min(-90).max(90),
  longitude: z.number().min(-180).max(180),
  deliveryRadiusKm: z.number().min(1).max(60).default(15),
  isActive: z.boolean().default(true),
  sortOrder: z.number().int().default(0),
});

const promoBodySchema = z.object({
  description: z.string().trim().min(3).max(120),
  type: z.enum(['PERCENT_OFF', 'FIXED_OFF', 'FREE_DELIVERY']),
  value: z.number().int().min(0).max(1_000_000).default(0),
  minSpend: z.number().int().min(0).default(0),
  maxDiscount: z.number().int().min(0).nullish(),
  isActive: z.boolean().default(true),
  expiresAt: z.iso.datetime().nullish(),
});

const window = z.tuple([z.number().int().min(0).max(1440), z.number().int().min(0).max(1440)]).refine(([a, b]) => b > a, 'End must be after start');
const pricedOption = z.object({
  id: z.string().min(1).max(40),
  name: z.string().min(1).max(60),
  description: z.string().max(120).default(''),
  surcharge: z.number().int().min(0),
  allergens: z.array(z.enum(ALLERGENS)).optional(),
  isEggless: z.boolean().optional(),
});
const settingsSchema = z
  .object({
    bakeryName: z.string().min(1).max(60),
    packagingFee: z.number().int().min(0),
    cakeBoxFee: z.number().int().min(0),
    deliveryFee: z.number().int().min(0),
    freeDeliveryThreshold: z.number().int().min(0),
    pickupPrepMinutes: z.number().int().min(0).max(600),
    deliveryPrepMinutes: z.number().int().min(0).max(600),
    leadTimeHours: z.number().int().min(0).max(168),
    afternoonBakeStartMinute: z.number().int().min(0).max(1440),
    bookingDays: z.number().int().min(1).max(14),
    pickupWindows: z.array(window).min(1),
    deliveryWindows: z.array(window).min(1),
    stampsPerReward: z.number().int().min(1).max(50),
    stampQualifyingTotal: z.number().int().min(0),
    egglessSurcharge: z.number().int().min(0),
    maxPreOrderQuantity: z.number().int().min(1).max(100),
    cakeSizes: z
      .array(z.object({ id: z.string(), label: z.string(), weightKg: z.number().positive(), servings: z.number().int().positive(), multiplier: z.number().positive(), tiers: z.number().int().positive() }))
      .min(1),
    sponges: z.array(pricedOption).min(1),
    fillings: z.array(pricedOption).min(1),
    frostings: z.array(pricedOption).min(1),
    addOns: z.array(z.object({ id: z.string().min(1).max(40), name: z.string().min(1).max(60), description: z.string().max(120).default(''), price: z.number().int().min(0) })),
  })
  .partial();

const userCreateSchema = z.object({
  email: z.email().transform((e) => e.trim().toLowerCase()),
  password: z.string().min(8).max(100),
  name: z.string().trim().min(2).max(80),
  phone: z.string().trim().max(20).nullish(),
  role: z.enum(['staff', 'admin']),
  hubId: z.string().nullish(),
});

const userPatchSchema = z.object({
  name: z.string().trim().min(2).max(80).optional(),
  phone: z.string().trim().max(20).nullish(),
  role: z.enum(['customer', 'staff', 'admin']).optional(),
  hubId: z.string().nullish(),
  isActive: z.boolean().optional(),
  password: z.string().min(8).max(100).optional(),
});

/** Owner tools: menu, branches, promos, business settings, team and reports. Admin only. */
export function adminRoutes(app: Hono<AppEnv>, deps: AppDeps) {
  const { sql, bus, auth } = deps;
  const admin = requireAuth(deps, ['admin']);

  // ── Menu ──
  app.get('/admin/products', admin, async (c) => c.json(await listProducts(sql, false)));

  app.post('/admin/products', admin, async (c) => {
    const input = await body(c, productBodySchema.extend({ id: slug }));
    const [exists] = await sql`select 1 from products where id = ${input.id}`;
    if (exists) throw conflict('A product with this id already exists');
    const [row] = await sql`insert into products ${sql({
      ...input,
      imageUrls: sql.json(input.imageUrls as never),
      allergens: sql.json(input.allergens as never),
      dietaryTags: sql.json(input.dietaryTags as never),
      nutrition: input.nutrition ? sql.json(input.nutrition as never) : null,
    } as never)} returning *`;
    await sql`insert into product_stock (product_id, hub_id) select ${input.id}, id from hubs on conflict do nothing`;
    await bus.publish({ type: 'catalog.updated' });
    return c.json(mapProduct(row), 201);
  });

  app.put('/admin/products/:id', admin, async (c) => {
    const input = await body(c, productBodySchema);
    const [row] = await sql`update products set ${sql({
      ...input,
      imageUrls: sql.json(input.imageUrls as never),
      allergens: sql.json(input.allergens as never),
      dietaryTags: sql.json(input.dietaryTags as never),
      nutrition: input.nutrition ? sql.json(input.nutrition as never) : null,
    } as never)}, updated_at = now() where id = ${c.req.param('id')} returning *`;
    if (!row) throw notFound('Product not found');
    await bus.publish({ type: 'catalog.updated' });
    return c.json(mapProduct(row));
  });

  /** Products are unlisted rather than deleted so past orders keep their history. */
  app.delete('/admin/products/:id', admin, async (c) => {
    const rows = await sql`update products set is_listed = false, updated_at = now() where id = ${c.req.param('id')} returning id`;
    if (!rows.length) throw notFound('Product not found');
    await bus.publish({ type: 'catalog.updated' });
    return c.json({ ok: true });
  });

  // ── Branches ──
  app.get('/admin/hubs', admin, async (c) => c.json(await listHubs(sql, true)));

  app.post('/admin/hubs', admin, async (c) => {
    const input = await body(c, hubBodySchema.extend({ id: slug }));
    const [exists] = await sql`select 1 from hubs where id = ${input.id}`;
    if (exists) throw conflict('A branch with this id already exists');
    const [row] = await sql`insert into hubs ${sql(input as never)} returning *`;
    await sql`insert into product_stock (product_id, hub_id) select id, ${input.id} from products on conflict do nothing`;
    await bus.publish({ type: 'hubs.updated' });
    return c.json(mapHub(row), 201);
  });

  app.put('/admin/hubs/:id', admin, async (c) => {
    const input = await body(c, hubBodySchema);
    const [row] = await sql`update hubs set ${sql(input as never)} where id = ${c.req.param('id')} returning *`;
    if (!row) throw notFound('Branch not found');
    await bus.publish({ type: 'hubs.updated' });
    return c.json(mapHub(row));
  });

  // ── Promo codes ──
  app.get('/admin/promos', admin, async (c) => c.json((await sql`select * from promo_codes order by created_at desc`).map(mapPromo)));

  app.post('/admin/promos', admin, async (c) => {
    const input = await body(c, promoBodySchema.extend({ code: z.string().trim().toUpperCase().regex(/^[A-Z0-9]{3,20}$/, '3–20 letters or numbers') }));
    const [exists] = await sql`select 1 from promo_codes where code = ${input.code}`;
    if (exists) throw conflict('That code already exists');
    const [row] = await sql`insert into promo_codes ${sql({ ...input, expiresAt: input.expiresAt ? new Date(input.expiresAt) : null } as never)} returning *`;
    await bus.publish({ type: 'promos.updated' });
    return c.json(mapPromo(row), 201);
  });

  app.put('/admin/promos/:code', admin, async (c) => {
    const input = await body(c, promoBodySchema);
    const [row] = await sql`update promo_codes set ${sql({ ...input, expiresAt: input.expiresAt ? new Date(input.expiresAt) : null } as never)}
                            where code = ${c.req.param('code').toUpperCase()} returning *`;
    if (!row) throw notFound('Promo code not found');
    await bus.publish({ type: 'promos.updated' });
    return c.json(mapPromo(row));
  });

  // ── Business settings ──
  app.get('/admin/settings', admin, async (c) => c.json(await getSettings(sql)));

  app.put('/admin/settings', admin, async (c) => {
    const patch = await body(c, settingsSchema);
    const merged = { ...(await getSettings(sql)), ...patch };
    await sql`insert into settings (key, value) values ('business', ${sql.json(merged as never)})
              on conflict (key) do update set value = excluded.value, updated_at = now()`;
    await bus.publish({ type: 'settings.updated' });
    return c.json(merged);
  });

  // ── Team ──
  app.get('/admin/users', admin, async (c) => {
    const role = c.req.query('role');
    const rows = role
      ? await sql`select * from users where role = ${role} order by created_at desc limit 500`
      : await sql`select * from users where role in ('staff', 'admin') order by role, name`;
    return c.json(rows.map(mapUser));
  });

  app.post('/admin/users', admin, async (c) => {
    const input = await body(c, userCreateSchema);
    const [exists] = await sql`select 1 from users where email = ${input.email}`;
    if (exists) throw conflict('An account with this email already exists', 'EMAIL_TAKEN');
    if (input.hubId) {
      const [hub] = await sql`select 1 from hubs where id = ${input.hubId}`;
      if (!hub) throw badRequest('Unknown branch', 'INVALID_HUB');
    }
    const [row] = await sql`insert into users ${sql({
      email: input.email,
      passwordHash: await auth.hashPassword(input.password),
      name: input.name,
      phone: input.phone || null,
      role: input.role,
      hubId: input.hubId || null,
    } as never)} returning *`;
    return c.json(mapUser(row), 201);
  });

  app.patch('/admin/users/:id', admin, async (c) => {
    const input = await body(c, userPatchSchema);
    const id = c.req.param('id');
    const me = c.get('user');
    if (id === me.id && (input.isActive === false || (input.role && input.role !== 'admin'))) {
      throw badRequest("You can't deactivate or demote your own account");
    }
    const patch: Record<string, unknown> = {};
    if (input.name !== undefined) patch.name = input.name;
    if (input.phone !== undefined) patch.phone = input.phone || null;
    if (input.role !== undefined) patch.role = input.role;
    if (input.hubId !== undefined) patch.hubId = input.hubId || null;
    if (input.isActive !== undefined) patch.isActive = input.isActive;
    if (input.password !== undefined) patch.passwordHash = await auth.hashPassword(input.password);
    if (Object.keys(patch).length === 0) throw badRequest('Nothing to update');
    const [row] = await sql`update users set ${sql(patch as never)} where id = ${id} returning *`;
    if (!row) throw notFound('User not found');
    return c.json(mapUser(row));
  });

  // ── Reports ──
  app.get('/admin/reports', admin, async (c) => {
    const settings = await getSettings(sql);
    const tz = settings.timezone;
    const to = c.req.query('to') ?? todayIn(tz, deps.now());
    const from = c.req.query('from') ?? addDays(to, -6);
    if (!/^\d{4}-\d{2}-\d{2}$/.test(from) || !/^\d{4}-\d{2}-\d{2}$/.test(to)) throw badRequest('Dates must be YYYY-MM-DD');
    const hubId = c.req.query('hubId') || null;
    const hubFilter = hubId ? sql`and o.hub_id = ${hubId}` : sql``;
    const range = sql`(o.created_at at time zone ${tz})::date between ${from}::date and ${to}::date`;

    const [totals] = await sql`
      select count(*) filter (where status <> 'CANCELLED') as orders,
             coalesce(sum((pricing->>'total')::int) filter (where status <> 'CANCELLED'), 0) as revenue,
             count(*) filter (where status = 'CANCELLED') as cancelled,
             count(*) filter (where fulfillment_type = 'DELIVERY' and status <> 'CANCELLED') as deliveries,
             count(distinct user_id) filter (where status <> 'CANCELLED') as customers
      from orders o where ${range} ${hubFilter}`;
    const byDay = await sql`
      select to_char((o.created_at at time zone ${tz})::date, 'YYYY-MM-DD') as day,
             count(*) as orders, coalesce(sum((pricing->>'total')::int), 0) as revenue
      from orders o where ${range} and status <> 'CANCELLED' ${hubFilter}
      group by 1 order by 1`;
    const byHub = await sql`
      select h.id as hub_id, h.name as hub_name, count(o.id) as orders, coalesce(sum((o.pricing->>'total')::int), 0) as revenue
      from orders o join hubs h on h.id = o.hub_id
      where ${range} and o.status <> 'CANCELLED' ${hubFilter}
      group by h.id, h.name order by revenue desc`;
    const topProducts = await sql`
      select l.product_id, l.product_name, sum(l.quantity) as quantity, sum(l.quantity * l.unit_price) as revenue
      from order_lines l join orders o on o.id = l.order_id
      where ${range} and o.status <> 'CANCELLED' and l.line_type = 'PRODUCT' ${hubFilter}
      group by l.product_id, l.product_name order by quantity desc limit 10`;

    const orders = Number(totals.orders);
    const revenue = Number(totals.revenue);
    return c.json({
      from,
      to,
      hubId,
      totals: {
        orders,
        revenue,
        averageOrder: orders ? Math.round(revenue / orders) : 0,
        cancelled: Number(totals.cancelled),
        deliveries: Number(totals.deliveries),
        customers: Number(totals.customers),
      },
      byDay: byDay.map((r) => ({ day: r.day, orders: Number(r.orders), revenue: Number(r.revenue) })),
      byHub: byHub.map((r) => ({ hubId: r.hubId, hubName: r.hubName, orders: Number(r.orders), revenue: Number(r.revenue) })),
      topProducts: topProducts.map((r) => ({ productId: r.productId, name: r.productName, quantity: Number(r.quantity), revenue: Number(r.revenue) })),
    });
  });
}
