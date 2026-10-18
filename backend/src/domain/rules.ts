import { badRequest } from '../errors.js';
import { addDays, dayLabel, todayIn, windowLabel, zonedToEpoch } from './time.js';
import type {
  AddOnOption,
  Allergen,
  BakeSchedule,
  BusinessSettings,
  Category,
  FulfillmentType,
  Hub,
  Promo,
} from './types.js';

// ── Money ──────────────────────────────────────────────────────────────────────

/** Whole rupees, half-up. */
export const roundMoney = (n: number): number => Math.round(n + Number.EPSILON);

// ── Custom cakes (spec §7.3) ───────────────────────────────────────────────────

export interface CakeChoice {
  sizeId: string;
  spongeId: string;
  fillingId: string;
  frostingId: string;
  eggless: boolean;
  message: string;
  fontId: string;
}

/** What gets stored on an order line: the choice plus resolved names and prices. */
export interface ResolvedCake extends CakeChoice {
  weightKg: number;
  sizeLabel: string;
  spongeFlavor: string;
  fillingFlavor: string;
  frostingType: string;
  pipingFont: string;
  isEggless: boolean;
  pipedMessage: string;
  sizeUplift: number;
  flavourSurcharge: number;
  egglessSurcharge: number;
  extraPrice: number;
  allergens: Allergen[];
}

/**
 * Price engine: size multiplier on the base (0.5 kg 1.0×, 1 kg 1.85×, 2 kg 3.5×), flavour and
 * eggless surcharges quoted per 0.5 kg and scaled by the same multiplier.
 * `unit price = basePrice + extraPrice`.
 */
export function resolveCake(
  s: BusinessSettings,
  basePrice: number,
  productAllergens: Allergen[],
  choice: CakeChoice,
): ResolvedCake {
  const size = s.cakeSizes.find((x) => x.id === choice.sizeId);
  const sponge = s.sponges.find((x) => x.id === choice.spongeId);
  const filling = s.fillings.find((x) => x.id === choice.fillingId);
  const frosting = s.frostings.find((x) => x.id === choice.frostingId);
  const font = s.pipingFonts.find((x) => x.id === choice.fontId) ?? s.pipingFonts[0];
  if (!size || !sponge || !filling || !frosting) throw badRequest('That cake option is no longer available', 'INVALID_CAKE');
  const message = (choice.message ?? '').trim();
  if (message.length > s.maxPipedMessageLength) {
    throw badRequest(`Piped messages can be at most ${s.maxPipedMessageLength} characters`, 'MESSAGE_TOO_LONG');
  }

  const m = size.multiplier;
  const isEggless = choice.eggless || Boolean(sponge.isEggless);
  const sizeUplift = roundMoney(basePrice * (m - 1));
  const flavourSurcharge = roundMoney((sponge.surcharge + filling.surcharge + frosting.surcharge) * m);
  const egglessSurcharge = isEggless && !sponge.isEggless ? roundMoney(s.egglessSurcharge * m) : 0;

  const allergens = new Set<Allergen>([...productAllergens, ...(filling.allergens ?? []), ...(frosting.allergens ?? [])]);
  if (isEggless) allergens.delete('EGGS');

  return {
    ...choice,
    message,
    eggless: isEggless,
    weightKg: size.weightKg,
    sizeLabel: size.label,
    spongeFlavor: sponge.name,
    fillingFlavor: filling.name,
    frostingType: frosting.name,
    pipingFont: font.id,
    isEggless,
    pipedMessage: message,
    sizeUplift,
    flavourSurcharge,
    egglessSurcharge,
    extraPrice: sizeUplift + flavourSurcharge + egglessSurcharge,
    allergens: [...allergens],
  };
}

// ── Order pricing ──────────────────────────────────────────────────────────────

export interface PricedLine {
  productId: string;
  name: string;
  category: Category;
  bakeSchedule: BakeSchedule;
  basePrice: number;
  unitPrice: number;
  quantity: number;
  isCustom: boolean;
}

export interface Pricing {
  subtotal: number;
  customCakeSurcharge: number;
  packagingFee: number;
  deliveryFee: number;
  promoDiscount: number;
  loyaltyDiscount: number;
  total: number;
}

/** Items + cake surcharge + add-ons, before fees. Used for promo minimum spend. */
export function goodsTotal(lines: PricedLine[], addOns: AddOnOption[]): number {
  return lines.reduce((sum, l) => sum + l.unitPrice * l.quantity, 0) + addOns.reduce((s, a) => s + a.price, 0);
}

export function orderPricing(
  s: BusinessSettings,
  lines: PricedLine[],
  addOns: AddOnOption[],
  type: FulfillmentType,
  promo: Promo | null,
  loyaltyDiscount: number,
): Pricing {
  if (lines.length === 0) {
    return { subtotal: 0, customCakeSurcharge: 0, packagingFee: 0, deliveryFee: 0, promoDiscount: 0, loyaltyDiscount: 0, total: 0 };
  }
  const itemsSubtotal = lines.reduce((sum, l) => sum + (l.isCustom ? l.basePrice : l.unitPrice) * l.quantity, 0);
  const cakeSurcharge = lines.filter((l) => l.isCustom).reduce((sum, l) => sum + Math.max(0, l.unitPrice - l.basePrice) * l.quantity, 0);
  const subtotal = itemsSubtotal + addOns.reduce((sum, a) => sum + a.price, 0);
  const goods = subtotal + cakeSurcharge;

  const cakeBoxes = lines.filter((l) => l.isCustom).reduce((sum, l) => sum + l.quantity, 0);
  const packaging = s.packagingFee + s.cakeBoxFee * cakeBoxes;
  const delivery = type === 'DELIVERY' && goods < s.freeDeliveryThreshold ? s.deliveryFee : 0;

  let promoDiscount = 0;
  if (promo?.type === 'PERCENT_OFF') {
    promoDiscount = (goods * promo.value) / 100;
    if (promo.maxDiscount != null) promoDiscount = Math.min(promoDiscount, promo.maxDiscount);
  } else if (promo?.type === 'FIXED_OFF') {
    promoDiscount = Math.min(promo.value, goods);
  } else if (promo?.type === 'FREE_DELIVERY') {
    promoDiscount = delivery;
  }
  const goodsAfterPromo = promo?.type === 'FREE_DELIVERY' ? goods : goods - promoDiscount;
  const loyalty = Math.min(Math.max(0, loyaltyDiscount), Math.max(0, goodsAfterPromo));
  const total = Math.max(0, goods + packaging + delivery - promoDiscount - loyalty);

  return {
    subtotal: roundMoney(subtotal),
    customCakeSurcharge: roundMoney(cakeSurcharge),
    packagingFee: roundMoney(packaging),
    deliveryFee: roundMoney(delivery),
    promoDiscount: roundMoney(promoDiscount),
    loyaltyDiscount: roundMoney(loyalty),
    total: roundMoney(total),
  };
}

/** Returns an error message, or null if the promo applies. */
export function promoProblem(promo: Promo | null, code: string, goods: number, type: FulfillmentType, nowMs: number): string | null {
  if (!promo || !promo.isActive || (promo.expiresAt && Date.parse(promo.expiresAt) < nowMs)) {
    return `"${code.trim().toUpperCase()}" isn't a valid code`;
  }
  if (goods < promo.minSpend) return `Spend Rs ${promo.minSpend.toLocaleString('en-US')} to use ${promo.code}`;
  if (promo.type === 'FREE_DELIVERY' && type !== 'DELIVERY') return `${promo.code} only applies to home delivery`;
  return null;
}

// ── Time slots (spec §7.1 + split availability) ────────────────────────────────

export interface SlotItem {
  bakeSchedule: BakeSchedule;
  isCustom: boolean;
}

export interface SlotOption {
  date: string;
  startMinute: number;
  endMinute: number;
  label: string;
  available: boolean;
  reason: string | null;
}

export interface SlotDay {
  date: string;
  label: string;
  options: SlotOption[];
}

export const needsLeadTime = (items: SlotItem[]) =>
  items.some((i) => i.isCustom || i.bakeSchedule === 'PRE_ORDER_24H');

/** Reason the window can't fulfil the basket, or null if it can. */
export function slotProblem(
  s: BusinessSettings,
  type: FulfillmentType,
  date: string,
  startMinute: number,
  items: SlotItem[],
  nowMs: number,
): string | null {
  const start = zonedToEpoch(date, startMinute, s.timezone);
  const prep = type === 'DELIVERY' ? s.deliveryPrepMinutes : s.pickupPrepMinutes;
  if (start < nowMs) return 'This window has already started';
  if (start < nowMs + prep * 60_000) return `Too soon — we need ${prep} minutes to prepare`;
  if (needsLeadTime(items) && (date === todayIn(s.timezone, nowMs) || start < nowMs + s.leadTimeHours * 3_600_000)) {
    return `Custom cakes need ${s.leadTimeHours} hours' notice`;
  }
  if (items.some((i) => i.bakeSchedule === 'AFTERNOON_BAKE') && startMinute < s.afternoonBakeStartMinute) {
    return 'Some items come from the afternoon bake (ready from 1 PM)';
  }
  return null;
}

export function windowsFor(s: BusinessSettings, type: FulfillmentType): [number, number][] {
  return type === 'DELIVERY' ? s.deliveryWindows : s.pickupWindows;
}

export function buildSlotDays(s: BusinessSettings, type: FulfillmentType, items: SlotItem[], nowMs: number): SlotDay[] {
  const today = todayIn(s.timezone, nowMs);
  return Array.from({ length: s.bookingDays }, (_, i) => {
    const date = addDays(today, i);
    return {
      date,
      label: dayLabel(date, today),
      options: windowsFor(s, type).map(([start, end]) => {
        const reason = slotProblem(s, type, date, start, items, nowMs);
        return { date, startMinute: start, endMinute: end, label: windowLabel(start, end), available: reason == null, reason };
      }),
    };
  });
}

// ── Delivery zone (spec §4 Flow 1) ─────────────────────────────────────────────

export function distanceKm(lat1: number, lng1: number, lat2: number, lng2: number): number {
  const rad = (d: number) => (d * Math.PI) / 180;
  const dLat = rad(lat2 - lat1);
  const dLng = rad(lng2 - lng1);
  const h = Math.sin(dLat / 2) ** 2 + Math.cos(rad(lat1)) * Math.cos(rad(lat2)) * Math.sin(dLng / 2) ** 2;
  return 2 * 6371.0088 * Math.asin(Math.sqrt(Math.min(1, Math.max(0, h))));
}

export type ZoneResult =
  | { inZone: true; hub: Hub; distanceKm: number }
  | { inZone: false; nearestHub: Hub; distanceKm: number }
  | { inZone: false; nearestHub: null; distanceKm: null };

export function checkZone(lat: number, lng: number, hubs: Hub[]): ZoneResult {
  const ranked = hubs
    .filter((h) => h.isActive)
    .map((hub) => ({ hub, d: distanceKm(lat, lng, hub.latitude, hub.longitude) }))
    .sort((a, b) => a.d - b.d);
  const nearest = ranked[0];
  if (!nearest) return { inZone: false, nearestHub: null, distanceKm: null };
  return nearest.d <= nearest.hub.deliveryRadiusKm
    ? { inZone: true, hub: nearest.hub, distanceKm: nearest.d }
    : { inZone: false, nearestHub: nearest.hub, distanceKm: nearest.d };
}

// ── Loyalty ("Baker's Dozen") ──────────────────────────────────────────────────

export interface LoyaltyStatus {
  stampsEarned: number;
  rewardsRedeemed: number;
  stampsAvailable: number;
  rewardsAvailable: number;
  stampsOnCard: number;
  stampsPerReward: number;
}

export function loyaltyStatus(s: BusinessSettings, stampsEarned: number, rewardsRedeemed: number): LoyaltyStatus {
  const per = s.stampsPerReward;
  const available = Math.max(0, stampsEarned - rewardsRedeemed * per);
  const rewards = Math.floor(available / per);
  return {
    stampsEarned,
    rewardsRedeemed,
    stampsAvailable: available,
    rewardsAvailable: rewards,
    stampsOnCard: rewards > 0 ? per : available % per,
    stampsPerReward: per,
  };
}

/** The free pastry is the cheapest single pastry or cookie in the basket. */
export function rewardValue(lines: PricedLine[]): number | null {
  const eligible = lines.filter((l) => !l.isCustom && (l.category === 'PASTRY' || l.category === 'COOKIE'));
  return eligible.length ? Math.min(...eligible.map((l) => l.unitPrice)) : null;
}

/** Same-day items are limited by today's batch; cakes and pre-orders are baked to order. */
export const isMadeToOrder = (l: { isCustom: boolean; bakeSchedule: BakeSchedule; category?: Category }) =>
  l.isCustom || l.bakeSchedule === 'PRE_ORDER_24H' || l.category === 'CUSTOM_CAKE';

// ── Order status flow ──────────────────────────────────────────────────────────

export const STATUS_FLOW = [
  'ORDER_CONFIRMED',
  'MIXING_AND_PROOFING',
  'IN_THE_OVEN',
  'DECORATING_AND_COOLING',
  'READY_OR_OUT_FOR_DELIVERY',
  'COMPLETED',
] as const;

export function canTransition(from: string, to: string): boolean {
  if (from === 'CANCELLED' || from === 'COMPLETED') return false;
  if (to === 'CANCELLED') return true;
  const a = STATUS_FLOW.indexOf(from as (typeof STATUS_FLOW)[number]);
  const b = STATUS_FLOW.indexOf(to as (typeof STATUS_FLOW)[number]);
  return a >= 0 && b > a;
}
