import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../models/enums.dart';
import '../models/models.dart';

/// An error safe to show to users (server message or a friendly network message).
class ApiException implements Exception {
  const ApiException(this.status, this.code, this.message);
  final int status;
  final String code;
  final String message;

  bool get isNetwork => code == 'NETWORK';
  bool get isUnauthorized => status == 401;

  @override
  String toString() => message;
}

/// One item in a checkout/quote/slots request.
class CartItemInput {
  const CartItemInput({required this.productId, required this.quantity, this.customization, this.specialInstructions});
  final String productId;
  final int quantity;
  final CakeChoice? customization;
  final String? specialInstructions;

  Json toJson() => {
        'productId': productId,
        'quantity': quantity,
        if (customization != null) 'customization': customization!.toJson(),
        if (specialInstructions != null && specialInstructions!.isNotEmpty) 'specialInstructions': specialInstructions,
      };
}

class CheckoutInput {
  const CheckoutInput({
    required this.hubId,
    required this.fulfillmentType,
    required this.items,
    this.slotDate,
    this.slotStartMinute,
    this.deliveryAddress,
    this.deliveryLat,
    this.deliveryLng,
    this.paymentMethod = PaymentMethod.cash,
    this.promoCode,
    this.redeemReward = false,
    this.addOns = const [],
    this.customerNote,
  });

  final String hubId;
  final FulfillmentType fulfillmentType;
  final List<CartItemInput> items;
  final String? slotDate;
  final int? slotStartMinute;
  final String? deliveryAddress;
  final double? deliveryLat;
  final double? deliveryLng;
  final PaymentMethod paymentMethod;
  final String? promoCode;
  final bool redeemReward;
  final List<String> addOns;
  final String? customerNote;

  Json toJson() => {
        'hubId': hubId,
        'fulfillmentType': fulfillmentType.wire,
        'slot': slotDate == null || slotStartMinute == null ? null : {'date': slotDate, 'startMinute': slotStartMinute},
        'deliveryAddress': deliveryAddress,
        'deliveryLat': deliveryLat,
        'deliveryLng': deliveryLng,
        'paymentMethod': paymentMethod.wire,
        'promoCode': (promoCode?.trim().isEmpty ?? true) ? null : promoCode!.trim(),
        'redeemReward': redeemReward,
        'addOns': addOns,
        'items': items.map((i) => i.toJson()).toList(),
        'customerNote': (customerNote?.trim().isEmpty ?? true) ? null : customerNote!.trim(),
      };
}

typedef AuthResult = ({String token, AppUser user});

/// Typed client for the Crumb & Craft API. Both apps share it.
class ApiClient {
  ApiClient({required this.baseUrl, this.token, http.Client? client, this.onUnauthorized}) : _http = client ?? clientFactory?.call() ?? http.Client();

  /// Test hook: supplies the HTTP client for every [ApiClient] created without one.
  static http.Client Function()? clientFactory;

  final String baseUrl;
  final String? token;
  final http.Client _http;

  /// Called when the server says the session is no longer valid.
  final void Function()? onUnauthorized;

  static const _timeout = Duration(seconds: 20);

  Uri _uri(String path, [Map<String, String?>? query]) {
    final base = baseUrl.endsWith('/') ? baseUrl.substring(0, baseUrl.length - 1) : baseUrl;
    final q = {for (final e in (query ?? const {}).entries) if (e.value != null && e.value!.isNotEmpty) e.key: e.value!};
    return Uri.parse('$base$path').replace(queryParameters: q.isEmpty ? null : q);
  }

  Future<dynamic> _send(String method, String path, {Object? body, Map<String, String?>? query}) async {
    final req = http.Request(method, _uri(path, query));
    req.headers['accept'] = 'application/json';
    if (token != null) req.headers['authorization'] = 'Bearer $token';
    if (body != null) {
      req.headers['content-type'] = 'application/json';
      req.body = jsonEncode(body);
    }
    http.Response res;
    try {
      res = await http.Response.fromStream(await _http.send(req).timeout(_timeout));
    } on TimeoutException {
      throw const ApiException(0, 'NETWORK', 'The bakery server is taking too long to answer. Check your connection and try again.');
    } on SocketException {
      throw const ApiException(0, 'NETWORK', "You're offline — check your connection and try again.");
    } on http.ClientException {
      throw const ApiException(0, 'NETWORK', "Couldn't reach the bakery server. Check your connection and try again.");
    }

    final text = utf8.decode(res.bodyBytes);
    dynamic data;
    if (text.isNotEmpty) {
      try {
        data = jsonDecode(text);
      } catch (_) {
        data = null;
      }
    }
    if (res.statusCode >= 200 && res.statusCode < 300) return data;

    final err = data is Map ? data['error'] : null;
    final ex = ApiException(
      res.statusCode,
      err is Map ? '${err['code']}' : 'HTTP_${res.statusCode}',
      err is Map ? '${err['message']}' : 'Something went wrong (${res.statusCode}). Please try again.',
    );
    if (ex.isUnauthorized && token != null) onUnauthorized?.call();
    throw ex;
  }

  Future<dynamic> get(String path, [Map<String, String?>? query]) => _send('GET', path, query: query);
  Future<dynamic> post(String path, [Object? body]) => _send('POST', path, body: body ?? const {});
  Future<dynamic> put(String path, Object body) => _send('PUT', path, body: body);
  Future<dynamic> patch(String path, Object body) => _send('PATCH', path, body: body);
  Future<dynamic> delete(String path) => _send('DELETE', path);

  static List<T> _list<T>(dynamic v, T Function(Json) f) => (v as List).map((e) => f(e as Json)).toList();

  // ── Public ──
  Future<bool> health() async => ((await get('/health')) as Json)['ok'] == true;
  Future<BusinessSettings> config() async => BusinessSettings(await get('/config') as Json);
  Future<List<Hub>> hubs() async => _list(await get('/hubs'), Hub.fromJson);
  Future<Catalog> catalog(String? hubId) async => Catalog.fromJson(await get('/catalog', {'hubId': hubId}) as Json);
  Future<ZoneResult> zoneCheck(double lat, double lng) async => ZoneResult.fromJson(await post('/zone-check', {'latitude': lat, 'longitude': lng}) as Json);

  // ── Auth ──
  AuthResult _auth(dynamic j) => (token: (j as Json)['token'] as String, user: AppUser.fromJson(j['user'] as Json));

  Future<AuthResult> register({required String email, required String password, required String name, String? phone}) async =>
      _auth(await post('/auth/register', {'email': email, 'password': password, 'name': name, if (phone != null && phone.isNotEmpty) 'phone': phone}));

  Future<AuthResult> login(String email, String password) async => _auth(await post('/auth/login', {'email': email, 'password': password}));

  Future<AppUser> me() async => AppUser.fromJson(((await get('/auth/me')) as Json)['user'] as Json);

  Future<AppUser> updateMe({String? name, String? phone}) async =>
      AppUser.fromJson(((await patch('/auth/me', {'name': ?name, 'phone': ?phone})) as Json)['user'] as Json);

  Future<void> changePassword(String current, String next) => post('/auth/password', {'currentPassword': current, 'newPassword': next});

  // ── Customer ──
  Future<Set<String>> favorites() async => ((await get('/me/favorites')) as List).map((e) => '$e').toSet();
  Future<void> setFavorite(String productId, bool favorite) => favorite ? put('/me/favorites/$productId', const {}) : delete('/me/favorites/$productId');

  Future<List<SavedCake>> savedCakes() async => _list(await get('/me/saved-cakes'), SavedCake.fromJson);
  Future<SavedCake> saveCake(String productId, String name, CakeChoice choice) async =>
      SavedCake.fromJson(await post('/me/saved-cakes', {'productId': productId, 'name': name, 'customization': choice.toJson()}) as Json);
  Future<void> deleteSavedCake(int id) => delete('/me/saved-cakes/$id');

  Future<LoyaltyStatus> loyalty() async => LoyaltyStatus.fromJson(await get('/me/loyalty') as Json);

  Future<List<SlotDay>> slots(FulfillmentType type, List<CartItemInput> items) async => _list(
        await post('/orders/slots', {
          'fulfillmentType': type.wire,
          'items': items.map((i) => {'productId': i.productId, if (i.customization != null) 'customization': i.customization!.toJson()}).toList(),
        }),
        SlotDay.fromJson,
      );

  Future<Quote> quote(CheckoutInput input) async => Quote.fromJson(await post('/orders/quote', input.toJson()) as Json);
  Future<Order> placeOrder(CheckoutInput input) async => Order.fromJson(await post('/orders', input.toJson()) as Json);
  Future<List<Order>> myOrders() async => _list(await get('/orders'), Order.fromJson);
  Future<Order> order(String id) async => Order.fromJson(await get('/orders/$id') as Json);
  Future<Order> cancelOrder(String id) async => Order.fromJson(await post('/orders/$id/cancel') as Json);

  // ── Staff ──
  Future<List<Order>> staffOrders({String scope = 'active', String? hubId}) async =>
      _list(await get('/staff/orders', {'scope': scope, 'hubId': hubId}), Order.fromJson);
  Future<Order> staffOrder(String id) async => Order.fromJson(await get('/staff/orders/$id') as Json);
  Future<Order> setOrderStatus(String id, OrderStatus status, {String? reason}) async =>
      Order.fromJson(await post('/staff/orders/$id/status', {'status': status.wire, 'reason': ?reason}) as Json);

  Future<({String hubId, List<StockItem> items})> stock({String? hubId}) async {
    final j = await get('/staff/stock', {'hubId': hubId}) as Json;
    return (hubId: j['hubId'] as String, items: _list(j['items'], StockItem.fromJson));
  }

  Future<void> setStock(String productId, {String? hubId, int? remaining, int? batchNumber}) =>
      patch('/staff/stock/$productId', {'hubId': ?hubId, 'remainingBatchStock': ?remaining, 'currentBatchNumber': ?batchNumber});
  Future<void> startBatch(String productId, int readyInMinutes, {String? hubId}) =>
      post('/staff/stock/$productId/start-batch', {'hubId': ?hubId, 'readyInMinutes': readyInMinutes});
  Future<void> batchOut(String productId, int quantity, {String? hubId}) =>
      post('/staff/stock/$productId/batch-out', {'hubId': ?hubId, 'quantity': quantity});

  // ── Admin ──
  Future<List<Product>> adminProducts() async => _list(await get('/admin/products'), Product.fromJson);
  Future<Product> createProduct(String id, Product p) async => Product.fromJson(await post('/admin/products', {...p.toAdminJson(), 'id': id}) as Json);
  Future<Product> updateProduct(Product p) async => Product.fromJson(await put('/admin/products/${p.id}', p.toAdminJson()) as Json);
  Future<void> unlistProduct(String id) => delete('/admin/products/$id');

  Future<List<Hub>> adminHubs() async => _list(await get('/admin/hubs'), Hub.fromJson);
  Future<Hub> createHub(String id, Hub h) async => Hub.fromJson(await post('/admin/hubs', {...h.toJson(), 'id': id}) as Json);
  Future<Hub> updateHub(String id, Hub h) async => Hub.fromJson(await put('/admin/hubs/$id', h.toJson()) as Json);

  Future<List<Promo>> promos() async => _list(await get('/admin/promos'), Promo.fromJson);
  Future<Promo> createPromo(Promo p) async => Promo.fromJson(await post('/admin/promos', {...p.toJson(), 'code': p.code}) as Json);
  Future<Promo> updatePromo(Promo p) async => Promo.fromJson(await put('/admin/promos/${p.code}', p.toJson()) as Json);

  Future<BusinessSettings> adminSettings() async => BusinessSettings(await get('/admin/settings') as Json);
  Future<BusinessSettings> updateSettings(Json patch) async => BusinessSettings(await put('/admin/settings', patch) as Json);

  Future<List<AppUser>> team() async => _list(await get('/admin/users'), AppUser.fromJson);
  Future<AppUser> createTeamMember({required String email, required String password, required String name, String? phone, required UserRole role, String? hubId}) async =>
      AppUser.fromJson(await post('/admin/users', {'email': email, 'password': password, 'name': name, 'phone': ?phone, 'role': role.wire, 'hubId': ?hubId}) as Json);
  Future<AppUser> updateTeamMember(String id, Json patch) async => AppUser.fromJson(await this.patch('/admin/users/$id', patch) as Json);

  Future<SalesReport> report({required String from, required String to, String? hubId}) async =>
      SalesReport(await get('/admin/reports', {'from': from, 'to': to, 'hubId': hubId}) as Json);
}
