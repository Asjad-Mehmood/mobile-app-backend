import 'package:crumb_core/crumb_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'screens/login_screen.dart';
import 'screens/shell.dart';
import 'state/data.dart';

void main() => bootstrapCrumbApp(const CrumbStaffApp());

class CrumbStaffApp extends ConsumerWidget {
  const CrumbStaffApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(staffSyncProvider);
    final session = ref.watch(sessionProvider);
    final user = session.value?.user;
    final signedIn = user != null && user.isStaffOrAdmin;

    return RealtimeLifecycle(
      onResume: () {
        ref.invalidate(staffOrdersProvider);
        ref.invalidate(newOrdersCountProvider);
        ref.invalidate(stockProvider);
      },
      child: MaterialApp(
        title: 'Crumb & Craft Staff',
        debugShowCheckedModeBanner: false,
        theme: bakeryLightTheme,
        darkTheme: bakeryDarkTheme,
        themeMode: ref.watch(themeModeProvider),
        home: session.isLoading && !session.hasValue
            ? const Scaffold(body: LoadingView())
            : signedIn
                ? const StaffShell()
                : LoginScreen(offline: session.hasError),
      ),
    );
  }
}
