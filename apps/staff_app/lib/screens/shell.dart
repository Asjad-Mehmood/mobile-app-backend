import 'package:crumb_core/crumb_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../state/data.dart';
import 'account_screen.dart';
import 'admin/manage_screen.dart';
import 'admin/reports_screen.dart';
import 'order_detail_screen.dart';
import 'orders_board.dart';
import 'stock_screen.dart';

class StaffShell extends ConsumerStatefulWidget {
  const StaffShell({super.key});

  @override
  ConsumerState<StaffShell> createState() => _StaffShellState();
}

class _StaffShellState extends ConsumerState<StaffShell> {
  int _index = 0;
  final _messenger = GlobalKey<ScaffoldMessengerState>();

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(currentUserProvider)!;
    final isAdmin = user.isAdmin;
    final newCount = ref.watch(newOrdersCountProvider).value ?? 0;

    // Alert the kitchen when an order lands.
    ref.listen(newOrderAlertProvider, (_, e) {
      if (e == null) return;
      HapticFeedback.heavyImpact();
      SystemSound.play(SystemSoundType.alert);
      _messenger.currentState?.showSnackBar(SnackBar(
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 8),
        content: Text('New order ${e.orderId ?? ''} just came in'),
        action: e.orderId == null
            ? null
            : SnackBarAction(
                label: 'Open',
                onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => OrderDetailScreen(orderId: e.orderId!))),
              ),
      ));
    });

    final pages = <(String, IconData, IconData, Widget)>[
      ('Orders', Icons.receipt_long_outlined, Icons.receipt_long, const OrdersBoard()),
      ('Stock', Icons.inventory_2_outlined, Icons.inventory_2, const StockScreen()),
      if (isAdmin) ('Manage', Icons.tune_outlined, Icons.tune, const ManageScreen()),
      if (isAdmin) ('Reports', Icons.insights_outlined, Icons.insights, const ReportsScreen()),
      ('Account', Icons.person_outline, Icons.person, const AccountScreen()),
    ];
    final index = _index.clamp(0, pages.length - 1);

    Widget icon(int i, bool selected) {
      final ic = Icon(selected ? pages[i].$3 : pages[i].$2);
      return i == 0 ? Badge(isLabelVisible: newCount > 0, label: Text('$newCount'), child: ic) : ic;
    }

    return ScaffoldMessenger(
      key: _messenger,
      child: LayoutBuilder(builder: (context, c) {
        final wide = c.maxWidth >= 840;
        final body = IndexedStack(index: index, children: [for (final p in pages) p.$4]);
        if (wide) {
          return Scaffold(
            body: Row(children: [
              NavigationRail(
                selectedIndex: index,
                onDestinationSelected: (i) => setState(() => _index = i),
                labelType: NavigationRailLabelType.all,
                leading: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  child: Icon(Icons.soup_kitchen_rounded, color: context.colors.primary, size: 32),
                ),
                destinations: [for (var i = 0; i < pages.length; i++) NavigationRailDestination(icon: icon(i, false), selectedIcon: icon(i, true), label: Text(pages[i].$1))],
              ),
              const VerticalDivider(width: 1),
              Expanded(child: body),
            ]),
          );
        }
        return Scaffold(
          body: body,
          bottomNavigationBar: NavigationBar(
            selectedIndex: index,
            onDestinationSelected: (i) => setState(() => _index = i),
            destinations: [for (var i = 0; i < pages.length; i++) NavigationDestination(icon: icon(i, false), selectedIcon: icon(i, true), label: pages[i].$1)],
          ),
        );
      }),
    );
  }
}

/// Branch picker for admins (staff see their own branch name only).
class HubFilterButton extends ConsumerWidget {
  const HubFilterButton({super.key, this.allowAll = true});
  final bool allowAll;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProvider);
    final hubs = ref.watch(hubsProvider).value ?? const [];
    final selected = allowAll ? ref.watch(hubFilterProvider) : ref.watch(stockHubProvider);
    final name = hubs.where((h) => h.id == selected).firstOrNull?.name ?? (allowAll ? 'All branches' : 'Branch');
    if (user?.role == UserRole.staff && user?.hubId != null) {
      return Padding(padding: const EdgeInsets.only(right: 12), child: Pill(name, icon: Icons.storefront));
    }
    return PopupMenuButton<String>(
      tooltip: 'Choose branch',
      onSelected: (v) => ref.read(hubFilterProvider.notifier).set(v.isEmpty ? null : v),
      itemBuilder: (_) => [
        if (allowAll) const PopupMenuItem(value: '', child: Text('All branches')),
        for (final h in hubs) PopupMenuItem(value: h.id, child: Text(h.name)),
      ],
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.storefront, size: 18, color: context.colors.primary),
          const SizedBox(width: 6),
          ConstrainedBox(constraints: const BoxConstraints(maxWidth: 160), child: Text(name, overflow: TextOverflow.ellipsis, style: context.text.labelLarge)),
          const Icon(Icons.arrow_drop_down),
        ]),
      ),
    );
  }
}

class LiveIndicator extends ConsumerWidget {
  const LiveIndicator({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) =>
      Padding(padding: const EdgeInsets.only(right: 12), child: LiveDot(live: ref.watch(realtimeStateProvider).value == RealtimeState.live));
}
