// End-to-end check of the shared Dart client against a running API.
// Run: API_URL=http://localhost:8080 flutter test test/live_api_test.dart
import 'dart:async';
import 'dart:io';

import 'package:crumb_core/crumb_core.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final url = Platform.environment['API_URL'];
  final skip = url == null ? 'Set API_URL to run against a live server' : null;

  test('customer → kitchen → customer round trip with live sync', () async {
    final anon = ApiClient(baseUrl: url!);
    final config = await anon.config();
    expect(config.cakeSizes, isNotEmpty);
    final hubs = await anon.hubs();
    final f7 = hubs.firstWhere((h) => h.id == 'hub-f7');
    final zone = await anon.zoneCheck(33.7286, 73.0726);
    expect(zone.inZone, isTrue);
    expect(zone.hub!.id, 'hub-f7');

    final catalog = await anon.catalog(f7.id);
    final croissant = catalog.products.firstWhere((p) => p.id == 'pastry-butter-croissant');
    final cake = catalog.products.firstWhere((p) => p.isCustomizableCake);
    final before = croissant.stock.remainingBatchStock;

    // Customer signs up.
    final email = 'dart${DateTime.now().millisecondsSinceEpoch}@test.pk';
    final reg = await anon.register(email: email, password: 'password123', name: 'Dart Tester', phone: '03001234567');
    final me = ApiClient(baseUrl: url, token: reg.token);
    final staff = ApiClient(baseUrl: url, token: (await anon.login('staff.f7@crumbandcraft.pk', 'demo-staff-pass')).token);

    // Both sides listen live.
    final customerRt = RealtimeClient(baseUrl: url, token: reg.token)..connect();
    final staffRt = RealtimeClient(baseUrl: url, token: staff.token)..connect();
    final customerEvents = <SyncEvent>[], staffEvents = <SyncEvent>[];
    customerRt.events.listen(customerEvents.add);
    staffRt.events.listen(staffEvents.add);
    await Future.wait([customerRt.states.firstWhere((s) => s == RealtimeState.live), staffRt.states.firstWhere((s) => s == RealtimeState.live)]);

    // Slots + quote, including a cake (needs 24 h) so pick a slot two days out.
    const choice = CakeChoice(sizeId: 'ONE_KG', spongeId: 'RED_VELVET', fillingId: 'RASPBERRY_COMPOTE', frostingId: 'VANILLA_BUTTERCREAM', message: 'Mubarak');
    final items = [
      const CartItemInput(productId: 'pastry-butter-croissant', quantity: 2),
      CartItemInput(productId: cake.id, quantity: 1, customization: choice),
    ];
    final days = await me.slots(FulfillmentType.pickup, items);
    final slot = days.expand((d) => d.options).firstWhere((o) => o.available);
    final input = CheckoutInput(hubId: f7.id, fulfillmentType: FulfillmentType.pickup, items: items, slotDate: slot.date, slotStartMinute: slot.startMinute, addOns: ['BIRTHDAY_CANDLES']);
    final quote = await me.quote(input);
    expect(quote.canPlace, isTrue, reason: quote.blockingIssue);
    // Client-side preview matches the server's price engine.
    expect(quote.lineUnitPrices[1], previewCakePrice(config, cake.basePrice, choice).unitPrice);

    final order = await me.placeOrder(input);
    expect(order.id, startsWith('CC-'));
    expect(order.pickupCode, startsWith('PU-'));
    expect(order.pricing.total, quote.pricing.total);
    expect(order.lines.where((l) => l.isAddOn), hasLength(1));

    // Kitchen hears the new order and moves it on; the customer's tracker hears that.
    await _until(() => staffEvents.any((e) => e.isNewOrder && e.orderId == order.id));
    final board = await staff.staffOrders();
    expect(board.map((o) => o.id), contains(order.id));
    await staff.setOrderStatus(order.id, OrderStatus.mixing);
    await _until(() => customerEvents.any((e) => e.type == 'order.updated' && e.status == 'MIXING_AND_PROOFING'));
    expect((await me.order(order.id)).status, OrderStatus.mixing);

    // Stock batch: start → countdown visible to customers → batch out adds stock.
    await staff.startBatch('pastry-butter-croissant', 20);
    await _until(() => customerEvents.any((e) => e.type == 'stock.updated'));
    final baking = (await anon.catalog(f7.id)).byId('pastry-butter-croissant')!;
    expect(baking.stock.isBaking(DateTime.now()), isTrue);
    await staff.batchOut('pastry-butter-croissant', 10);
    final after = (await anon.catalog(f7.id)).byId('pastry-butter-croissant')!;
    expect(after.stock.nextBatchReadyAt, isNull);
    // Same-day orders reserve stock; cake slot may be another day, so only check the batch was added.
    expect(after.stock.remainingBatchStock, greaterThanOrEqualTo(before - 2 + 10));

    // Saved cake + favourites + loyalty parse correctly.
    final saved = await me.saveCake(cake.id, 'Eid cake', choice);
    expect(saved.customization.summary, contains('Mubarak'));
    await me.setFavorite(croissant.id, true);
    expect(await me.favorites(), contains(croissant.id));
    final loyalty = await me.loyalty();
    expect(loyalty.stampsPerReward, config.stampsPerReward);

    // Staff can't use admin endpoints; admin reports parse.
    await expectLater(staff.team(), throwsA(isA<ApiException>().having((e) => e.status, 'status', 403)));
    final admin = ApiClient(baseUrl: url, token: (await anon.login('owner@crumbandcraft.pk', 'owner-pass-123')).token);
    final today = isoDate(DateTime.now());
    final report = await admin.report(from: today, to: isoDate(DateTime.now().add(const Duration(days: 1))));
    expect(report.orders, greaterThanOrEqualTo(1));
    expect((await admin.adminProducts()).length, greaterThan(10));
    expect(await admin.promos(), isNotEmpty);

    // Wrong password gives a friendly message.
    await expectLater(anon.login(email, 'nope-nope'), throwsA(isA<ApiException>().having((e) => e.status, 'status', 401)));
    // Offline server gives the NETWORK code.
    await expectLater(ApiClient(baseUrl: 'http://127.0.0.1:1').hubs(), throwsA(isA<ApiException>().having((e) => e.isNetwork, 'network', isTrue)));

    await customerRt.close();
    await staffRt.close();
  }, skip: skip, timeout: const Timeout(Duration(seconds: 60)));
}

Future<void> _until(bool Function() ok) async {
  for (var i = 0; i < 100; i++) {
    if (ok()) return;
    await Future<void>.delayed(const Duration(milliseconds: 100));
  }
  throw TimeoutException('condition not met');
}
