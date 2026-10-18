export const ALLERGENS = ['GLUTEN', 'DAIRY', 'EGGS', 'NUTS', 'SOY'] as const;
export type Allergen = (typeof ALLERGENS)[number];

export const DIETARY_TAGS = ['VEGAN', 'EGGLESS', 'SUGAR_FREE', 'ORGANIC'] as const;
export type DietaryTag = (typeof DIETARY_TAGS)[number];

export const CATEGORIES = ['BREAD', 'PASTRY', 'CUSTOM_CAKE', 'COOKIE', 'BEVERAGE'] as const;
export type Category = (typeof CATEGORIES)[number];

export const BAKE_SCHEDULES = ['MORNING_BAKE', 'AFTERNOON_BAKE', 'ALL_DAY', 'PRE_ORDER_24H'] as const;
export type BakeSchedule = (typeof BAKE_SCHEDULES)[number];

export const ORDER_STATUSES = [
  'ORDER_CONFIRMED',
  'MIXING_AND_PROOFING',
  'IN_THE_OVEN',
  'DECORATING_AND_COOLING',
  'READY_OR_OUT_FOR_DELIVERY',
  'COMPLETED',
  'CANCELLED',
] as const;
export type OrderStatus = (typeof ORDER_STATUSES)[number];

export type FulfillmentType = 'PICKUP' | 'DELIVERY';
export type PaymentMethod = 'CASH_ON_DELIVERY' | 'CARD';
export type Role = 'customer' | 'staff' | 'admin';

export interface Nutrition {
  servingSize: string;
  calories: number;
  fatGrams: number;
  carbsGrams: number;
  sugarGrams: number;
  proteinGrams: number;
}

export interface ProductStock {
  remainingBatchStock: number;
  currentBatchNumber: number;
  nextBatchReadyAt: string | null;
}

export interface Product {
  id: string;
  name: string;
  subtitle: string;
  description: string;
  crumbNotes: string | null;
  reheatingTip: string | null;
  basePrice: number;
  category: Category;
  imageUrls: string[];
  allergens: Allergen[];
  dietaryTags: DietaryTag[];
  bakeSchedule: BakeSchedule;
  isCustomizableCake: boolean;
  nutrition: Nutrition | null;
  sortOrder: number;
  isListed: boolean;
}

export interface Hub {
  id: string;
  name: string;
  address: string;
  latitude: number;
  longitude: number;
  deliveryRadiusKm: number;
  isActive: boolean;
  sortOrder: number;
}

export interface Promo {
  code: string;
  description: string;
  type: 'PERCENT_OFF' | 'FIXED_OFF' | 'FREE_DELIVERY';
  value: number;
  minSpend: number;
  maxDiscount: number | null;
  isActive: boolean;
  expiresAt: string | null;
}

// ── Configurable business settings (admin-editable) ─────────────────────────────

export interface CakeSizeOption {
  id: string;
  label: string;
  weightKg: number;
  servings: number;
  multiplier: number;
  tiers: number;
}

export interface PricedOption {
  id: string;
  name: string;
  description: string;
  /** Rupees per 0.5 kg; scaled by the size multiplier. */
  surcharge: number;
  allergens?: Allergen[];
  isEggless?: boolean;
}

export interface AddOnOption {
  id: string;
  name: string;
  description: string;
  price: number;
}

export interface BusinessSettings {
  bakeryName: string;
  currencyCode: string;
  currencySymbol: string;
  timezone: string;
  packagingFee: number;
  cakeBoxFee: number;
  deliveryFee: number;
  freeDeliveryThreshold: number;
  pickupPrepMinutes: number;
  deliveryPrepMinutes: number;
  leadTimeHours: number;
  afternoonBakeStartMinute: number;
  bookingDays: number;
  pickupWindows: [number, number][];
  deliveryWindows: [number, number][];
  stampsPerReward: number;
  stampQualifyingTotal: number;
  egglessSurcharge: number;
  maxPipedMessageLength: number;
  maxPreOrderQuantity: number;
  cakeSizes: CakeSizeOption[];
  sponges: PricedOption[];
  fillings: PricedOption[];
  frostings: PricedOption[];
  pipingFonts: { id: string; name: string }[];
  addOns: AddOnOption[];
}

const h = (n: number) => n * 60;

export const DEFAULT_SETTINGS: BusinessSettings = {
  bakeryName: 'Crumb & Craft',
  currencyCode: 'PKR',
  currencySymbol: 'Rs',
  timezone: 'Asia/Karachi',
  packagingFee: 50,
  cakeBoxFee: 150,
  deliveryFee: 250,
  freeDeliveryThreshold: 5000,
  pickupPrepMinutes: 45,
  deliveryPrepMinutes: 90,
  leadTimeHours: 24,
  afternoonBakeStartMinute: h(13),
  bookingDays: 4,
  pickupWindows: [[h(8), h(10)], [h(10), h(12)], [h(12), h(14)], [h(14), h(16)], [h(16), h(18)], [h(18), h(20)]],
  deliveryWindows: [[h(9), h(11)], [h(11), h(13)], [h(13), h(15)], [h(15), h(17)], [h(17), h(19)], [h(19), h(21)]],
  stampsPerReward: 12,
  stampQualifyingTotal: 1000,
  egglessSurcharge: 400,
  maxPipedMessageLength: 35,
  maxPreOrderQuantity: 10,
  cakeSizes: [
    { id: 'HALF_KG', label: '0.5 kg', weightKg: 0.5, servings: 4, multiplier: 1.0, tiers: 1 },
    { id: 'ONE_KG', label: '1 kg', weightKg: 1.0, servings: 8, multiplier: 1.85, tiers: 1 },
    { id: 'TWO_KG_TWO_TIER', label: '2 kg Two-Tier', weightKg: 2.0, servings: 16, multiplier: 3.5, tiers: 2 },
  ],
  sponges: [
    { id: 'MADAGASCAR_VANILLA', name: 'Madagascar Vanilla', description: 'Bourbon vanilla bean — buttery and light', surcharge: 0 },
    { id: 'BELGIAN_DARK_CHOCOLATE', name: 'Belgian 70% Dark Chocolate', description: 'Deep, fudgy and not too sweet', surcharge: 250 },
    { id: 'RED_VELVET', name: 'Red Velvet', description: 'Buttermilk cocoa with a gentle tang', surcharge: 200 },
    { id: 'LEMON_ELDERFLOWER', name: 'Lemon Elderflower', description: 'Zesty lemon soaked in elderflower syrup', surcharge: 300 },
    { id: 'EGGLESS', name: 'Eggless Sponge', description: 'Vanilla sponge made without eggs', surcharge: 0, isEggless: true },
  ],
  fillings: [
    { id: 'RASPBERRY_COMPOTE', name: 'Raspberry Compote', description: 'Tart, bright and fruity', surcharge: 0 },
    { id: 'SALTED_CARAMEL', name: 'Salted Caramel', description: 'Slow-cooked caramel with sea salt', surcharge: 150, allergens: ['DAIRY'] },
    { id: 'HAZELNUT_PRALINE', name: 'Hazelnut Praline', description: 'Caramelised hazelnut crunch', surcharge: 250, allergens: ['NUTS'] },
  ],
  frostings: [
    { id: 'MASCARPONE_WHIPPED_CREAM', name: 'Mascarpone Whipped Cream', description: 'Light, creamy and barely sweet', surcharge: 250, allergens: ['DAIRY'] },
    { id: 'SALTED_CARAMEL_BUTTERCREAM', name: 'Salted Caramel Buttercream', description: 'Silky buttercream with caramel', surcharge: 200, allergens: ['DAIRY'] },
    { id: 'VANILLA_BUTTERCREAM', name: 'Classic Vanilla Buttercream', description: 'Smooth vanilla bean buttercream', surcharge: 0, allergens: ['DAIRY'] },
  ],
  pipingFonts: [
    { id: 'SCRIPT', name: 'Classic Script' },
    { id: 'SERIF', name: 'Patisserie Serif' },
    { id: 'PLAIN', name: 'Clean Print' },
  ],
  addOns: [
    { id: 'BIRTHDAY_CANDLES', name: 'Birthday candles', description: '12 tall beeswax candles', price: 250 },
    { id: 'GREETING_CARD', name: 'Greeting card', description: 'Hand-lettered by our bakers', price: 350 },
    { id: 'KNIFE_AND_SERVER', name: 'Knife & server set', description: 'Wooden cake knife and server', price: 600 },
  ],
};
