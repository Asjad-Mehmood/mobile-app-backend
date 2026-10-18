import type { Hub, Nutrition, Product, Promo } from './domain/types.js';

const img = (id: string) => `https://images.unsplash.com/photo-${id}?auto=format&fit=crop&w=1080&q=80`;
const SOURDOUGH = img('1586444248902-2f64eddc13df');
const SLICED_LOAF = img('1549931319-a545dcf3bc73');
const SEEDED_RYE = img('1509440159596-0249088772ff');
const BREAD_BASKET = img('1608198093002-ad4e005484ec');
const CROISSANTS_DARK = img('1555507036-ab1f4038808a');
const CROISSANT_PILE = img('1530610476181-d83430b64dcd');
const BLUEBERRY_MUFFINS = img('1558303420-f814d8a590f5');
const DARK_CHOC_COOKIES = img('1499636136210-6f4ee915583e');
const CHOC_CHIP_BASKET = img('1558961363-fa8fdf82db35');
const TRUFFLE_CAKE = img('1578985545062-69928b1d9587');
const CHEESECAKE = img('1524351199678-941a58a3df50');
const BLACK_FOREST = img('1606890737304-57a1ca8a5b62');
const STRAWBERRY_CAKE = img('1621303837174-89787a7d4729');
const CONFETTI_CAKE = img('1464349095431-e9a21285b5f3');
const FLAT_WHITE = img('1495474472287-4d71bcdd2085');

export const SEED_HUBS: Hub[] = [
  { id: 'hub-f7', name: 'F-7 Markaz Bakehouse', address: 'Jinnah Super Market, F-7 Markaz, Islamabad', latitude: 33.7213, longitude: 73.0566, deliveryRadiusKm: 15, isActive: true, sortOrder: 10 },
  { id: 'hub-saddar', name: 'Saddar Atelier', address: 'Bank Road, Saddar, Rawalpindi', latitude: 33.5965, longitude: 73.0525, deliveryRadiusKm: 15, isActive: true, sortOrder: 20 },
  { id: 'hub-bahria', name: 'Bahria Town Oven', address: 'Civic Centre, Bahria Town Phase 4, Rawalpindi', latitude: 33.5375, longitude: 73.1255, deliveryRadiusKm: 15, isActive: true, sortOrder: 30 },
];

const n = (servingSize: string, calories: number, fat: number, carbs: number, sugar: number, protein: number): Nutrition => ({
  servingSize,
  calories,
  fatGrams: fat,
  carbsGrams: carbs,
  sugarGrams: sugar,
  proteinGrams: protein,
});

type SeedProduct = Omit<Product, 'isListed' | 'crumbNotes' | 'reheatingTip'> & {
  crumbNotes?: string;
  reheatingTip?: string;
  /** Opening stock per branch, and minutes until a batch is out (null = nothing in the oven). */
  stock: number;
  ovenMinutes: number | null;
};

export const SEED_PRODUCTS: SeedProduct[] = [
  {
    id: 'bread-sourdough-country', name: 'Sourdough Country Loaf', subtitle: '72-hour cold ferment · 800 g',
    description: 'Our house levain, stone-milled organic wheat and a slow three-day ferment for a deep, gently sour loaf.',
    crumbNotes: 'Open, glossy crumb with a blistered, deeply caramelised crust.', reheatingTip: 'Spritz with water and refresh at 200 °C for 6–8 minutes.',
    basePrice: 1400, category: 'BREAD', imageUrls: [SOURDOUGH, SLICED_LOAF], allergens: ['GLUTEN'], dietaryTags: ['VEGAN', 'EGGLESS', 'ORGANIC'],
    bakeSchedule: 'MORNING_BAKE', isCustomizableCake: false, nutrition: n('1 slice (50 g)', 120, 0.6, 24, 0.8, 4.4), sortOrder: 10, stock: 4, ovenMinutes: 52,
  },
  {
    id: 'bread-seeded-rye', name: 'Seeded Danish Rye', subtitle: 'Rye, sunflower & flax · 900 g',
    description: 'A dark, malty rugbrød packed with cracked rye, sunflower and flax seeds.',
    crumbNotes: 'Dense, moist and seed-packed. Slice thin.', reheatingTip: 'Best toasted. Keeps 5 days wrapped in linen.',
    basePrice: 1600, category: 'BREAD', imageUrls: [SEEDED_RYE], allergens: ['GLUTEN'], dietaryTags: ['VEGAN', 'EGGLESS', 'ORGANIC'],
    bakeSchedule: 'MORNING_BAKE', isCustomizableCake: false, nutrition: n('1 slice (45 g)', 105, 2.1, 18, 1.2, 3.6), sortOrder: 20, stock: 7, ovenMinutes: null,
  },
  {
    id: 'bread-honey-spelt', name: 'Honey Spelt Sandwich Loaf', subtitle: 'Wholegrain spelt · 750 g',
    description: 'Soft wholegrain spelt enriched with Pakistani beri honey and a little butter.',
    crumbNotes: 'Tight, tender, even crumb that holds up to sandwiches.', reheatingTip: 'Toast straight from frozen — no need to thaw.',
    basePrice: 1200, category: 'BREAD', imageUrls: [SLICED_LOAF, BREAD_BASKET], allergens: ['GLUTEN', 'DAIRY'], dietaryTags: ['EGGLESS'],
    bakeSchedule: 'MORNING_BAKE', isCustomizableCake: false, nutrition: n('1 slice (40 g)', 98, 1.4, 18, 2.6, 3.8), sortOrder: 30, stock: 9, ovenMinutes: null,
  },
  {
    id: 'bread-baguette', name: 'Tradition Baguette', subtitle: 'Poolish-fermented · 250 g',
    description: 'Flour, water, salt and yeast — nothing else — shaped by hand and baked on the stone.',
    crumbNotes: 'Crackling crust, creamy irregular crumb.', reheatingTip: '3 minutes at 220 °C brings back the crackle.',
    basePrice: 450, category: 'BREAD', imageUrls: [BREAD_BASKET], allergens: ['GLUTEN'], dietaryTags: ['VEGAN', 'EGGLESS'],
    bakeSchedule: 'AFTERNOON_BAKE', isCustomizableCake: false, nutrition: n('¼ baguette (62 g)', 155, 0.7, 31, 0.9, 5.2), sortOrder: 40, stock: 6, ovenMinutes: 38,
  },
  {
    id: 'pastry-butter-croissant', name: 'Butter Croissant', subtitle: 'Cultured butter · 27 layers',
    description: 'Laminated over three days with cultured butter for a shattering, honeycombed croissant.',
    crumbNotes: 'Shatter-crisp shell, airy honeycomb interior.', reheatingTip: '4 minutes at 180 °C. Never microwave.',
    basePrice: 550, category: 'PASTRY', imageUrls: [CROISSANTS_DARK, CROISSANT_PILE], allergens: ['GLUTEN', 'DAIRY', 'EGGS'], dietaryTags: [],
    bakeSchedule: 'MORNING_BAKE', isCustomizableCake: false, nutrition: n('1 croissant (70 g)', 290, 17, 29, 5, 6), sortOrder: 50, stock: 12, ovenMinutes: 22,
  },
  {
    id: 'pastry-almond-croissant', name: 'Almond Croissants', subtitle: 'Twice-baked · almond frangipane',
    description: "Yesterday's croissants soaked in orange-blossom syrup, filled with frangipane and baked again under flaked almonds.",
    crumbNotes: 'Crisp, caramelised top over a soft, custardy centre.', reheatingTip: '5 minutes at 170 °C to re-crisp the almonds.',
    basePrice: 750, category: 'PASTRY', imageUrls: [CROISSANT_PILE, CROISSANTS_DARK], allergens: ['GLUTEN', 'DAIRY', 'EGGS', 'NUTS'], dietaryTags: [],
    bakeSchedule: 'MORNING_BAKE', isCustomizableCake: false, nutrition: n('1 croissant (95 g)', 420, 24, 41, 18, 9), sortOrder: 60, stock: 2, ovenMinutes: 14,
  },
  {
    id: 'pastry-pistachio-raspberry', name: 'Pistachio Raspberry Croissant', subtitle: 'Pistachio cream · raspberry compote',
    description: 'Our butter croissant filled with pistachio cream and a ribbon of tart raspberry compote.',
    crumbNotes: 'Flaky layers around a silky, nutty filling.', reheatingTip: 'Enjoy at room temperature — the filling is best unheated.',
    basePrice: 950, category: 'PASTRY', imageUrls: [CROISSANT_PILE, CROISSANTS_DARK], allergens: ['GLUTEN', 'DAIRY', 'EGGS', 'NUTS'], dietaryTags: [],
    bakeSchedule: 'MORNING_BAKE', isCustomizableCake: false, nutrition: n('1 croissant (110 g)', 465, 27, 46, 21, 9.5), sortOrder: 70, stock: 3, ovenMinutes: null,
  },
  {
    id: 'pastry-blueberry-muffin', name: 'Blueberry Crumble Muffin', subtitle: 'Wild blueberries · brown-butter crumble',
    description: 'Buttermilk muffin bursting with wild blueberries under a brown-butter oat crumble.',
    crumbNotes: 'Moist, tender crumb with a crunchy, craggy top.', reheatingTip: '10 seconds in the microwave, or 4 minutes at 160 °C.',
    basePrice: 600, category: 'PASTRY', imageUrls: [BLUEBERRY_MUFFINS], allergens: ['GLUTEN', 'DAIRY', 'EGGS'], dietaryTags: [],
    bakeSchedule: 'ALL_DAY', isCustomizableCake: false, nutrition: n('1 muffin (120 g)', 410, 18, 56, 30, 6), sortOrder: 80, stock: 5, ovenMinutes: 32,
  },
  {
    id: 'cookie-sea-salt-dark', name: 'Sea Salt Dark Chocolate Cookie', subtitle: '70% Belgian chocolate · flaky salt',
    description: 'Brown-butter dough rested for 48 hours, loaded with 70% Belgian chocolate and finished with flaky sea salt.',
    crumbNotes: 'Crisp edges, gooey molten centre.', reheatingTip: '6 minutes at 160 °C for a just-baked centre.',
    basePrice: 450, category: 'COOKIE', imageUrls: [DARK_CHOC_COOKIES, CHOC_CHIP_BASKET], allergens: ['GLUTEN', 'DAIRY', 'EGGS', 'SOY'], dietaryTags: [],
    bakeSchedule: 'ALL_DAY', isCustomizableCake: false, nutrition: n('1 cookie (85 g)', 395, 21, 47, 29, 5), sortOrder: 90, stock: 22, ovenMinutes: null,
  },
  {
    id: 'cookie-vegan-choc-chip', name: 'Vegan Brown Sugar Chip Cookie', subtitle: 'Oat milk · dairy-free chocolate',
    description: 'A fully plant-based chewy cookie made with dark muscovado, oat milk and dairy-free chocolate chips.',
    crumbNotes: 'Chewy and toffee-like with crisp, lacy edges.', reheatingTip: '5 minutes at 160 °C.',
    basePrice: 450, category: 'COOKIE', imageUrls: [CHOC_CHIP_BASKET], allergens: ['GLUTEN', 'SOY'], dietaryTags: ['VEGAN', 'EGGLESS'],
    bakeSchedule: 'ALL_DAY', isCustomizableCake: false, nutrition: n('1 cookie (80 g)', 360, 16, 50, 28, 4), sortOrder: 100, stock: 14, ovenMinutes: null,
  },
  {
    id: 'cake-belgian-dark-truffle', name: 'Belgian Dark Truffle Cake', subtitle: '70% ganache drip · from 0.5 kg',
    description: 'Layers of dark chocolate sponge and whipped truffle ganache under a glossy chocolate drip.',
    crumbNotes: 'Fudgy, close-textured sponge with silky ganache.', reheatingTip: 'Serve at room temperature: out of the fridge 30 minutes before slicing.',
    basePrice: 3800, category: 'CUSTOM_CAKE', imageUrls: [TRUFFLE_CAKE], allergens: ['GLUTEN', 'DAIRY', 'EGGS'], dietaryTags: [],
    bakeSchedule: 'PRE_ORDER_24H', isCustomizableCake: true, nutrition: n('1 slice (1/8 of 1 kg)', 520, 31, 54, 41, 7), sortOrder: 110, stock: 0, ovenMinutes: null,
  },
  {
    id: 'cake-basque-cheesecake', name: 'Custom Basque Cheesecake', subtitle: 'Burnt top, crustless · from 0.5 kg',
    description: 'San Sebastián-style cheesecake baked hot for a deeply caramelised top and a barely-set, creamy heart.',
    crumbNotes: 'Bittersweet burnt top, molten-custard centre.', reheatingTip: 'Rest 1 hour at room temperature for the creamiest centre.',
    basePrice: 3500, category: 'CUSTOM_CAKE', imageUrls: [CHEESECAKE], allergens: ['DAIRY', 'EGGS'], dietaryTags: [],
    bakeSchedule: 'PRE_ORDER_24H', isCustomizableCake: true, nutrition: n('1 slice (1/8 of 1 kg)', 430, 32, 26, 23, 9), sortOrder: 120, stock: 0, ovenMinutes: null,
  },
  {
    id: 'cake-black-forest', name: 'Black Forest Celebration Cake', subtitle: 'Morello cherries · Chantilly cream',
    description: 'Cocoa sponge layered with Morello cherry compote and vanilla Chantilly, crowned with fresh cherries.',
    crumbNotes: 'Light cocoa sponge, cloud-soft cream.', reheatingTip: 'Keep refrigerated; serve within 2 days.',
    basePrice: 3600, category: 'CUSTOM_CAKE', imageUrls: [BLACK_FOREST], allergens: ['GLUTEN', 'DAIRY', 'EGGS'], dietaryTags: [],
    bakeSchedule: 'PRE_ORDER_24H', isCustomizableCake: true, nutrition: n('1 slice (1/8 of 1 kg)', 460, 26, 50, 36, 6), sortOrder: 130, stock: 0, ovenMinutes: null,
  },
  {
    id: 'cake-strawberry-celebration', name: 'Strawberry Ripple Celebration Cake', subtitle: 'Vanilla bean sponge · fresh strawberries',
    description: 'Vanilla sponge rippled with strawberry jam, finished in pink buttercream and a strawberry drip.',
    crumbNotes: 'Soft, buttery sponge with jammy ribbons.', reheatingTip: 'Keep refrigerated; out of the fridge 30 minutes before serving.',
    basePrice: 3400, category: 'CUSTOM_CAKE', imageUrls: [STRAWBERRY_CAKE, CONFETTI_CAKE], allergens: ['GLUTEN', 'DAIRY', 'EGGS'], dietaryTags: [],
    bakeSchedule: 'PRE_ORDER_24H', isCustomizableCake: true, nutrition: n('1 slice (1/8 of 1 kg)', 470, 23, 61, 45, 5), sortOrder: 140, stock: 0, ovenMinutes: null,
  },
  {
    id: 'drink-flat-white', name: 'Flat White', subtitle: 'Double ristretto · steamed whole milk',
    description: 'A double ristretto of our seasonal single-origin espresso with silky microfoam.',
    basePrice: 750, category: 'BEVERAGE', imageUrls: [FLAT_WHITE], allergens: ['DAIRY'], dietaryTags: [],
    bakeSchedule: 'ALL_DAY', isCustomizableCake: false, nutrition: n('1 cup (180 ml)', 110, 6, 8.5, 8.5, 6), sortOrder: 150, stock: 99, ovenMinutes: null,
  },
];

export const SEED_PROMOS: Omit<Promo, 'expiresAt'>[] = [
  { code: 'FRESH10', description: '10% off your order (up to Rs 1,000)', type: 'PERCENT_OFF', value: 10, minSpend: 0, maxDiscount: 1000, isActive: true },
  { code: 'WELCOME500', description: 'Rs 500 off orders over Rs 2,500', type: 'FIXED_OFF', value: 500, minSpend: 2500, maxDiscount: null, isActive: true },
  { code: 'FREEDELIVERY', description: 'Free home delivery', type: 'FREE_DELIVERY', value: 0, minSpend: 0, maxDiscount: null, isActive: true },
];
