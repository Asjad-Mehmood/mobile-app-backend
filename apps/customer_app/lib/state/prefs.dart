import 'dart:convert';

import 'package:crumb_core/crumb_core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// How the customer gets their bakes: pickup branch or delivery address (+ serving branch).
class FulfillmentPrefs {
  const FulfillmentPrefs({this.onboarded = false, this.type = FulfillmentType.pickup, this.hubId, this.address, this.lat, this.lng});

  final bool onboarded;
  final FulfillmentType type;
  final String? hubId;
  final String? address;
  final double? lat;
  final double? lng;

  bool get isDelivery => type == FulfillmentType.delivery;

  FulfillmentPrefs copyWith({bool? onboarded, FulfillmentType? type, String? hubId, String? address, double? lat, double? lng}) => FulfillmentPrefs(
        onboarded: onboarded ?? this.onboarded,
        type: type ?? this.type,
        hubId: hubId ?? this.hubId,
        address: address ?? this.address,
        lat: lat ?? this.lat,
        lng: lng ?? this.lng,
      );

  Json toJson() => {'onboarded': onboarded, 'type': type.wire, 'hubId': hubId, 'address': address, 'lat': lat, 'lng': lng};

  factory FulfillmentPrefs.fromJson(Json j) => FulfillmentPrefs(
        onboarded: j['onboarded'] as bool? ?? false,
        type: FulfillmentType.fromWire(j['type'] as String?),
        hubId: j['hubId'] as String?,
        address: j['address'] as String?,
        lat: (j['lat'] as num?)?.toDouble(),
        lng: (j['lng'] as num?)?.toDouble(),
      );
}

final fulfillmentProvider = NotifierProvider<FulfillmentNotifier, FulfillmentPrefs>(FulfillmentNotifier.new);

class FulfillmentNotifier extends Notifier<FulfillmentPrefs> {
  static const _key = 'fulfillment';

  @override
  FulfillmentPrefs build() {
    final raw = ref.read(storageProvider).getString(_key);
    if (raw == null) return const FulfillmentPrefs();
    try {
      return FulfillmentPrefs.fromJson(jsonDecode(raw) as Json);
    } catch (_) {
      return const FulfillmentPrefs();
    }
  }

  Future<void> _save(FulfillmentPrefs p) async {
    state = p;
    await ref.read(storageProvider).setString(_key, jsonEncode(p.toJson()));
  }

  Future<void> choosePickup(String hubId) => _save(FulfillmentPrefs(onboarded: true, type: FulfillmentType.pickup, hubId: hubId, address: state.address, lat: state.lat, lng: state.lng));

  Future<void> chooseDelivery({required String hubId, required String address, required double lat, required double lng}) =>
      _save(FulfillmentPrefs(onboarded: true, type: FulfillmentType.delivery, hubId: hubId, address: address, lat: lat, lng: lng));
}

/// Stamps the customer has already watched being pressed (so only new ones animate).
final seenStampsProvider = NotifierProvider<SeenStampsNotifier, int>(SeenStampsNotifier.new);

class SeenStampsNotifier extends Notifier<int> {
  @override
  int build() => int.tryParse(ref.read(storageProvider).getString('seen_stamps') ?? '') ?? -1;

  Future<void> set(int earned) async {
    state = earned;
    await ref.read(storageProvider).setString('seen_stamps', '$earned');
  }
}
