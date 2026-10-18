import 'enums.dart';

typedef Json = Map<String, dynamic>;

int _int(Object? v, [int fallback = 0]) => v is num ? v.toInt() : int.tryParse('$v') ?? fallback;
double _double(Object? v, [double fallback = 0]) => v is num ? v.toDouble() : double.tryParse('$v') ?? fallback;
List<String> _strings(Object? v) => (v as List? ?? const []).map((e) => '$e').toList();
DateTime? _date(Object? v) => v == null ? null : DateTime.tryParse('$v')?.toLocal();

// ── Users ─────────────────────────────────────────────────────────────────────

class AppUser {
  const AppUser({required this.id, required this.email, required this.name, this.phone, required this.role, this.hubId, this.isActive = true});

  final String id;
  final String email;
  final String name;
  final String? phone;
  final UserRole role;
  final String? hubId;
  final bool isActive;

  bool get isStaffOrAdmin => role == UserRole.staff || role == UserRole.admin;
  bool get isAdmin => role == UserRole.admin;

  factory AppUser.fromJson(Json j) => AppUser(
        id: j['id'] as String,
        email: j['email'] as String,
        name: j['name'] as String? ?? '',
        phone: j['phone'] as String?,
        role: UserRole.fromWire(j['role'] as String?),
        hubId: j['hubId'] as String?,
        isActive: j['isActive'] as bool? ?? true,
      );
}

// ── Catalog ───────────────────────────────────────────────────────────────────

class Nutrition {
  const Nutrition({required this.servingSize, required this.calories, required this.fatGrams, required this.carbsGrams, required this.sugarGrams, required this.proteinGrams});

  final String servingSize;
  final int calories;
  final double fatGrams;
  final double carbsGrams;
  final double sugarGrams;
  final double proteinGrams;

  factory Nutrition.fromJson(Json j) => Nutrition(
        servingSize: j['servingSize'] as String? ?? '',
        calories: _int(j['calories']),
        fatGrams: _double(j['fatGrams']),
        carbsGrams: _double(j['carbsGrams']),
        sugarGrams: _double(j['sugarGrams']),
        proteinGrams: _double(j['proteinGrams']),
      );

  Json toJson() => {
        'servingSize': servingSize,
        'calories': calories,
        'fatGrams': fatGrams,
        'carbsGrams': carbsGrams,
        'sugarGrams': sugarGrams,
        'proteinGrams': proteinGrams,
      };
}

class ProductStock {
  const ProductStock({this.remainingBatchStock = 0, this.currentBatchNumber = 1, this.nextBatchReadyAt});

  final int remainingBatchStock;
  final int currentBatchNumber;
  final DateTime? nextBatchReadyAt;

  bool isBaking(DateTime now) => nextBatchReadyAt != null && nextBatchReadyAt!.isAfter(now);

  factory ProductStock.fromJson(Json? j) => j == null
      ? const ProductStock()
      : ProductStock(
          remainingBatchStock: _int(j['remainingBatchStock']),
          currentBatchNumber: _int(j['currentBatchNumber'], 1),
          nextBatchReadyAt: _date(j['nextBatchReadyAt']),
        );
}

class Product {
  const Product({
    required this.id,
    required this.name,
    this.subtitle = '',
    this.description = '',
    this.crumbNotes,
    this.reheatingTip,
    required this.basePrice,
    required this.category,
    this.imageUrls = const [],
    this.allergens = const {},
    this.dietaryTags = const {},
    this.bakeSchedule = BakeSchedule.allDay,
    this.isCustomizableCake = false,
    this.nutrition,
    this.sortOrder = 0,
    this.isListed = true,
    this.stock = const ProductStock(),
  });

  final String id;
  final String name;
  final String subtitle;
  final String description;
  final String? crumbNotes;
  final String? reheatingTip;
  final int basePrice;
  final ProductCategory category;
  final List<String> imageUrls;
  final Set<Allergen> allergens;
  final Set<DietaryTag> dietaryTags;
  final BakeSchedule bakeSchedule;
  final bool isCustomizableCake;
  final Nutrition? nutrition;
  final int sortOrder;
  final bool isListed;
  final ProductStock stock;

  String? get imageUrl => imageUrls.isEmpty ? null : imageUrls.first;

  /// Cakes and 24-hour items are baked to order — no batch limit.
  bool get isMadeToOrder => isCustomizableCake || bakeSchedule == BakeSchedule.preOrder;

  bool get isSoldOut => !isMadeToOrder && stock.remainingBatchStock <= 0;

  bool isFreeFrom(Allergen a) => !allergens.contains(a);

  factory Product.fromJson(Json j) => Product(
        id: j['id'] as String,
        name: j['name'] as String,
        subtitle: j['subtitle'] as String? ?? '',
        description: j['description'] as String? ?? '',
        crumbNotes: j['crumbNotes'] as String?,
        reheatingTip: j['reheatingTip'] as String?,
        basePrice: _int(j['basePrice']),
        category: ProductCategory.fromWire(j['category'] as String?),
        imageUrls: _strings(j['imageUrls']),
        allergens: _strings(j['allergens']).map(Allergen.fromWire).whereType<Allergen>().toSet(),
        dietaryTags: _strings(j['dietaryTags']).map(DietaryTag.fromWire).whereType<DietaryTag>().toSet(),
        bakeSchedule: BakeSchedule.fromWire(j['bakeSchedule'] as String?),
        isCustomizableCake: j['isCustomizableCake'] as bool? ?? false,
        nutrition: j['nutrition'] == null ? null : Nutrition.fromJson(j['nutrition'] as Json),
        sortOrder: _int(j['sortOrder']),
        isListed: j['isListed'] as bool? ?? true,
        stock: ProductStock.fromJson(j['stock'] as Json?),
      );

  /// Body for the admin create/update endpoints.
  Json toAdminJson() => {
        'name': name,
        'subtitle': subtitle,
        'description': description,
        'crumbNotes': crumbNotes,
        'reheatingTip': reheatingTip,
        'basePrice': basePrice,
        'category': category.wire,
        'imageUrls': imageUrls,
        'allergens': allergens.map((a) => a.wire).toList(),
        'dietaryTags': dietaryTags.map((d) => d.wire).toList(),
        'bakeSchedule': bakeSchedule.wire,
        'isCustomizableCake': isCustomizableCake,
        'nutrition': nutrition?.toJson(),
        'sortOrder': sortOrder,
        'isListed': isListed,
      };
}

class Hub {
  const Hub({required this.id, required this.name, required this.address, required this.latitude, required this.longitude, this.deliveryRadiusKm = 15, this.isActive = true, this.sortOrder = 0});

  final String id;
  final String name;
  final String address;
  final double latitude;
  final double longitude;
  final double deliveryRadiusKm;
  final bool isActive;
  final int sortOrder;

  factory Hub.fromJson(Json j) => Hub(
        id: j['id'] as String,
        name: j['name'] as String,
        address: j['address'] as String? ?? '',
        latitude: _double(j['latitude']),
        longitude: _double(j['longitude']),
        deliveryRadiusKm: _double(j['deliveryRadiusKm'], 15),
        isActive: j['isActive'] as bool? ?? true,
        sortOrder: _int(j['sortOrder']),
      );

  Json toJson() => {
        'name': name,
        'address': address,
        'latitude': latitude,
        'longitude': longitude,
        'deliveryRadiusKm': deliveryRadiusKm,
        'isActive': isActive,
        'sortOrder': sortOrder,
      };
}

class Catalog {
  const Catalog({required this.hubId, required this.products, required this.serverTime});
  final String hubId;
  final List<Product> products;
  final DateTime serverTime;

  Product? byId(String id) => products.where((p) => p.id == id).firstOrNull;

  factory Catalog.fromJson(Json j) => Catalog(
        hubId: j['hubId'] as String,
        products: (j['products'] as List).map((e) => Product.fromJson(e as Json)).toList(),
        serverTime: _date(j['serverTime']) ?? DateTime.now(),
      );
}

// ── Business settings ─────────────────────────────────────────────────────────

class CakeSizeOption {
  const CakeSizeOption({required this.id, required this.label, required this.weightKg, required this.servings, required this.multiplier, required this.tiers});
  final String id;
  final String label;
  final double weightKg;
  final int servings;
  final double multiplier;
  final int tiers;

  factory CakeSizeOption.fromJson(Json j) => CakeSizeOption(
        id: j['id'] as String,
        label: j['label'] as String,
        weightKg: _double(j['weightKg']),
        servings: _int(j['servings']),
        multiplier: _double(j['multiplier'], 1),
        tiers: _int(j['tiers'], 1),
      );

  Json toJson() => {'id': id, 'label': label, 'weightKg': weightKg, 'servings': servings, 'multiplier': multiplier, 'tiers': tiers};
}

class PricedOption {
  const PricedOption({required this.id, required this.name, this.description = '', required this.surcharge, this.allergens = const {}, this.isEggless = false});
  final String id;
  final String name;
  final String description;
  final int surcharge;
  final Set<Allergen> allergens;
  final bool isEggless;

  factory PricedOption.fromJson(Json j) => PricedOption(
        id: j['id'] as String,
        name: j['name'] as String,
        description: j['description'] as String? ?? '',
        surcharge: _int(j['surcharge']),
        allergens: _strings(j['allergens']).map(Allergen.fromWire).whereType<Allergen>().toSet(),
        isEggless: j['isEggless'] as bool? ?? false,
      );

  PricedOption copyWith({int? surcharge}) =>
      PricedOption(id: id, name: name, description: description, surcharge: surcharge ?? this.surcharge, allergens: allergens, isEggless: isEggless);

  Json toJson() => {
        'id': id,
        'name': name,
        'description': description,
        'surcharge': surcharge,
        if (allergens.isNotEmpty) 'allergens': allergens.map((a) => a.wire).toList(),
        if (isEggless) 'isEggless': true,
      };
}

class AddOnOption {
  const AddOnOption({required this.id, required this.name, this.description = '', required this.price});
  final String id;
  final String name;
  final String description;
  final int price;

  factory AddOnOption.fromJson(Json j) =>
      AddOnOption(id: j['id'] as String, name: j['name'] as String, description: j['description'] as String? ?? '', price: _int(j['price']));

  AddOnOption copyWith({int? price}) => AddOnOption(id: id, name: name, description: description, price: price ?? this.price);

  Json toJson() => {'id': id, 'name': name, 'description': description, 'price': price};
}

class NamedOption {
  const NamedOption(this.id, this.name);
  final String id;
  final String name;
}

class BusinessSettings {
  const BusinessSettings(this.raw);

  /// Kept whole so admin edits can round-trip fields this app version doesn't know.
  final Json raw;

  String get bakeryName => raw['bakeryName'] as String? ?? 'Crumb & Craft';
  String get currencySymbol => raw['currencySymbol'] as String? ?? 'Rs';
  String get timezone => raw['timezone'] as String? ?? 'Asia/Karachi';
  int get packagingFee => _int(raw['packagingFee']);
  int get cakeBoxFee => _int(raw['cakeBoxFee']);
  int get deliveryFee => _int(raw['deliveryFee']);
  int get freeDeliveryThreshold => _int(raw['freeDeliveryThreshold']);
  int get pickupPrepMinutes => _int(raw['pickupPrepMinutes']);
  int get deliveryPrepMinutes => _int(raw['deliveryPrepMinutes']);
  int get leadTimeHours => _int(raw['leadTimeHours'], 24);
  int get bookingDays => _int(raw['bookingDays'], 4);
  int get stampsPerReward => _int(raw['stampsPerReward'], 12);
  int get stampQualifyingTotal => _int(raw['stampQualifyingTotal']);
  int get egglessSurcharge => _int(raw['egglessSurcharge']);
  int get maxPipedMessageLength => _int(raw['maxPipedMessageLength'], 35);
  int get maxPreOrderQuantity => _int(raw['maxPreOrderQuantity'], 10);

  List<CakeSizeOption> get cakeSizes => _list(raw['cakeSizes'], CakeSizeOption.fromJson);
  List<PricedOption> get sponges => _list(raw['sponges'], PricedOption.fromJson);
  List<PricedOption> get fillings => _list(raw['fillings'], PricedOption.fromJson);
  List<PricedOption> get frostings => _list(raw['frostings'], PricedOption.fromJson);
  List<AddOnOption> get addOns => _list(raw['addOns'], AddOnOption.fromJson);
  List<NamedOption> get pipingFonts =>
      (raw['pipingFonts'] as List? ?? const []).map((e) => NamedOption((e as Json)['id'] as String, e['name'] as String)).toList();

  static List<T> _list<T>(Object? v, T Function(Json) f) => (v as List? ?? const []).map((e) => f(e as Json)).toList();
}

// ── Custom cakes ──────────────────────────────────────────────────────────────

/// What the customer picked in the cake builder (sent to the server, which re-prices it).
class CakeChoice {
  const CakeChoice({required this.sizeId, required this.spongeId, required this.fillingId, required this.frostingId, this.eggless = false, this.message = '', this.fontId = 'SCRIPT'});

  final String sizeId;
  final String spongeId;
  final String fillingId;
  final String frostingId;
  final bool eggless;
  final String message;
  final String fontId;

  CakeChoice copyWith({String? sizeId, String? spongeId, String? fillingId, String? frostingId, bool? eggless, String? message, String? fontId}) => CakeChoice(
        sizeId: sizeId ?? this.sizeId,
        spongeId: spongeId ?? this.spongeId,
        fillingId: fillingId ?? this.fillingId,
        frostingId: frostingId ?? this.frostingId,
        eggless: eggless ?? this.eggless,
        message: message ?? this.message,
        fontId: fontId ?? this.fontId,
      );

  Json toJson() => {
        'sizeId': sizeId,
        'spongeId': spongeId,
        'fillingId': fillingId,
        'frostingId': frostingId,
        'eggless': eggless,
        'message': message,
        'fontId': fontId,
      };

  factory CakeChoice.fromJson(Json j) => CakeChoice(
        sizeId: j['sizeId'] as String,
        spongeId: j['spongeId'] as String,
        fillingId: j['fillingId'] as String,
        frostingId: j['frostingId'] as String,
        eggless: j['eggless'] as bool? ?? false,
        message: j['message'] as String? ?? '',
        fontId: j['fontId'] as String? ?? 'SCRIPT',
      );

  @override
  bool operator ==(Object other) => other is CakeChoice && other.toJson().toString() == toJson().toString();

  @override
  int get hashCode => toJson().toString().hashCode;
}

/// A cake as stored on an order line or saved blueprint (choice + resolved names/prices).
class ResolvedCake {
  const ResolvedCake(this.raw);
  final Json raw;

  CakeChoice get choice => CakeChoice.fromJson(raw);
  String get sizeLabel => raw['sizeLabel'] as String? ?? '';
  String get spongeFlavor => raw['spongeFlavor'] as String? ?? '';
  String get fillingFlavor => raw['fillingFlavor'] as String? ?? '';
  String get frostingType => raw['frostingType'] as String? ?? '';
  String get pipedMessage => raw['pipedMessage'] as String? ?? '';
  String get pipingFont => raw['pipingFont'] as String? ?? 'SCRIPT';
  bool get isEggless => raw['isEggless'] as bool? ?? false;
  int get extraPrice => _int(raw['extraPrice']);

  /// "1 kg · Red Velvet · Raspberry Compote · “Mubarak”"
  String get summary => [
        sizeLabel,
        spongeFlavor,
        fillingFlavor,
        frostingType,
        if (isEggless) 'Eggless',
        if (pipedMessage.isNotEmpty) '“$pipedMessage”',
      ].where((s) => s.isNotEmpty).join(' · ');
}

// ── Orders ────────────────────────────────────────────────────────────────────

class Pricing {
  const Pricing({this.subtotal = 0, this.customCakeSurcharge = 0, this.packagingFee = 0, this.deliveryFee = 0, this.promoDiscount = 0, this.loyaltyDiscount = 0, this.total = 0});

  final int subtotal;
  final int customCakeSurcharge;
  final int packagingFee;
  final int deliveryFee;
  final int promoDiscount;
  final int loyaltyDiscount;
  final int total;

  factory Pricing.fromJson(Json? j) => j == null
      ? const Pricing()
      : Pricing(
          subtotal: _int(j['subtotal']),
          customCakeSurcharge: _int(j['customCakeSurcharge']),
          packagingFee: _int(j['packagingFee']),
          deliveryFee: _int(j['deliveryFee']),
          promoDiscount: _int(j['promoDiscount']),
          loyaltyDiscount: _int(j['loyaltyDiscount']),
          total: _int(j['total']),
        );
}

class OrderSlot {
  const OrderSlot({required this.date, required this.startMinute, required this.endMinute, required this.label});
  final String date;
  final int startMinute;
  final int endMinute;
  final String label;

  factory OrderSlot.fromJson(Json j) =>
      OrderSlot(date: j['date'] as String, startMinute: _int(j['startMinute']), endMinute: _int(j['endMinute']), label: j['label'] as String? ?? '');
}

class OrderLine {
  const OrderLine({required this.lineType, required this.productId, required this.productName, this.imageUrl, this.category, required this.quantity, required this.unitPrice, this.customization, this.specialInstructions});

  final String lineType;
  final String productId;
  final String productName;
  final String? imageUrl;
  final String? category;
  final int quantity;
  final int unitPrice;
  final ResolvedCake? customization;
  final String? specialInstructions;

  bool get isAddOn => lineType == 'ADDON';
  int get lineTotal => unitPrice * quantity;

  factory OrderLine.fromJson(Json j) => OrderLine(
        lineType: j['lineType'] as String? ?? 'PRODUCT',
        productId: j['productId'] as String,
        productName: j['productName'] as String,
        imageUrl: j['imageUrl'] as String?,
        category: j['category'] as String?,
        quantity: _int(j['quantity'], 1),
        unitPrice: _int(j['unitPrice']),
        customization: j['customization'] == null ? null : ResolvedCake(j['customization'] as Json),
        specialInstructions: j['specialInstructions'] as String?,
      );
}

class StatusEntry {
  const StatusEntry({required this.status, required this.at, this.by, this.reason});
  final OrderStatus status;
  final DateTime at;
  final String? by;
  final String? reason;

  factory StatusEntry.fromJson(Json j) => StatusEntry(
        status: OrderStatus.fromWire(j['status'] as String?),
        at: _date(j['at']) ?? DateTime.now(),
        by: j['by'] as String?,
        reason: j['reason'] as String?,
      );
}

class OrderCustomer {
  const OrderCustomer({required this.name, required this.email, this.phone});
  final String name;
  final String email;
  final String? phone;
}

class Order {
  const Order({
    required this.id,
    required this.userId,
    this.customer,
    required this.hubId,
    required this.hubName,
    required this.status,
    required this.fulfillmentType,
    required this.slot,
    this.deliveryAddress,
    required this.paymentMethod,
    this.promoCode,
    required this.pricing,
    this.pickupCode,
    this.stampsEarned = 0,
    this.loyaltyRedeemed = false,
    this.statusHistory = const [],
    this.customerNote,
    this.createdAt,
    required this.lines,
  });

  final String id;
  final String userId;
  final OrderCustomer? customer;
  final String hubId;
  final String hubName;
  final OrderStatus status;
  final FulfillmentType fulfillmentType;
  final OrderSlot slot;
  final String? deliveryAddress;
  final PaymentMethod paymentMethod;
  final String? promoCode;
  final Pricing pricing;
  final String? pickupCode;
  final int stampsEarned;
  final bool loyaltyRedeemed;
  final List<StatusEntry> statusHistory;
  final String? customerNote;
  final DateTime? createdAt;
  final List<OrderLine> lines;

  String get statusTitle => status.titleFor(fulfillmentType);
  List<OrderLine> get productLines => lines.where((l) => !l.isAddOn).toList();
  int get itemCount => productLines.fold(0, (s, l) => s + l.quantity);
  bool get isActive => !status.isFinished;

  String itemsSummary({int maxNames = 2}) {
    final names = productLines.take(maxNames).map((l) => l.quantity > 1 ? '${l.quantity}× ${l.productName}' : l.productName).join(', ');
    final extra = productLines.length - maxNames;
    return extra > 0 ? '$names +$extra more' : names;
  }

  factory Order.fromJson(Json j) {
    final c = j['customer'] as Json?;
    return Order(
      id: j['id'] as String,
      userId: j['userId'] as String,
      customer: c == null ? null : OrderCustomer(name: c['name'] as String? ?? '', email: c['email'] as String? ?? '', phone: c['phone'] as String?),
      hubId: j['hubId'] as String,
      hubName: j['hubName'] as String? ?? '',
      status: OrderStatus.fromWire(j['status'] as String?),
      fulfillmentType: FulfillmentType.fromWire(j['fulfillmentType'] as String?),
      slot: OrderSlot.fromJson(j['slot'] as Json),
      deliveryAddress: j['deliveryAddress'] as String?,
      paymentMethod: PaymentMethod.fromWire(j['paymentMethod'] as String?),
      promoCode: j['promoCode'] as String?,
      pricing: Pricing.fromJson(j['pricing'] as Json?),
      pickupCode: j['pickupCode'] as String?,
      stampsEarned: _int(j['stampsEarned']),
      loyaltyRedeemed: j['loyaltyRedeemed'] as bool? ?? false,
      statusHistory: (j['statusHistory'] as List? ?? const []).map((e) => StatusEntry.fromJson(e as Json)).toList(),
      customerNote: j['customerNote'] as String?,
      createdAt: _date(j['createdAt']),
      lines: (j['lines'] as List? ?? const []).map((e) => OrderLine.fromJson(e as Json)).toList(),
    );
  }
}

// ── Checkout ──────────────────────────────────────────────────────────────────

class SlotOption {
  const SlotOption({required this.date, required this.startMinute, required this.endMinute, required this.label, required this.available, this.reason});
  final String date;
  final int startMinute;
  final int endMinute;
  final String label;
  final bool available;
  final String? reason;

  factory SlotOption.fromJson(Json j) => SlotOption(
        date: j['date'] as String,
        startMinute: _int(j['startMinute']),
        endMinute: _int(j['endMinute']),
        label: j['label'] as String,
        available: j['available'] as bool? ?? false,
        reason: j['reason'] as String?,
      );
}

class SlotDay {
  const SlotDay({required this.date, required this.label, required this.options});
  final String date;
  final String label;
  final List<SlotOption> options;

  bool get hasAvailable => options.any((o) => o.available);

  factory SlotDay.fromJson(Json j) => SlotDay(
        date: j['date'] as String,
        label: j['label'] as String,
        options: (j['options'] as List).map((e) => SlotOption.fromJson(e as Json)).toList(),
      );
}

class LoyaltyStatus {
  const LoyaltyStatus({this.stampsEarned = 0, this.rewardsRedeemed = 0, this.stampsAvailable = 0, this.rewardsAvailable = 0, this.stampsOnCard = 0, this.stampsPerReward = 12, this.rewardValue, this.redeemed = false});

  final int stampsEarned;
  final int rewardsRedeemed;
  final int stampsAvailable;
  final int rewardsAvailable;
  final int stampsOnCard;
  final int stampsPerReward;
  final int? rewardValue;
  final bool redeemed;

  factory LoyaltyStatus.fromJson(Json j) => LoyaltyStatus(
        stampsEarned: _int(j['stampsEarned']),
        rewardsRedeemed: _int(j['rewardsRedeemed']),
        stampsAvailable: _int(j['stampsAvailable']),
        rewardsAvailable: _int(j['rewardsAvailable']),
        stampsOnCard: _int(j['stampsOnCard']),
        stampsPerReward: _int(j['stampsPerReward'], 12),
        rewardValue: j['rewardValue'] == null ? null : _int(j['rewardValue']),
        redeemed: j['redeemed'] as bool? ?? false,
      );
}

class StockIssue {
  const StockIssue({required this.productId, required this.name, required this.available, required this.requested});
  final String productId;
  final String name;
  final int available;
  final int requested;

  factory StockIssue.fromJson(Json j) =>
      StockIssue(productId: j['productId'] as String, name: j['name'] as String, available: _int(j['available']), requested: _int(j['requested']));
}

class Quote {
  const Quote({required this.pricing, this.promoCode, this.promoDescription, this.promoError, required this.loyalty, this.slotError, this.deliveryError, this.stockIssues = const [], this.blockingIssue, required this.canPlace, this.lineUnitPrices = const {}});

  final Pricing pricing;
  final String? promoCode;
  final String? promoDescription;
  final String? promoError;
  final LoyaltyStatus loyalty;
  final String? slotError;
  final String? deliveryError;
  final List<StockIssue> stockIssues;
  final String? blockingIssue;
  final bool canPlace;
  final Map<int, int> lineUnitPrices;

  factory Quote.fromJson(Json j) {
    final promo = j['promo'] as Json?;
    final lines = (j['lines'] as List? ?? const []);
    return Quote(
      pricing: Pricing.fromJson(j['pricing'] as Json?),
      promoCode: promo?['code'] as String?,
      promoDescription: promo?['description'] as String?,
      promoError: j['promoError'] as String?,
      loyalty: LoyaltyStatus.fromJson(j['loyalty'] as Json? ?? const {}),
      slotError: j['slotError'] as String?,
      deliveryError: j['deliveryError'] as String?,
      stockIssues: (j['stockIssues'] as List? ?? const []).map((e) => StockIssue.fromJson(e as Json)).toList(),
      blockingIssue: j['blockingIssue'] as String?,
      canPlace: j['canPlace'] as bool? ?? false,
      lineUnitPrices: {for (var i = 0; i < lines.length; i++) i: _int((lines[i] as Json)['unitPrice'])},
    );
  }
}

class SavedCake {
  const SavedCake({required this.id, required this.productId, required this.name, required this.customization, this.createdAt});
  final int id;
  final String productId;
  final String name;
  final ResolvedCake customization;
  final DateTime? createdAt;

  factory SavedCake.fromJson(Json j) => SavedCake(
        id: _int(j['id']),
        productId: j['productId'] as String,
        name: j['name'] as String,
        customization: ResolvedCake(j['customization'] as Json),
        createdAt: _date(j['createdAt']),
      );
}

class ZoneResult {
  const ZoneResult({required this.inZone, this.hub, this.distanceKm});
  final bool inZone;

  /// The serving hub when in zone; the nearest hub when out of zone.
  final Hub? hub;
  final double? distanceKm;

  factory ZoneResult.fromJson(Json j) {
    final hub = (j['hub'] ?? j['nearestHub']) as Json?;
    return ZoneResult(
      inZone: j['inZone'] as bool? ?? false,
      hub: hub == null ? null : Hub.fromJson(hub),
      distanceKm: j['distanceKm'] == null ? null : _double(j['distanceKm']),
    );
  }
}

// ── Staff & admin ─────────────────────────────────────────────────────────────

class StockItem {
  const StockItem({required this.product, required this.stock});
  final Product product;
  final ProductStock stock;

  factory StockItem.fromJson(Json j) => StockItem(product: Product.fromJson(j['product'] as Json), stock: ProductStock.fromJson(j['stock'] as Json?));
}

class Promo {
  const Promo({required this.code, required this.description, required this.type, this.value = 0, this.minSpend = 0, this.maxDiscount, this.isActive = true, this.expiresAt});

  final String code;
  final String description;
  final String type;
  final int value;
  final int minSpend;
  final int? maxDiscount;
  final bool isActive;
  final DateTime? expiresAt;

  factory Promo.fromJson(Json j) => Promo(
        code: j['code'] as String,
        description: j['description'] as String? ?? '',
        type: j['type'] as String,
        value: _int(j['value']),
        minSpend: _int(j['minSpend']),
        maxDiscount: j['maxDiscount'] == null ? null : _int(j['maxDiscount']),
        isActive: j['isActive'] as bool? ?? true,
        expiresAt: _date(j['expiresAt']),
      );

  Json toJson() => {
        'description': description,
        'type': type,
        'value': value,
        'minSpend': minSpend,
        'maxDiscount': maxDiscount,
        'isActive': isActive,
        'expiresAt': expiresAt?.toUtc().toIso8601String(),
      };
}

class SalesReport {
  const SalesReport(this.raw);
  final Json raw;

  String get from => raw['from'] as String;
  String get to => raw['to'] as String;
  Json get _totals => raw['totals'] as Json? ?? const {};
  int get orders => _int(_totals['orders']);
  int get revenue => _int(_totals['revenue']);
  int get averageOrder => _int(_totals['averageOrder']);
  int get cancelled => _int(_totals['cancelled']);
  int get deliveries => _int(_totals['deliveries']);
  int get customers => _int(_totals['customers']);

  List<({String day, int orders, int revenue})> get byDay => (raw['byDay'] as List? ?? const [])
      .map((e) => (day: (e as Json)['day'] as String, orders: _int(e['orders']), revenue: _int(e['revenue'])))
      .toList();

  List<({String hubName, int orders, int revenue})> get byHub => (raw['byHub'] as List? ?? const [])
      .map((e) => (hubName: (e as Json)['hubName'] as String, orders: _int(e['orders']), revenue: _int(e['revenue'])))
      .toList();

  List<({String name, int quantity, int revenue})> get topProducts => (raw['topProducts'] as List? ?? const [])
      .map((e) => (name: (e as Json)['name'] as String, quantity: _int(e['quantity']), revenue: _int(e['revenue'])))
      .toList();
}
