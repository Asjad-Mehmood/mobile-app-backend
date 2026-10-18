import { Hono } from 'hono';
import { cors } from 'hono/cors';
import { logger } from 'hono/logger';
import { ApiError } from './errors.js';
import type { AppDeps, AppEnv } from './http.js';
import { adminRoutes } from './routes/admin.js';
import { authRoutes } from './routes/auth.js';
import { customerRoutes } from './routes/customer.js';
import { publicRoutes } from './routes/public.js';
import { staffRoutes } from './routes/staff.js';

export function createApp(deps: AppDeps, opts: { log?: boolean } = {}): Hono<AppEnv> {
  const app = new Hono<AppEnv>();
  if (opts.log) app.use(logger());
  app.use(cors());

  app.onError((err, c) => {
    if (err instanceof ApiError) return c.json({ error: { code: err.code, message: err.message } }, err.status);
    const pgCode = (err as { code?: string }).code;
    if (pgCode === '23505') return c.json({ error: { code: 'CONFLICT', message: 'That already exists' } }, 409);
    if (pgCode === '23503') return c.json({ error: { code: 'INVALID_REFERENCE', message: 'A referenced item does not exist' } }, 400);
    console.error(err);
    return c.json({ error: { code: 'INTERNAL', message: 'Something went wrong — please try again' } }, 500);
  });
  app.notFound((c) => c.json({ error: { code: 'NOT_FOUND', message: 'Not found' } }, 404));

  publicRoutes(app, deps);
  authRoutes(app, deps);
  customerRoutes(app, deps);
  staffRoutes(app, deps);
  adminRoutes(app, deps);
  return app;
}
