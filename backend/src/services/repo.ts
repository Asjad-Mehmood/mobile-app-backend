import type { Db } from '../db.js';
import { DEFAULT_SETTINGS, type BusinessSettings, type Hub, type Product, type ProductStock, type Promo } from '../domain/types.js';
import type { AuthUser } from './auth.js';

const iso = (d: unknown): string | null => (d instanceof Date ? d.toISOString() : d == null ? null : String(d));

export function mapProduct(r: Record<string, any>): Product {
  return {
    id: r.id,
    name: r.name,
    subtitle: r.subtitle,
    description: r.description,
    crumbNotes: r.crumbNotes ?? null,
    reheatingTip: r.reheatingTip ?? null,
    basePrice: Number(r.basePrice),
    category: r.category,
    imageUrls: r.imageUrls ?? [],
    allergens: r.allergens ?? [],
    dietaryTags: r.dietaryTags ?? [],
    bakeSchedule: r.bakeSchedule,
    isCustomizableCake: r.isCustomizableCake,
    nutrition: r.nutrition ?? null,
    sortOrder: r.sortOrder,
    isListed: r.isListed,
  };
}

export function mapHub(r: Record<string, any>): Hub {
  return {
    id: r.id,
    name: r.name,
    address: r.address,
    latitude: Number(r.latitude),
    longitude: Number(r.longitude),
    deliveryRadiusKm: Number(r.deliveryRadiusKm),
    isActive: r.isActive,
    sortOrder: r.sortOrder,
  };
}

export function mapPromo(r: Record<string, any>): Promo {
  return {
    code: r.code,
    description: r.description,
    type: r.type,
    value: r.value,
    minSpend: r.minSpend,
    maxDiscount: r.maxDiscount ?? null,
    isActive: r.isActive,
    expiresAt: iso(r.expiresAt),
  };
}

export function mapUser(r: Record<string, any>): AuthUser & { isActive: boolean; createdAt: string | null } {
  return {
    id: r.id,
    email: r.email,
    name: r.name,
    phone: r.phone ?? null,
    role: r.role,
    hubId: r.hubId ?? null,
    isActive: r.isActive,
    createdAt: iso(r.createdAt),
  };
}

export async function getSettings(db: Db): Promise<BusinessSettings> {
  const [row] = await db<{ value: Partial<BusinessSettings> }[]>`select value from settings where key = 'business'`;
  return { ...DEFAULT_SETTINGS, ...(row?.value ?? {}) };
}

export async function listHubs(db: Db, includeInactive = false): Promise<Hub[]> {
  const rows = includeInactive
    ? await db`select * from hubs order by sort_order, name`
    : await db`select * from hubs where is_active order by sort_order, name`;
  return rows.map(mapHub);
}

export async function getHub(db: Db, id: string): Promise<Hub | null> {
  const [row] = await db`select * from hubs where id = ${id}`;
  return row ? mapHub(row) : null;
}

export async function listProducts(db: Db, listedOnly = true): Promise<Product[]> {
  const rows = listedOnly
    ? await db`select * from products where is_listed order by sort_order, name`
    : await db`select * from products order by sort_order, name`;
  return rows.map(mapProduct);
}

export async function getProductsByIds(db: Db, ids: string[]): Promise<Map<string, Product>> {
  if (ids.length === 0) return new Map();
  const rows = await db`select * from products where id in ${db(ids)}`;
  return new Map(rows.map((r) => [r.id as string, mapProduct(r)]));
}

export async function stockForHub(db: Db, hubId: string): Promise<Map<string, ProductStock>> {
  const rows = await db`select * from product_stock where hub_id = ${hubId}`;
  return new Map(
    rows.map((r) => [
      r.productId as string,
      { remainingBatchStock: r.remainingBatchStock, currentBatchNumber: r.currentBatchNumber, nextBatchReadyAt: iso(r.nextBatchReadyAt) },
    ]),
  );
}

export const EMPTY_STOCK: ProductStock = { remainingBatchStock: 0, currentBatchNumber: 1, nextBatchReadyAt: null };

export async function getPromo(db: Db, code: string): Promise<Promo | null> {
  const [row] = await db`select * from promo_codes where upper(code) = upper(${code.trim()})`;
  return row ? mapPromo(row) : null;
}

export async function loyaltyCounts(db: Db, userId: string): Promise<{ earned: number; redeemed: number }> {
  const [row] = await db<{ earned: string; redeemed: string }[]>`
    select coalesce(sum(stamps_earned), 0) as earned,
           count(*) filter (where loyalty_redeemed) as redeemed
    from orders where user_id = ${userId} and status <> 'CANCELLED'`;
  return { earned: Number(row.earned), redeemed: Number(row.redeemed) };
}

export { iso };
