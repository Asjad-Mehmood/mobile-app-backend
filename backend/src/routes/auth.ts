import type { Hono } from 'hono';
import { z } from 'zod';
import { ApiError, badRequest, conflict, unauthorized } from '../errors.js';
import { body, clientIp, requireAuth, type AppDeps, type AppEnv } from '../http.js';
import { mapUser } from '../services/repo.js';

const registerSchema = z.object({
  email: z.email().transform((e) => e.trim().toLowerCase()),
  password: z.string().min(8, 'Use at least 8 characters').max(100),
  name: z.string().trim().min(2).max(80),
  phone: z.string().trim().max(20).nullish(),
});

const loginSchema = z.object({
  email: z.string().transform((e) => e.trim().toLowerCase()),
  password: z.string().min(1).max(100),
});

/** Simple in-memory limiter: 10 login attempts per email+IP per 15 minutes. */
const attempts = new Map<string, { count: number; resetAt: number }>();
function throttle(key: string, now: number) {
  const entry = attempts.get(key);
  if (!entry || entry.resetAt < now) {
    attempts.set(key, { count: 1, resetAt: now + 15 * 60_000 });
    return;
  }
  entry.count++;
  if (entry.count > 10) throw new ApiError(429, 'TOO_MANY_ATTEMPTS', 'Too many attempts — try again in a few minutes');
}

export function authRoutes(app: Hono<AppEnv>, deps: AppDeps) {
  const { sql, auth } = deps;

  app.post('/auth/register', async (c) => {
    const input = await body(c, registerSchema);
    const [existing] = await sql`select 1 from users where email = ${input.email}`;
    if (existing) throw conflict('An account with this email already exists — try signing in', 'EMAIL_TAKEN');
    const [row] = await sql`insert into users ${sql({
      email: input.email,
      passwordHash: await auth.hashPassword(input.password),
      name: input.name,
      phone: input.phone || null,
      role: 'customer',
    } as never)} returning *`;
    const user = mapUser(row);
    return c.json({ token: await auth.sign(user), user }, 201);
  });

  app.post('/auth/login', async (c) => {
    const input = await body(c, loginSchema);
    throttle(`${input.email}|${clientIp(c)}`, deps.now());
    const [row] = await sql`select * from users where email = ${input.email}`;
    if (!row || !(await auth.verifyPassword(input.password, row.passwordHash))) {
      throw unauthorized('Email or password is incorrect');
    }
    if (!row.isActive) throw unauthorized('This account has been deactivated');
    const user = mapUser(row);
    return c.json({ token: await auth.sign(user), user });
  });

  app.get('/auth/me', requireAuth(deps), (c) => c.json({ user: c.get('user') }));

  app.patch('/auth/me', requireAuth(deps), async (c) => {
    const input = await body(c, z.object({ name: z.string().trim().min(2).max(80).optional(), phone: z.string().trim().max(20).nullish() }));
    const user = c.get('user');
    const [row] = await sql`update users set
        name = coalesce(${input.name ?? null}, name),
        phone = ${input.phone === undefined ? user.phone : input.phone || null}
      where id = ${user.id} returning *`;
    return c.json({ user: mapUser(row) });
  });

  app.post('/auth/password', requireAuth(deps), async (c) => {
    const input = await body(c, z.object({ currentPassword: z.string(), newPassword: z.string().min(8).max(100) }));
    const [row] = await sql`select password_hash from users where id = ${c.get('user').id}`;
    if (!(await auth.verifyPassword(input.currentPassword, row.passwordHash))) throw badRequest('Current password is incorrect');
    await sql`update users set password_hash = ${await auth.hashPassword(input.newPassword)} where id = ${c.get('user').id}`;
    return c.json({ ok: true });
  });
}
