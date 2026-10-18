// Renders the main customer screens with real API data and saves screenshots.
// FIXTURES=... CORE_FONTS=... flutter test --update-goldens test/screens_test.dart
import 'dart:convert';
import 'dart:io';

import 'package:crumb_core/crumb_core.dart';
import 'package:crumb_customer/main.dart';
import 'package:crumb_customer/router.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fixture_api.dart';

void main() {
  final enabled = Platform.environment['FIXTURES'] != null;

  testWidgets('customer screens render', (t) async {
    useFixtureApi();
    await loadFonts();
    phoneSize(t);
    final order = jsonDecode(File('${Platform.environment['FIXTURES']}/order.json').readAsStringSync());
    SharedPreferences.setMockInitialValues({
      '_auth_token': 'fixture-token',
      'fulfillment': jsonEncode({'onboarded': true, 'type': 'PICKUP', 'hubId': 'hub-f7'}),
      'cart_v1': jsonEncode([
        {'productId': 'pastry-butter-croissant', 'name': 'Butter Croissant', 'category': 'PASTRY', 'quantity': 2, 'unitPrice': 550},
        {'productId': 'bread-sourdough-country', 'name': 'Country Sourdough', 'category': 'BREAD', 'quantity': 1, 'unitPrice': 1400},
        {'productId': 'cookie-sea-salt-dark', 'name': 'Sea Salt Dark Chocolate Cookie', 'category': 'COOKIE', 'quantity': 3, 'unitPrice': 450},
      ]),
      'seen_stamps': '0',
    });
    final storage = await AppStorage.open();
    await t.pumpWidget(ProviderScope(
      overrides: [
        storageProvider.overrideWithValue(storage),
        realtimeProvider.overrideWithValue(RealtimeClient(baseUrl: 'http://fixture')),
      ],
      child: const CrumbCustomerApp(),
    ));

    final container = ProviderScope.containerOf(t.element(find.byType(CrumbCustomerApp)));
    final router = container.read(routerProvider);

    Future<void> shot(String path, String name, {Future<void> Function()? then}) async {
      router.go(path);
      for (var i = 0; i < 12; i++) {
        await t.pump(const Duration(milliseconds: 150));
      }
      if (then != null) await then();
      await expectLater(find.byType(MaterialApp), matchesGoldenFile('screens/$name.png'));
    }

    await shot('/home', '01_home');
    await shot('/product/pastry-butter-croissant', '02_product');
    await shot('/cake/cake-strawberry-celebration', '03_cake_builder', then: () async {
      await t.tap(find.text('Next'));
      await t.pump(const Duration(milliseconds: 400));
    });
    await shot('/cakes', '04_cakes');
    await shot('/cart', '05_cart');
    await shot('/checkout', '06_checkout');
    await shot('/track/${order['id']}', '07_tracker');
    await shot('/orders', '08_orders');
    await shot('/profile', '09_profile');
    await shot('/fulfillment', '10_fulfillment');
    await t.pumpWidget(const SizedBox());
    await t.pump(const Duration(seconds: 5));
  }, skip: !enabled);
}
