import 'package:crumb_core/crumb_core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show ProviderOrFamily;

import 'prefs.dart';

/// Menu + live stock for the customer's branch.
final catalogProvider = FutureProvider<Catalog>((ref) async {
  final hubId = ref.watch(fulfillmentProvider.select((p) => p.hubId));
  ref.watch(serverUrlProvider);
  return ref.read(apiProvider).catalog(hubId);
});

final productProvider = Provider.family<Product?, String>((ref, id) => ref.watch(catalogProvider).value?.byId(id));

final favoritesProvider = AsyncNotifierProvider<FavoritesNotifier, Set<String>>(FavoritesNotifier.new);

class FavoritesNotifier extends AsyncNotifier<Set<String>> {
  @override
  Future<Set<String>> build() async {
    final user = ref.watch(currentUserProvider);
    if (user == null) return {};
    return ref.read(apiProvider).favorites();
  }

  /// Optimistic toggle; rolls back if the server refuses.
  Future<void> toggle(String productId) async {
    final before = state.value ?? {};
    final on = !before.contains(productId);
    state = AsyncData(on ? {...before, productId} : ({...before}..remove(productId)));
    try {
      await ref.read(apiProvider).setFavorite(productId, on);
    } catch (e) {
      state = AsyncData(before);
      rethrow;
    }
  }
}

final myOrdersProvider = FutureProvider<List<Order>>((ref) async {
  if (ref.watch(currentUserProvider) == null) return [];
  return ref.read(apiProvider).myOrders();
});

final orderProvider = FutureProvider.family<Order, String>((ref, id) async {
  ref.watch(currentUserProvider.select((u) => u?.id));
  return ref.read(apiProvider).order(id);
});

final loyaltyProvider = FutureProvider<LoyaltyStatus?>((ref) async {
  if (ref.watch(currentUserProvider) == null) return null;
  return ref.read(apiProvider).loyalty();
});

final savedCakesProvider = FutureProvider<List<SavedCake>>((ref) async {
  if (ref.watch(currentUserProvider) == null) return [];
  return ref.read(apiProvider).savedCakes();
});

/// Listens to the server's live events and refreshes exactly what changed.
final customerSyncProvider = Provider<void>((ref) {
  ref.listen(syncEventsProvider, (_, next) {
    final e = next.value;
    if (e == null) return;
    handleSharedSyncEvent(ref, e);
    final myHub = ref.read(fulfillmentProvider).hubId;
    switch (e.type) {
      case 'catalog.updated':
        ref.invalidate(catalogProvider);
        ref.invalidate(savedCakesProvider);
      case 'stock.updated':
        if (e.hubId == null || e.hubId == myHub) ref.invalidate(catalogProvider);
      case 'hubs.updated':
        ref.invalidate(catalogProvider);
      case 'settings.updated':
        ref.invalidate(loyaltyProvider);
      case 'order.created' || 'order.updated':
        ref.invalidate(myOrdersProvider);
        ref.invalidate(loyaltyProvider);
        if (e.orderId != null) ref.invalidate(orderProvider(e.orderId!));
    }
  });
});

/// Pull-everything refresh (app resumed / pull-to-refresh).
/// Pass `ref.invalidate` from a widget or provider.
void refreshCustomerData(void Function(ProviderOrFamily) invalidate) {
  invalidate(catalogProvider);
  invalidate(myOrdersProvider);
  invalidate(loyaltyProvider);
  invalidate(configProvider);
}
