// Renders the staff/admin screens with real API data and saves screenshots.
import 'dart:io';

import 'package:crumb_core/crumb_core.dart';
import 'package:crumb_staff/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fixture_api.dart';

void main() {
  final enabled = Platform.environment['FIXTURES'] != null;

  testWidgets('staff & admin screens render', (t) async {
    useFixtureApi();
    await loadFonts();
    phoneSize(t);
    SharedPreferences.setMockInitialValues({'_auth_token': 'fixture-token'});
    final storage = await AppStorage.open();
    await t.pumpWidget(ProviderScope(
      overrides: [
        storageProvider.overrideWithValue(storage),
        realtimeProvider.overrideWithValue(RealtimeClient(baseUrl: 'http://fixture')),
      ],
      child: const CrumbStaffApp(),
    ));
    Future<void> settle() async {
      for (var i = 0; i < 12; i++) {
        await t.pump(const Duration(milliseconds: 150));
      }
    }

    Future<void> shot(String name) async {
      await settle();
      await expectLater(find.byType(MaterialApp), matchesGoldenFile('screens/$name.png'));
    }

    for (var i = 0; i < 4; i++) {
      await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 200)));
      await settle();
    }
    await shot('01_orders_board');
    await t.tap(find.byType(Card).first);
    await shot('02_order_detail');
    await t.pageBack();
    await settle();
    await t.tap(find.text('Stock').last);
    await shot('03_stock');
    await t.tap(find.text('Manage').last);
    await shot('04_manage');
    await t.tap(find.text('Business settings'));
    await shot('05_settings');
    await t.pageBack();
    await settle();
    await t.tap(find.text('Menu'));
    await shot('06_menu');
    await t.pageBack();
    await settle();
    await t.tap(find.text('Reports').last);
    await shot('07_reports');
    await t.pumpWidget(const SizedBox());
    await t.pump(const Duration(seconds: 5));
  }, skip: !enabled);
}
