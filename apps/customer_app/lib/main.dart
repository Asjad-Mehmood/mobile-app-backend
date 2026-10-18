import 'package:crumb_core/crumb_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'router.dart';
import 'state/data.dart';

void main() => bootstrapCrumbApp(const CrumbCustomerApp());

class CrumbCustomerApp extends ConsumerWidget {
  const CrumbCustomerApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(customerSyncProvider);
    final router = ref.watch(routerProvider);
    return RealtimeLifecycle(
      onResume: () => refreshCustomerData(ref.invalidate),
      child: MaterialApp.router(
        title: 'Crumb & Craft',
        debugShowCheckedModeBanner: false,
        theme: bakeryLightTheme,
        darkTheme: bakeryDarkTheme,
        themeMode: ref.watch(themeModeProvider),
        routerConfig: router,
        builder: (context, child) => AnnotatedRegion<SystemUiOverlayStyle>(
          value: Theme.of(context).brightness == Brightness.dark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark,
          child: child!,
        ),
      ),
    );
  }
}
