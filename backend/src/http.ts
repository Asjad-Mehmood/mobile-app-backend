import type { Context, MiddlewareHandler } from 'hono';
import { z } from 'zod';
import type { Sql } from './db.js';
import type { Role } from './domain/types.js';
import { ALLERGENS, BAKE_SCHEDULES, CATEGORIES, DIETARY_TAGS } from './domain/types.js';
import { badRequest, forbidden, unauthorized } from './errors.js';
import type { AuthService, AuthUser } from './services/auth.js';
import type { EventBus } from './services/events.js';
import { mapUser } from './services/repo.js';

export interface AppDeps {
  sql: Sql;
  bus: EventBus;
  auth: AuthService;
  now: () => number;
}

export type AppEnv = { Variables: { user: AuthUser } };

/** Bearer-token auth. Role and active status are re-read every request, so changes apply immediately. */
export function requireAuth(deps: AppDeps, roles?: Role[]): MiddlewareHandler<AppEnv> {
  return async (c, next) => {
    const header = c.req.header('authorization') ?? '';
    const token = header.startsWith('Bearer ') ? header.slice(7) : null;
    if (!token) throw unauthorized();
    const id = await deps.auth.verify(token);
    if (!id) throw unauthorized('Your session has expired — please sign in again');
    const [row] = await deps.sql`select * from users where id = ${id}`;
    if (!row || !row.isActive) throw unauthorized('This account is no longer active');
    const user = mapUser(row);
    if (roles && !roles.includes(user.role)) throw forbidden();
    c.set('user', user);
    await next();
  };
}

export async function body<T>(c: Context, schema: z.ZodType<T>): Promise<T> {
  let json: unknown;
  try {
    json = await c.req.json();
  } catch {
    throw badRequest('Request body must be JSON');
  }
  const result = schema.safeParse(json);
  if (!result.success) {
    const issue = result.error.issues[0];
    const field = issue.path.join('.');
    throw badRequest(field ? `${field}: ${issue.message}` : issue.message, 'VALIDATION');
  }
  return result.data;
}

// ── Shared schemas ─────────────────────────────────────────────────────────────

export const cakeChoiceSchema = z.object({
  sizeId: z.string(),
  spongeId: z.string(),
  fillingId: z.string(),
  frostingId: z.string(),
  eggless: z.boolean().default(false),
  message: z.string().max(100).default(''),
  fontId: z.string().default('SCRIPT'),
});

const itemSchema = z.object({
  productId: z.string().min(1),
  quantity: z.number().int().min(1).max(50),
  customization: cakeChoiceSchema.nullish(),
  specialInstructions: z.string().max(200).nullish(),
});

export const checkoutSchema = z.object({
  hubId: z.string().min(1),
  fulfillmentType: z.enum(['PICKUP', 'DELIVERY']),
  slot: z.object({ date: z.string().regex(/^\d{4}-\d{2}-\d{2}$/), startMinute: z.number().int().min(0).max(1440) }).nullish(),
  deliveryAddress: z.string().max(300).nullish(),
  deliveryLat: z.number().min(-90).max(90).nullish(),
  deliveryLng: z.number().min(-180).max(180).nullish(),
  paymentMethod: z.enum(['CASH_ON_DELIVERY', 'CARD']).default('CASH_ON_DELIVERY'),
  promoCode: z.string().max(40).nullish(),
  redeemReward: z.boolean().default(false),
  addOns: z.array(z.string()).max(10).default([]),
  items: z.array(itemSchema).min(1).max(50),
  customerNote: z.string().max(300).nullish(),
});

export const slotsSchema = z.object({
  fulfillmentType: z.enum(['PICKUP', 'DELIVERY']),
  items: z.array(itemSchema.pick({ productId: true, customization: true })).max(50).default([]),
});

export const nutritionSchema = z.object({
  servingSize: z.string().max(60),
  calories: z.number().int().min(0),
  fatGrams: z.number().min(0),
  carbsGrams: z.number().min(0),
  sugarGrams: z.number().min(0),
  proteinGrams: z.number().min(0),
});

export const productBodySchema = z.object({
  name: z.string().trim().min(2).max(80),
  subtitle: z.string().max(120).default(''),
  description: z.string().max(1000).default(''),
  crumbNotes: z.string().max(300).nullish(),
  reheatingTip: z.string().max(300).nullish(),
  basePrice: z.number().int().min(0).max(1_000_000),
  category: z.enum(CATEGORIES),
  imageUrls: z.array(z.url()).max(8).default([]),
  allergens: z.array(z.enum(ALLERGENS)).default([]),
  dietaryTags: z.array(z.enum(DIETARY_TAGS)).default([]),
  bakeSchedule: z.enum(BAKE_SCHEDULES).default('ALL_DAY'),
  isCustomizableCake: z.boolean().default(false),
  nutrition: nutritionSchema.nullish(),
  sortOrder: z.number().int().default(0),
  isListed: z.boolean().default(true),
});

export const slug = z.string().regex(/^[a-z0-9][a-z0-9-]{1,59}$/, 'Use lowercase letters, numbers and dashes');

export function clientIp(c: Context): string {
  return c.req.header('x-forwarded-for')?.split(',')[0].trim() || 'local';
}
