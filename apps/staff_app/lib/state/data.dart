import 'package:crumb_core/crumb_core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Which branch an admin is looking at (`null` = all). Staff are pinned to their own branch.
final hubFilterProvider = NotifierProvider<HubFilterNotifier, String?>(HubFilterNotifier.new);

class HubFilterNotifier extends Notifier<String?> {
  @override
  String? build() {
    final user = ref.watch(currentUserProvider);
    if (user?.role == UserRole.staff) return user?.hubId;
    return ref.read(storageProvider).getString('hub_filter');
  }

  Future<void> set(String? hubId) async {
    state = hubId;
    await ref.read(storageProvider).setString('hub_filter', hubId);
  }
}

/// Branch used for the stock screen (stock is always per-branch).
final stockHubProvider = Provider<String?>((ref) {
  final user = ref.watch(currentUserProvider);
  if (user?.role == UserRole.staff && user?.hubId != null) return user!.hubId;
  return ref.watch(hubFilterProvider) ?? ref.watch(hubsProvider).value?.firstOrNull?.id;
});

final orderScopeProvider = NotifierProvider<OrderScopeNotifier, String>(OrderScopeNotifier.new);

class OrderScopeNotifier extends Notifier<String> {
  @override
  String build() => 'active';
  void set(String scope) => state = scope;
}

final staffOrdersProvider = FutureProvider<List<Order>>((ref) async {
  if (ref.watch(currentUserProvider) == null) return [];
  final scope = ref.watch(orderScopeProvider);
  final hubId = ref.watch(hubFilterProvider);
  return ref.read(apiProvider).staffOrders(scope: scope, hubId: hubId);
});

/// Number of orders waiting for the kitchen to start — shown as a badge.
final newOrdersCountProvider = FutureProvider<int>((ref) async {
  if (ref.watch(currentUserProvider) == null) return 0;
  final orders = await ref.read(apiProvider).staffOrders(scope: 'active', hubId: ref.watch(hubFilterProvider));
  return orders.where((o) => o.status == OrderStatus.confirmed).length;
});

final staffOrderProvider = FutureProvider.family<Order, String>((ref, id) => ref.read(apiProvider).staffOrder(id));

final stockProvider = FutureProvider<({String hubId, List<StockItem> items})>((ref) async {
  if (ref.watch(currentUserProvider) == null) return (hubId: '', items: <StockItem>[]);
  return ref.read(apiProvider).stock(hubId: ref.watch(stockHubProvider));
});

// ── Admin ──
final adminProductsProvider = FutureProvider<List<Product>>((ref) => ref.read(apiProvider).adminProducts());
final adminHubsProvider = FutureProvider<List<Hub>>((ref) => ref.read(apiProvider).adminHubs());
final promosProvider = FutureProvider<List<Promo>>((ref) => ref.read(apiProvider).promos());
final adminSettingsProvider = FutureProvider<BusinessSettings>((ref) => ref.read(apiProvider).adminSettings());
final teamProvider = FutureProvider<List<AppUser>>((ref) => ref.read(apiProvider).team());

typedef ReportQuery = ({String from, String to, String? hubId});
final reportProvider = FutureProvider.family<SalesReport, ReportQuery>((ref, q) => ref.read(apiProvider).report(from: q.from, to: q.to, hubId: q.hubId));

/// Latest new-order event, so the shell can alert the team.
final newOrderAlertProvider = NotifierProvider<NewOrderAlert, SyncEvent?>(NewOrderAlert.new);

class NewOrderAlert extends Notifier<SyncEvent?> {
  @override
  SyncEvent? build() => null;
  void push(SyncEvent e) => state = e;
}

/// Refreshes exactly what changed whenever the server pushes an event.
final staffSyncProvider = Provider<void>((ref) {
  ref.listen(syncEventsProvider, (_, next) {
    final e = next.value;
    if (e == null) return;
    handleSharedSyncEvent(ref, e);
    switch (e.type) {
      case 'order.created':
        ref.invalidate(staffOrdersProvider);
        ref.invalidate(newOrdersCountProvider);
        ref.read(newOrderAlertProvider.notifier).push(e);
      case 'order.updated':
        ref.invalidate(staffOrdersProvider);
        ref.invalidate(newOrdersCountProvider);
        if (e.orderId != null) ref.invalidate(staffOrderProvider(e.orderId!));
      case 'stock.updated':
        ref.invalidate(stockProvider);
        ref.invalidate(adminProductsProvider);
      case 'catalog.updated':
        ref.invalidate(stockProvider);
        ref.invalidate(adminProductsProvider);
      case 'hubs.updated':
        ref.invalidate(adminHubsProvider);
      case 'promos.updated':
        ref.invalidate(promosProvider);
      case 'settings.updated':
        ref.invalidate(adminSettingsProvider);
    }
  });
});
