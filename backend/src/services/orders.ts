import { randomInt } from 'node:crypto';
import type { Db, Sql } from '../db.js';
import {
  buildSlotDays,
  canTransition,
  checkZone,
  distanceKm,
  goodsTotal,
  isMadeToOrder,
  loyaltyStatus,
  orderPricing,
  promoProblem,
  resolveCake,
  rewardValue,
  slotProblem,
  type CakeChoice,
  type LoyaltyStatus,
  type PricedLine,
  type Pricing,
  type ResolvedCake,
  type SlotDay,
  type SlotItem,
  windowsFor,
} from '../domain/rules.js';
import { todayIn, windowLabel } from '../domain/time.js';
import type { AddOnOption, BusinessSettings, FulfillmentType, Hub, OrderStatus, PaymentMethod, Product, Promo } from '../domain/types.js';
import { badRequest, conflict, forbidden, notFound, unprocessable } from '../errors.js';
import type { AuthUser } from './auth.js';
import type { EventBus } from './events.js';
import { getHub, getProductsByIds, getPromo, getSettings, iso, listHubs, loyaltyCounts, stockForHub } from './repo.js';

export interface CheckoutItemInput {
  productId: string;
  quantity: number;
  customization?: CakeChoice | null;
  specialInstructions?: string | null;
}

export interface CheckoutInput {
  hubId: string;
  fulfillmentType: FulfillmentType;
  slot?: { date: string; startMinute: number } | null;
  deliveryAddress?: string | null;
  deliveryLat?: number | null;
  deliveryLng?: number | null;
  paymentMethod: PaymentMethod;
  promoCode?: string | null;
  redeemReward: boolean;
  addOns: string[];
  items: CheckoutItemInput[];
  customerNote?: string | null;
}

export interface PreparedLine extends PricedLine {
  product: Product;
  customization: ResolvedCake | null;
  specialInstructions: string | null;
  lineTotal: number;
}

export interface StockIssue {
  productId: string;
  name: string;
  available: number;
  requested: number;
}

export interface Prepared {
  settings: BusinessSettings;
  hub: Hub;
  lines: PreparedLine[];
  addOns: AddOnOption[];
  promo: Promo | null;
  promoError: string | null;
  loyalty: LoyaltyStatus;
  rewardValue: number | null;
  redeem: boolean;
  pricing: Pricing;
  slot: { date: string; startMinute: number; endMinute: number; label: string } | null;
  slotError: string | null;
  deliveryError: string | null;
  stockIssues: StockIssue[];
  slotIsToday: boolean;
}

/** Everything checkout needs, computed server-side. Shared by quote and place so they never disagree. */
export async function prepareOrder(db: Db, user: AuthUser, input: CheckoutInput, nowMs: number): Promise<Prepared> {
  const settings = await getSettings(db);
  const hub = await getHub(db, input.hubId);
  if (!hub || !hub.isActive) throw badRequest('Choose one of our bakeries', 'INVALID_HUB');
  if (input.items.length === 0) throw badRequest('Your basket is empty', 'EMPTY_BASKET');

  const products = await getProductsByIds(db, [...new Set(input.items.map((i) => i.productId))]);
  const lines: PreparedLine[] = input.items.map((item) => {
    const product = products.get(item.productId);
    if (!product || !product.isListed) throw conflict(`${product?.name ?? 'An item'} is no longer on the menu`, 'PRODUCT_UNAVAILABLE');
    let customization: ResolvedCake | null = null;
    if (product.isCustomizableCake) {
      if (!item.customization) throw badRequest(`Design your ${product.name} before ordering`, 'CAKE_NOT_CONFIGURED');
      customization = resolveCake(settings, product.basePrice, product.allergens, item.customization);
    } else if (item.customization) {
      throw badRequest(`${product.name} can't be customised`, 'NOT_CUSTOMIZABLE');
    }
    const madeToOrder = isMadeToOrder({ isCustom: customization != null, bakeSchedule: product.bakeSchedule, category: product.category });
    if (madeToOrder && item.quantity > settings.maxPreOrderQuantity) {
      throw badRequest(`You can pre-order up to ${settings.maxPreOrderQuantity} of ${product.name}`, 'QUANTITY_LIMIT');
    }
    const unitPrice = product.basePrice + (customization?.extraPrice ?? 0);
    return {
      productId: product.id,
      name: product.name,
      category: product.category,
      bakeSchedule: product.bakeSchedule,
      basePrice: product.basePrice,
      unitPrice,
      quantity: item.quantity,
      isCustom: customization != null,
      product,
      customization,
      specialInstructions: item.specialInstructions?.trim() || null,
      lineTotal: unitPrice * item.quantity,
    };
  });

  const addOns = input.addOns.map((id) => {
    const addOn = settings.addOns.find((a) => a.id === id);
    if (!addOn) throw badRequest('That add-on is no longer available', 'INVALID_ADDON');
    return addOn;
  });

  // Slot
  let slot: Prepared['slot'] = null;
  let slotError: string | null = null;
  const slotItems: SlotItem[] = lines.map((l) => ({ bakeSchedule: l.bakeSchedule, isCustom: l.isCustom }));
  if (input.slot) {
    const window = windowsFor(settings, input.fulfillmentType).find(([s]) => s === input.slot!.startMinute);
    if (!window) {
      slotError = 'That time window is not offered';
    } else {
      slot = { date: input.slot.date, startMinute: window[0], endMinute: window[1], label: windowLabel(window[0], window[1]) };
      slotError = slotProblem(settings, input.fulfillmentType, slot.date, slot.startMinute, slotItems, nowMs);
    }
  }
  const slotIsToday = slot != null && slot.date === todayIn(settings.timezone, nowMs);

  // Delivery zone (checked against the chosen branch's radius)
  let deliveryError: string | null = null;
  if (input.fulfillmentType === 'DELIVERY') {
    if (!input.deliveryAddress?.trim() || input.deliveryLat == null || input.deliveryLng == null) {
      deliveryError = 'Add a delivery address to continue';
    } else {
      const d = distanceKm(input.deliveryLat, input.deliveryLng, hub.latitude, hub.longitude);
      if (d > hub.deliveryRadiusKm) {
        deliveryError = `That address is ${d.toFixed(1)} km from ${hub.name} — outside our ${hub.deliveryRadiusKm} km delivery radius`;
      }
    }
  }

  // Same-day batch stock (spec §7.2)
  const stock = await stockForHub(db, hub.id);
  const requested = new Map<string, number>();
  for (const l of lines) {
    if (isMadeToOrder(l)) continue;
    requested.set(l.productId, (requested.get(l.productId) ?? 0) + l.quantity);
  }
  const stockIssues: StockIssue[] = [];
  for (const [productId, qty] of requested) {
    const available = stock.get(productId)?.remainingBatchStock ?? 0;
    if (qty > available) stockIssues.push({ productId, name: products.get(productId)!.name, available, requested: qty });
  }

  // Loyalty
  const counts = await loyaltyCounts(db, user.id);
  const loyalty = loyaltyStatus(settings, counts.earned, counts.redeemed);
  const reward = loyalty.rewardsAvailable > 0 ? rewardValue(lines) : null;
  const redeem = input.redeemReward && reward != null;

  // Promo
  let promo: Promo | null = null;
  let promoError: string | null = null;
  if (input.promoCode?.trim()) {
    const candidate = await getPromo(db, input.promoCode);
    promoError = promoProblem(candidate, input.promoCode, goodsTotal(lines, addOns), input.fulfillmentType, nowMs);
    if (!promoError) promo = candidate;
  }

  const pricing = orderPricing(settings, lines, addOns, input.fulfillmentType, promo, redeem ? reward! : 0);

  return { settings, hub, lines, addOns, promo, promoError, loyalty, rewardValue: reward, redeem, pricing, slot, slotError, deliveryError, stockIssues, slotIsToday };
}

/** Client-facing summary of [prepareOrder] for the checkout screen. */
export function quoteView(p: Prepared) {
  const blocking =
    p.deliveryError ??
    (p.slot == null ? 'Choose a time slot' : p.slotError) ??
    (p.slotIsToday && p.stockIssues.length
      ? `Only ${p.stockIssues[0].available} ${p.stockIssues[0].name} left today — reduce it or pick a later day`
      : null) ??
    p.promoError;
  return {
    hubId: p.hub.id,
    pricing: p.pricing,
    lines: p.lines.map((l) => ({
      productId: l.productId,
      unitPrice: l.unitPrice,
      quantity: l.quantity,
      lineTotal: l.lineTotal,
      customization: l.customization,
    })),
    addOns: p.addOns,
    promo: p.promo ? { code: p.promo.code, description: p.promo.description } : null,
    promoError: p.promoError,
    loyalty: { ...p.loyalty, rewardValue: p.rewardValue, redeemed: p.redeem },
    slot: p.slot,
    slotError: p.slotError,
    deliveryError: p.deliveryError,
    stockIssues: p.stockIssues,
    blockingIssue: blocking,
    canPlace: blocking == null,
  };
}

const ID_ALPHABET = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
const newOrderId = () => 'CC-' + Array.from({ length: 6 }, () => ID_ALPHABET[randomInt(ID_ALPHABET.length)]).join('');

export async function placeOrder(sql: Sql, bus: EventBus, user: AuthUser, input: CheckoutInput, nowMs: number) {
  return sql.begin(async (tx) => {
    const p = await prepareOrder(tx, user, input, nowMs);
    if (p.deliveryError) throw unprocessable(p.deliveryError, 'DELIVERY_ADDRESS');
    if (!p.slot) throw unprocessable('Choose a time slot', 'SLOT_REQUIRED');
    if (p.slotError) throw unprocessable(`${p.slot.label} is unavailable: ${p.slotError.toLowerCase()}`, 'SLOT_UNAVAILABLE');
    if (p.promoError) throw unprocessable(p.promoError, 'PROMO_INVALID');

    // Reserve same-day stock under row locks so two customers can't buy the last croissant.
    const reserved: string[] = [];
    if (p.slotIsToday) {
      const needed = new Map<string, number>();
      for (const l of p.lines) if (!isMadeToOrder(l)) needed.set(l.productId, (needed.get(l.productId) ?? 0) + l.quantity);
      for (const [productId, qty] of needed) {
        const [row] = await tx`
          select remaining_batch_stock from product_stock
          where product_id = ${productId} and hub_id = ${p.hub.id} for update`;
        const available = row?.remainingBatchStock ?? 0;
        if (available < qty) {
          const name = p.lines.find((l) => l.productId === productId)!.name;
          throw conflict(`Only ${available} ${name} left today — reduce it or pick a later day`, 'OUT_OF_STOCK');
        }
        await tx`update product_stock set remaining_batch_stock = remaining_batch_stock - ${qty}, updated_at = now()
                 where product_id = ${productId} and hub_id = ${p.hub.id}`;
        reserved.push(productId);
      }
    }

    let id = newOrderId();
    while ((await tx`select 1 from orders where id = ${id}`).length) id = newOrderId();
    const stamps = p.pricing.total >= p.settings.stampQualifyingTotal ? 1 : 0;
    const now = new Date(nowMs).toISOString();

    await tx`insert into orders ${tx({
      id,
      userId: user.id,
      hubId: p.hub.id,
      status: 'ORDER_CONFIRMED',
      fulfillmentType: input.fulfillmentType,
      slotDate: p.slot.date,
      slotStartMinute: p.slot.startMinute,
      slotEndMinute: p.slot.endMinute,
      slotLabel: p.slot.label,
      deliveryAddress: input.fulfillmentType === 'DELIVERY' ? input.deliveryAddress!.trim() : null,
      deliveryLat: input.fulfillmentType === 'DELIVERY' ? input.deliveryLat! : null,
      deliveryLng: input.fulfillmentType === 'DELIVERY' ? input.deliveryLng! : null,
      paymentMethod: input.paymentMethod,
      promoCode: p.promo?.code ?? null,
      pricing: tx.json(p.pricing as never),
      pickupCode: input.fulfillmentType === 'PICKUP' ? 'PU-' + randomInt(1000, 10000) : null,
      stampsEarned: stamps,
      loyaltyRedeemed: p.redeem,
      stockReserved: reserved.length > 0,
      statusHistory: tx.json([{ status: 'ORDER_CONFIRMED', at: now, by: 'customer' }] as never),
      customerNote: input.customerNote?.trim() || null,
    } as never)}`;

    const lineRows = [
      ...p.lines.map((l) => ({
        orderId: id,
        lineType: 'PRODUCT',
        productId: l.productId,
        productName: l.name,
        imageUrl: l.product.imageUrls[0] ?? null,
        category: l.category,
        quantity: l.quantity,
        unitPrice: l.unitPrice,
        customization: l.customization ? tx.json(l.customization as never) : null,
        specialInstructions: l.specialInstructions,
      })),
      ...p.addOns.map((a) => ({
        orderId: id,
        lineType: 'ADDON',
        productId: a.id,
        productName: a.name,
        imageUrl: null,
        category: null,
        quantity: 1,
        unitPrice: a.price,
        customization: null,
        specialInstructions: null,
      })),
    ];
    await tx`insert into order_lines ${tx(lineRows as never)}`;

    await bus.publish({ type: 'order.created', orderId: id, hubId: p.hub.id, userId: user.id, status: 'ORDER_CONFIRMED' }, tx);
    if (reserved.length) await bus.publish({ type: 'stock.updated', hubId: p.hub.id, productIds: reserved }, tx);
    return (await getOrder(tx, id))!;
  });
}

// ── Reading orders ────────────────────────────────────────────────────────────

export function mapOrder(r: Record<string, any>, lines: Record<string, any>[]) {
  return {
    id: r.id,
    userId: r.userId,
    customer: r.customerName ? { name: r.customerName, email: r.customerEmail, phone: r.customerPhone ?? null } : undefined,
    hubId: r.hubId,
    hubName: r.hubName,
    status: r.status as OrderStatus,
    fulfillmentType: r.fulfillmentType as FulfillmentType,
    slot: {
      date: r.slotDate instanceof Date ? r.slotDate.toISOString().slice(0, 10) : String(r.slotDate).slice(0, 10),
      startMinute: r.slotStartMinute,
      endMinute: r.slotEndMinute,
      label: r.slotLabel,
    },
    deliveryAddress: r.deliveryAddress,
    deliveryLat: r.deliveryLat,
    deliveryLng: r.deliveryLng,
    paymentMethod: r.paymentMethod,
    promoCode: r.promoCode,
    pricing: r.pricing as Pricing,
    pickupCode: r.pickupCode,
    stampsEarned: r.stampsEarned,
    loyaltyRedeemed: r.loyaltyRedeemed,
    statusHistory: r.statusHistory,
    customerNote: r.customerNote,
    createdAt: iso(r.createdAt),
    updatedAt: iso(r.updatedAt),
    lines: lines
      .filter((l) => l.orderId === r.id)
      .map((l) => ({
        id: Number(l.id),
        lineType: l.lineType,
        productId: l.productId,
        productName: l.productName,
        imageUrl: l.imageUrl,
        category: l.category,
        quantity: l.quantity,
        unitPrice: l.unitPrice,
        lineTotal: l.unitPrice * l.quantity,
        customization: l.customization,
        specialInstructions: l.specialInstructions,
      })),
  };
}

export type OrderView = ReturnType<typeof mapOrder>;

const ORDER_SELECT = (db: Db) => db`
  select o.*, h.name as hub_name, u.name as customer_name, u.email as customer_email, u.phone as customer_phone
  from orders o join hubs h on h.id = o.hub_id join users u on u.id = o.user_id`;

async function withLines(db: Db, rows: Record<string, any>[]): Promise<OrderView[]> {
  if (rows.length === 0) return [];
  const lines = await db`select * from order_lines where order_id in ${db(rows.map((r) => r.id))} order by id`;
  return rows.map((r) => mapOrder(r, lines));
}

export async function getOrder(db: Db, id: string): Promise<OrderView | null> {
  const rows = await db`${ORDER_SELECT(db)} where o.id = ${id}`;
  return (await withLines(db, rows))[0] ?? null;
}

export async function listOrdersForUser(db: Db, userId: string): Promise<OrderView[]> {
  const rows = await db`${ORDER_SELECT(db)} where o.user_id = ${userId} order by o.created_at desc limit 100`;
  return withLines(db, rows);
}

export async function listOrdersForStaff(
  db: Db,
  opts: { hubId: string | null; scope: 'active' | 'today' | 'all'; tz: string; nowMs: number },
): Promise<OrderView[]> {
  const hubFilter = opts.hubId ? db`and o.hub_id = ${opts.hubId}` : db``;
  const today = todayIn(opts.tz, opts.nowMs);
  const scopeFilter =
    opts.scope === 'active'
      ? db`and o.status not in ('COMPLETED', 'CANCELLED')`
      : opts.scope === 'today'
        ? db`and o.slot_date = ${today}`
        : db``;
  const rows = await db`${ORDER_SELECT(db)} where true ${hubFilter} ${scopeFilter}
    order by o.slot_date, o.slot_start_minute, o.created_at limit 300`;
  return withLines(db, rows);
}

export function canSeeOrder(user: AuthUser, order: { userId: string; hubId: string }): boolean {
  if (user.role === 'admin') return true;
  if (user.role === 'staff') return user.hubId == null || user.hubId === order.hubId;
  return order.userId === user.id;
}

// ── Status changes ────────────────────────────────────────────────────────────

export async function changeStatus(
  sql: Sql,
  bus: EventBus,
  actor: AuthUser,
  orderId: string,
  to: OrderStatus,
  nowMs: number,
  reason?: string,
) {
  return sql.begin(async (tx) => {
    const [order] = await tx`select * from orders where id = ${orderId} for update`;
    if (!order) throw notFound('Order not found');
    if (actor.role === 'customer') {
      if (order.userId !== actor.id) throw notFound('Order not found');
      if (to !== 'CANCELLED' || order.status !== 'ORDER_CONFIRMED') {
        throw conflict('This order is already being prepared — please contact the bakery', 'TOO_LATE_TO_CANCEL');
      }
    } else if (actor.role === 'staff' && actor.hubId && actor.hubId !== order.hubId) {
      throw forbidden('This order belongs to another branch');
    }
    if (!canTransition(order.status, to)) throw conflict(`Can't move an order from ${order.status} to ${to}`, 'INVALID_TRANSITION');

    const restored: string[] = [];
    if (to === 'CANCELLED' && order.stockReserved) {
      const lines = await tx`select product_id, quantity, customization from order_lines
                             where order_id = ${orderId} and line_type = 'PRODUCT' and customization is null`;
      for (const l of lines) {
        const res = await tx`update product_stock set remaining_batch_stock = remaining_batch_stock + ${l.quantity}, updated_at = now()
                             where product_id = ${l.productId} and hub_id = ${order.hubId} returning product_id`;
        if (res.length) restored.push(l.productId);
      }
    }

    const entry = { status: to, at: new Date(nowMs).toISOString(), by: actor.role, ...(reason ? { reason } : {}) };
    await tx`update orders set status = ${to}, stock_reserved = ${to === 'CANCELLED' ? false : order.stockReserved},
             status_history = status_history || ${tx.json([entry] as never)}, updated_at = now()
             where id = ${orderId}`;
    await bus.publish({ type: 'order.updated', orderId, hubId: order.hubId, userId: order.userId, status: to }, tx);
    if (restored.length) await bus.publish({ type: 'stock.updated', hubId: order.hubId, productIds: restored }, tx);
    return (await getOrder(tx, orderId))!;
  });
}

// ── Slots for the checkout picker ─────────────────────────────────────────────

export async function slotsFor(
  db: Db,
  type: FulfillmentType,
  items: { productId: string; customization?: CakeChoice | null }[],
  nowMs: number,
): Promise<SlotDay[]> {
  const settings = await getSettings(db);
  const products = await getProductsByIds(db, [...new Set(items.map((i) => i.productId))]);
  const slotItems: SlotItem[] = items
    .map((i) => products.get(i.productId))
    .filter((p): p is Product => p != null)
    .map((p) => ({ bakeSchedule: p.bakeSchedule, isCustom: p.isCustomizableCake }));
  return buildSlotDays(settings, type, slotItems, nowMs);
}

export async function zoneCheck(db: Db, lat: number, lng: number) {
  const result = checkZone(lat, lng, await listHubs(db));
  return result;
}
