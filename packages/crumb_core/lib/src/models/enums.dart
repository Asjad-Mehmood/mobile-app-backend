enum Allergen {
  gluten('GLUTEN', 'Gluten'),
  dairy('DAIRY', 'Dairy'),
  eggs('EGGS', 'Eggs'),
  nuts('NUTS', 'Nuts'),
  soy('SOY', 'Soy');

  const Allergen(this.wire, this.label);
  final String wire;
  final String label;

  static Allergen? fromWire(String? v) => values.where((e) => e.wire == v).firstOrNull;
}

enum DietaryTag {
  vegan('VEGAN', 'Vegan'),
  eggless('EGGLESS', 'Eggless'),
  sugarFree('SUGAR_FREE', 'Sugar-Free'),
  organic('ORGANIC', 'Organic');

  const DietaryTag(this.wire, this.label);
  final String wire;
  final String label;

  static DietaryTag? fromWire(String? v) => values.where((e) => e.wire == v).firstOrNull;
}

enum ProductCategory {
  bread('BREAD', 'Sourdough & Loaves'),
  pastry('PASTRY', 'Viennoiserie'),
  customCake('CUSTOM_CAKE', 'Artisanal Cakes'),
  cookie('COOKIE', 'Cookies'),
  beverage('BEVERAGE', 'Coffee & Drinks');

  const ProductCategory(this.wire, this.label);
  final String wire;
  final String label;

  static ProductCategory fromWire(String? v) => values.where((e) => e.wire == v).firstOrNull ?? pastry;
}

enum BakeSchedule {
  morning('MORNING_BAKE', 'Morning bake · from 7 AM'),
  afternoon('AFTERNOON_BAKE', 'Afternoon bake · from 1 PM'),
  allDay('ALL_DAY', 'Available all day'),
  preOrder('PRE_ORDER_24H', '24-hour pre-order');

  const BakeSchedule(this.wire, this.label);
  final String wire;
  final String label;

  static BakeSchedule fromWire(String? v) => values.where((e) => e.wire == v).firstOrNull ?? allDay;
}

enum OrderStatus {
  confirmed('ORDER_CONFIRMED', 'Order confirmed', 'Received by the head baker.'),
  mixing('MIXING_AND_PROOFING', 'Mixing & proofing', 'Your dough and batter are being prepared.'),
  oven('IN_THE_OVEN', 'In the oven', 'Baking in progress.'),
  decorating('DECORATING_AND_COOLING', 'Decorating & cooling', 'Frosting, piping and artisanal packaging.'),
  ready('READY_OR_OUT_FOR_DELIVERY', 'Ready', 'Ready for pickup or out for delivery.'),
  completed('COMPLETED', 'Completed', 'Enjoy your bake!'),
  cancelled('CANCELLED', 'Cancelled', 'This order was cancelled.');

  const OrderStatus(this.wire, this.title, this.description);
  final String wire;
  final String title;
  final String description;

  static OrderStatus fromWire(String? v) => values.where((e) => e.wire == v).firstOrNull ?? confirmed;

  /// The five tracker stages (spec §4 Flow 5).
  static const trackerStages = [confirmed, mixing, oven, decorating, ready];

  bool get isFinished => this == completed || this == cancelled;
  bool get isReadyOrLater => this == ready || this == completed;

  /// Next stage in the kitchen flow, or null at the end.
  OrderStatus? get next => switch (this) {
        confirmed => mixing,
        mixing => oven,
        oven => decorating,
        decorating => ready,
        ready => completed,
        completed || cancelled => null,
      };

  /// Title that reads naturally for how the order is fulfilled.
  String titleFor(FulfillmentType type) => switch (this) {
        ready => type == FulfillmentType.delivery ? 'Out for delivery' : 'Ready for pickup',
        completed => type == FulfillmentType.delivery ? 'Delivered' : 'Picked up',
        _ => title,
      };
}

enum FulfillmentType {
  pickup('PICKUP', 'Store Pickup'),
  delivery('DELIVERY', 'Home Delivery');

  const FulfillmentType(this.wire, this.label);
  final String wire;
  final String label;

  static FulfillmentType fromWire(String? v) => values.where((e) => e.wire == v).firstOrNull ?? pickup;
}

enum PaymentMethod {
  cash('CASH_ON_DELIVERY', 'Cash on pickup or delivery'),
  card('CARD', 'Card on pickup or delivery');

  const PaymentMethod(this.wire, this.label);
  final String wire;
  final String label;

  static PaymentMethod fromWire(String? v) => values.where((e) => e.wire == v).firstOrNull ?? cash;
}

enum UserRole {
  customer('customer'),
  staff('staff'),
  admin('admin');

  const UserRole(this.wire);
  final String wire;

  static UserRole fromWire(String? v) => values.where((e) => e.wire == v).firstOrNull ?? customer;
}
