import type { Hono } from 'hono';
import { z } from 'zod';
import { checkZone } from '../domain/rules.js';
import { badRequest } from '../errors.js';
import { body, type AppDeps, type AppEnv } from '../http.js';
import { EMPTY_STOCK, getSettings, listHubs, listProducts, stockForHub } from '../services/repo.js';

/** No sign-in needed: menu, branches, settings and the delivery-zone check. */
export function publicRoutes(app: Hono<AppEnv>, deps: AppDeps) {
  const { sql } = deps;

  app.get('/health', (c) => c.json({ ok: true, time: new Date(deps.now()).toISOString() }));

  app.get('/config', async (c) => c.json(await getSettings(sql)));

  app.get('/hubs', async (c) => c.json(await listHubs(sql)));

  /** Listed products with live batch stock for one branch. */
  app.get('/catalog', async (c) => {
    const hubs = await listHubs(sql);
    const hubId = c.req.query('hubId') ?? hubs[0]?.id;
    if (!hubId || !hubs.some((h) => h.id === hubId)) throw badRequest('Unknown branch', 'INVALID_HUB');
    const [products, stock] = await Promise.all([listProducts(sql), stockForHub(sql, hubId)]);
    return c.json({
      hubId,
      serverTime: new Date(deps.now()).toISOString(),
      products: products.map((p) => ({ ...p, stock: stock.get(p.id) ?? EMPTY_STOCK })),
    });
  });

  app.post('/zone-check', async (c) => {
    const input = await body(c, z.object({ latitude: z.number().min(-90).max(90), longitude: z.number().min(-180).max(180) }));
    const result = checkZone(input.latitude, input.longitude, await listHubs(sql));
    return c.json(result);
  });
}
