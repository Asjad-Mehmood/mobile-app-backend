import 'dart:convert';

import 'package:crumb_core/crumb_core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// One cart line. Unit price is a preview — the server re-prices everything at checkout.
class CartLine {
  const CartLine({
    required this.productId,
    required this.name,
    this.imageUrl,
    required this.category,
    required this.quantity,
    required this.unitPrice,
    this.cake,
    this.cakeSummary,
    this.instructions,
  });

  final String productId;
  final String name;
  final String? imageUrl;
  final ProductCategory category;
  final int quantity;
  final int unitPrice;
  final CakeChoice? cake;
  final String? cakeSummary;
  final String? instructions;

  String get key => '$productId|${cake?.toJson()}|${instructions ?? ''}';
  int get lineTotal => unitPrice * quantity;

  CartLine copyWith({int? quantity, int? unitPrice}) => CartLine(
        productId: productId,
        name: name,
        imageUrl: imageUrl,
        category: category,
        quantity: quantity ?? this.quantity,
        unitPrice: unitPrice ?? this.unitPrice,
        cake: cake,
        cakeSummary: cakeSummary,
        instructions: instructions,
      );

  CartItemInput toInput() => CartItemInput(productId: productId, quantity: quantity, customization: cake, specialInstructions: instructions);

  Json toJson() => {
        'productId': productId,
        'name': name,
        'imageUrl': imageUrl,
        'category': category.wire,
        'quantity': quantity,
        'unitPrice': unitPrice,
        'cake': cake?.toJson(),
        'cakeSummary': cakeSummary,
        'instructions': instructions,
      };

  factory CartLine.fromJson(Json j) => CartLine(
        productId: j['productId'] as String,
        name: j['name'] as String,
        imageUrl: j['imageUrl'] as String?,
        category: ProductCategory.fromWire(j['category'] as String?),
        quantity: (j['quantity'] as num).toInt(),
        unitPrice: (j['unitPrice'] as num).toInt(),
        cake: j['cake'] == null ? null : CakeChoice.fromJson(j['cake'] as Json),
        cakeSummary: j['cakeSummary'] as String?,
        instructions: j['instructions'] as String?,
      );
}

final cartProvider = NotifierProvider<CartNotifier, List<CartLine>>(CartNotifier.new);

final cartCountProvider = Provider<int>((ref) => ref.watch(cartProvider).fold(0, (s, l) => s + l.quantity));
final cartSubtotalProvider = Provider<int>((ref) => ref.watch(cartProvider).fold(0, (s, l) => s + l.lineTotal));

/// Cart is kept on the device so it survives restarts.
class CartNotifier extends Notifier<List<CartLine>> {
  static const _key = 'cart_v1';

  @override
  List<CartLine> build() {
    final raw = ref.read(storageProvider).getString(_key);
    if (raw == null) return const [];
    try {
      return (jsonDecode(raw) as List).map((e) => CartLine.fromJson(e as Json)).toList();
    } catch (_) {
      return const [];
    }
  }

  void _set(List<CartLine> lines) {
    state = List.unmodifiable(lines);
    ref.read(storageProvider).setString(_key, jsonEncode(lines.map((l) => l.toJson()).toList()));
  }

  void add(CartLine line) {
    final lines = [...state];
    final i = lines.indexWhere((l) => l.key == line.key);
    if (i >= 0) {
      lines[i] = lines[i].copyWith(quantity: (lines[i].quantity + line.quantity).clamp(1, 50), unitPrice: line.unitPrice);
    } else {
      lines.add(line);
    }
    _set(lines);
  }

  void addProduct(Product p, {int quantity = 1, String? instructions}) => add(CartLine(
        productId: p.id,
        name: p.name,
        imageUrl: p.imageUrl,
        category: p.category,
        quantity: quantity,
        unitPrice: p.basePrice,
        instructions: (instructions?.trim().isEmpty ?? true) ? null : instructions!.trim(),
      ));

  void addCake(Product p, BusinessSettings s, CakeChoice choice, {String? summary}) => add(CartLine(
        productId: p.id,
        name: p.name,
        imageUrl: p.imageUrl,
        category: p.category,
        quantity: 1,
        unitPrice: previewCakePrice(s, p.basePrice, choice).unitPrice,
        cake: choice,
        cakeSummary: summary,
      ));

  void setQuantity(String key, int quantity) {
    if (quantity <= 0) return remove(key);
    _set([for (final l in state) l.key == key ? l.copyWith(quantity: quantity) : l]);
  }

  void remove(String key) => _set(state.where((l) => l.key != key).toList());

  /// Keep previews in line with the server's prices (called by the checkout quote).
  void syncPrices(Map<int, int> unitPricesByIndex) {
    if (unitPricesByIndex.isEmpty) return;
    var changed = false;
    final lines = [...state];
    for (var i = 0; i < lines.length; i++) {
      final p = unitPricesByIndex[i];
      if (p != null && p != lines[i].unitPrice) {
        lines[i] = lines[i].copyWith(unitPrice: p);
        changed = true;
      }
    }
    if (changed) _set(lines);
  }

  void clear() => _set(const []);
}

/// Summary for a cake choice using the bakery's option names.
String cakeSummary(BusinessSettings s, CakeChoice c) {
  String name(List<PricedOption> list, String id) => list.where((o) => o.id == id).firstOrNull?.name ?? id;
  final size = s.cakeSizes.where((x) => x.id == c.sizeId).firstOrNull?.label ?? c.sizeId;
  return [
    size,
    name(s.sponges, c.spongeId),
    name(s.fillings, c.fillingId),
    name(s.frostings, c.frostingId),
    if (c.eggless) 'Eggless',
    if (c.message.trim().isNotEmpty) '“${c.message.trim()}”',
  ].join(' · ');
}
