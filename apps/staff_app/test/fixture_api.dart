import 'dart:convert';
import 'dart:io';

import 'package:crumb_core/crumb_core.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// Serves JSON captured from a real Crumb & Craft API (see FIXTURES env var).
void useFixtureApi() {
  final dir = Platform.environment['FIXTURES']!;
  dynamic load(String name) {
    final data = jsonDecode(File('$dir/$name.json').readAsStringSync());
    _stripImages(data);
    return data;
  }

  ApiClient.clientFactory = () => MockClient((req) async {
        final p = req.url.path;
        final routes = <String, String>{
          'GET /config': 'config',
          'GET /admin/settings': 'admin_settings',
          'GET /hubs': 'hubs',
          'GET /catalog': 'catalog',
          'GET /me/loyalty': 'loyalty',
          'GET /orders': 'orders',
          'GET /me/favorites': 'favorites',
          'GET /me/saved-cakes': 'saved_cakes',
          'POST /orders/slots': 'slots',
          'POST /orders/quote': 'quote',
          'GET /staff/orders': 'staff_orders',
          'GET /staff/stock': 'staff_stock',
          'GET /admin/reports': 'report',
          'GET /admin/products': 'admin_products',
          'GET /admin/hubs': 'hubs',
        };
        String? name = routes['${req.method} $p'];
        if (p == '/auth/me') name = Platform.environment['ME'] ?? 'me';
        if (p.startsWith('/orders/CC-') || p.startsWith('/staff/orders/CC-')) name = 'order';
        if (name == null) return http.Response('{"error":{"code":"NOT_FOUND","message":"no fixture for $p"}}', 404);
        return http.Response(jsonEncode(load(name)), 200, headers: {'content-type': 'application/json; charset=utf-8'});
      });
}

void _stripImages(dynamic v) {
  if (v is Map) {
    if (v.containsKey('imageUrls')) v['imageUrls'] = <String>[];
    if (v.containsKey('imageUrl')) v['imageUrl'] = null;
    v.values.forEach(_stripImages);
  } else if (v is List) {
    v.forEach(_stripImages);
  }
}

Future<void> loadFonts() async {
  final core = Platform.environment['CORE_FONTS']!;
  final sdk = Platform.environment['FLUTTER_ROOT']!;
  Future<void> font(String family, List<String> files) async {
    final loader = FontLoader(family);
    for (final f in files) {
      loader.addFont(Future.value(ByteData.view(File(f).readAsBytesSync().buffer)));
    }
    await loader.load();
  }

  await font('packages/crumb_core/PlayfairDisplay', ['$core/playfair_display.ttf', '$core/playfair_display_italic.ttf']);
  await font('packages/crumb_core/PlusJakartaSans', ['$core/plus_jakarta_sans.ttf']);
  await font('PlusJakartaSans', ['$core/plus_jakarta_sans.ttf']);
  await font('MaterialIcons', ['$sdk/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf']);
}

void phoneSize(WidgetTester t) {
  t.view.physicalSize = const Size(1080, 2340);
  t.view.devicePixelRatio = 2.625;
  addTearDown(t.view.reset);
}
