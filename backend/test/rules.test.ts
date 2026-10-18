import { describe, expect, it } from 'vitest';
import {
  buildSlotDays,
  canTransition,
  checkZone,
  distanceKm,
  loyaltyStatus,
  orderPricing,
  resolveCake,
  rewardValue,
  slotProblem,
  type PricedLine,
} from '../src/domain/rules.js';
import { dayLabel, windowLabel, zonedParts, zonedToEpoch } from '../src/domain/time.js';
import { DEFAULT_SETTINGS as S } from '../src/domain/types.js';
import { SEED_HUBS } from '../src/seed-data.js';
import { TEST_NOW } from './helpers.js';

const line = (o: Partial<PricedLine>): PricedLine => ({
  productId: 'p',
  name: 'P',
  category: 'PASTRY',
  bakeSchedule: 'MORNING_BAKE',
  basePrice: 550,
  unitPrice: 550,
  quantity: 1,
  isCustom: false,
  ...o,
});

describe('time (Asia/Karachi)', () => {
  it('converts between epoch and Islamabad wall-clock time', () => {
    expect(zonedParts(TEST_NOW, 'Asia/Karachi')).toMatchObject({ dateIso: '2026-10-18', minuteOfDay: 600 });
    expect(zonedToEpoch('2026-10-18', 600, 'Asia/Karachi')).toBe(TEST_NOW);
  });
  it('formats windows and day labels like the apps', () => {
    expect(windowLabel(480, 600)).toBe('08:00 AM - 10:00 AM');
    expect(windowLabel(1140, 1260)).toBe('07:00 PM - 09:00 PM');
    expect(dayLabel('2026-10-19', '2026-10-18')).toBe('Tomorrow');
    expect(dayLabel('2026-10-20', '2026-10-18')).toBe('Tue 20 Oct');
  });
});

describe('cake price engine (spec §7.3)', () => {
  it('applies 1.0× / 1.85× / 3.5× and scales surcharges', () => {
    const r = resolveCake(S, 3800, ['GLUTEN', 'DAIRY', 'EGGS'], {
      sizeId: 'ONE_KG', spongeId: 'BELGIAN_DARK_CHOCOLATE', fillingId: 'HAZELNUT_PRALINE', frostingId: 'MASCARPONE_WHIPPED_CREAM',
      eggless: false, message: 'Mubarak', fontId: 'SCRIPT',
    });
    expect(r.sizeUplift).toBe(3230); // 3800 × 0.85
    expect(r.flavourSurcharge).toBe(1388); // 750 × 1.85 = 1387.5
    expect(r.extraPrice).toBe(4618);
    expect(r.allergens.sort()).toEqual(['DAIRY', 'EGGS', 'GLUTEN', 'NUTS']);
  });
  it('eggless removes eggs and costs extra except on the eggless sponge', () => {
    const base = { sizeId: 'HALF_KG', fillingId: 'RASPBERRY_COMPOTE', frostingId: 'VANILLA_BUTTERCREAM', message: '', fontId: 'SCRIPT' };
    const upgraded = resolveCake(S, 3400, ['EGGS'], { ...base, spongeId: 'RED_VELVET', eggless: true });
    expect(upgraded.egglessSurcharge).toBe(400);
    expect(upgraded.allergens).not.toContain('EGGS');
    expect(resolveCake(S, 3400, [], { ...base, spongeId: 'EGGLESS', eggless: false }).egglessSurcharge).toBe(0);
  });
  it('rejects unknown options and over-long messages', () => {
    const ok = { sizeId: 'HALF_KG', spongeId: 'RED_VELVET', fillingId: 'RASPBERRY_COMPOTE', frostingId: 'VANILLA_BUTTERCREAM', eggless: false, fontId: 'SCRIPT' };
    expect(() => resolveCake(S, 1, [], { ...ok, message: 'x'.repeat(36) })).toThrow(/35/);
    expect(() => resolveCake(S, 1, [], { ...ok, sizeId: 'TEN_KG', message: '' })).toThrow();
  });
});

describe('order pricing', () => {
  it('splits subtotal, cake surcharge, packaging, free delivery', () => {
    const lines = [line({ quantity: 2 }), line({ category: 'CUSTOM_CAKE', basePrice: 3800, unitPrice: 7030, isCustom: true })];
    const p = orderPricing(S, lines, [S.addOns[0]], 'DELIVERY', null, 0);
    expect(p).toEqual({ subtotal: 1100 + 3800 + 250, customCakeSurcharge: 3230, packagingFee: 200, deliveryFee: 0, promoDiscount: 0, loyaltyDiscount: 0, total: 8580 });
  });
  it('charges delivery under Rs 5,000, caps percent promos, subtracts loyalty', () => {
    expect(orderPricing(S, [line({ quantity: 2 })], [], 'DELIVERY', null, 0).total).toBe(1100 + 50 + 250);
    const promo = { code: 'FRESH10', description: '', type: 'PERCENT_OFF' as const, value: 10, minSpend: 0, maxDiscount: 1000, isActive: true, expiresAt: null };
    const p = orderPricing(S, [line({ unitPrice: 20000, basePrice: 20000 })], [], 'PICKUP', promo, 550);
    expect(p.promoDiscount).toBe(1000);
    expect(p.total).toBe(20000 + 50 - 1000 - 550);
  });
});

describe('slots (spec §7.1)', () => {
  const pastry = [{ bakeSchedule: 'MORNING_BAKE' as const, isCustom: false }];
  it('blocks past, too-soon and lead-time windows', () => {
    expect(slotProblem(S, 'PICKUP', '2026-10-18', 480, pastry, TEST_NOW)).toMatch(/started/);
    expect(slotProblem(S, 'PICKUP', '2026-10-18', 600, pastry, TEST_NOW)).toMatch(/45 minutes/);
    expect(slotProblem(S, 'PICKUP', '2026-10-18', 720, pastry, TEST_NOW)).toBeNull();
    const cake = [{ bakeSchedule: 'PRE_ORDER_24H' as const, isCustom: true }];
    expect(slotProblem(S, 'PICKUP', '2026-10-18', 1080, cake, TEST_NOW)).toMatch(/24 hours/);
    expect(slotProblem(S, 'PICKUP', '2026-10-19', 480, cake, TEST_NOW)).toMatch(/24 hours/);
    expect(slotProblem(S, 'PICKUP', '2026-10-19', 600, cake, TEST_NOW)).toBeNull();
  });
  it('keeps afternoon-bake items after 1 PM', () => {
    const baguette = [{ bakeSchedule: 'AFTERNOON_BAKE' as const, isCustom: false }];
    expect(slotProblem(S, 'PICKUP', '2026-10-19', 600, baguette, TEST_NOW)).toMatch(/afternoon/);
    expect(slotProblem(S, 'PICKUP', '2026-10-19', 840, baguette, TEST_NOW)).toBeNull();
  });
  it('builds four days of labelled windows', () => {
    const days = buildSlotDays(S, 'DELIVERY', pastry, TEST_NOW);
    expect(days.map((d) => d.label).slice(0, 2)).toEqual(['Today', 'Tomorrow']);
    expect(days).toHaveLength(4);
    expect(days[0].options[0]).toMatchObject({ label: '09:00 AM - 11:00 AM', available: false });
  });
});

describe('delivery zone & loyalty & status', () => {
  it('matches twin-city addresses to the nearest branch', () => {
    expect(checkZone(33.7286, 73.0726, SEED_HUBS)).toMatchObject({ inZone: true, hub: { id: 'hub-f7' } });
    expect(checkZone(33.6007, 73.0679, SEED_HUBS)).toMatchObject({ inZone: true, hub: { id: 'hub-saddar' } });
    expect(checkZone(33.517, 73.105, SEED_HUBS)).toMatchObject({ inZone: true, hub: { id: 'hub-bahria' } });
    expect(checkZone(33.907, 73.3943, SEED_HUBS)).toMatchObject({ inZone: false, nearestHub: { id: 'hub-f7' } });
    expect(distanceKm(33.7213, 73.0566, 33.5965, 73.0525)).toBeGreaterThan(13);
  });
  it('rolls stamps into rewards; reward is the cheapest pastry', () => {
    expect(loyaltyStatus(S, 5, 0)).toMatchObject({ stampsOnCard: 5, rewardsAvailable: 0 });
    expect(loyaltyStatus(S, 13, 0)).toMatchObject({ stampsOnCard: 12, rewardsAvailable: 1 });
    expect(loyaltyStatus(S, 14, 1)).toMatchObject({ rewardsAvailable: 0, stampsOnCard: 2 });
    expect(rewardValue([line({ unitPrice: 750 }), line({ category: 'COOKIE', unitPrice: 450 }), line({ category: 'BREAD', unitPrice: 300 })])).toBe(450);
  });
  it('only moves orders forward, and never out of a final state', () => {
    expect(canTransition('ORDER_CONFIRMED', 'IN_THE_OVEN')).toBe(true);
    expect(canTransition('IN_THE_OVEN', 'MIXING_AND_PROOFING')).toBe(false);
    expect(canTransition('IN_THE_OVEN', 'CANCELLED')).toBe(true);
    expect(canTransition('COMPLETED', 'CANCELLED')).toBe(false);
  });
});
