import 'package:crumb_core/crumb_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';

import '../state/prefs.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final _pages = PageController();
  int _page = 0;

  static const _intro = [
    (Icons.bakery_dining_rounded, 'BAKED AT DAWN', 'Fresh from our ovens, every morning',
        'Slow-fermented sourdough, laminated viennoiserie and celebration cakes from our bakeries in F-7 Islamabad, Saddar Rawalpindi and Bahria Town.'),
    (Icons.local_fire_department_rounded, 'LIVE BATCH TIMERS', "Know the moment it's out of the oven",
        'Live countdowns show exactly when your favourite bake comes out — so it\'s still warm when you get it.'),
    (Icons.cake_rounded, 'CUSTOM CAKES', "Design a cake that's yours alone",
        "Choose the size, sponge, filling and frosting, add a piped message, and we'll bake it fresh with 24 hours' notice."),
  ];

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final last = _page == _intro.length;
    return Scaffold(
      body: SafeArea(
        child: Column(children: [
          Align(
            alignment: Alignment.centerRight,
            child: AnimatedOpacity(
              opacity: last ? 0 : 1,
              duration: const Duration(milliseconds: 200),
              child: TextButton(onPressed: last ? null : () => _pages.animateToPage(_intro.length, duration: const Duration(milliseconds: 350), curve: Curves.easeOut), child: const Text('Skip')),
            ),
          ),
          Expanded(
            child: PageView(
              controller: _pages,
              onPageChanged: (p) => setState(() => _page = p),
              children: [
                for (final (icon, eyebrow, title, body) in _intro) _IntroPage(icon: icon, eyebrow: eyebrow, title: title, body: body),
                const FulfillmentChooser(),
              ],
            ),
          ),
          if (!last)
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
              child: Row(children: [
                for (var i = 0; i <= _intro.length; i++)
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 250),
                    margin: const EdgeInsets.only(right: 6),
                    width: i == _page ? 22 : 8,
                    height: 8,
                    decoration: BoxDecoration(color: i == _page ? context.colors.primary : context.colors.outlineVariant, borderRadius: BorderRadius.circular(4)),
                  ),
                const Spacer(),
                FilledButton(
                  onPressed: () => _pages.nextPage(duration: const Duration(milliseconds: 350), curve: Curves.easeOut),
                  child: const Text('Next'),
                ),
              ]),
            ),
        ]),
      ),
    );
  }
}

class _IntroPage extends StatelessWidget {
  const _IntroPage({required this.icon, required this.eyebrow, required this.title, required this.body});
  final IconData icon;
  final String eyebrow;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 28),
        child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(
            width: 120,
            height: 120,
            decoration: BoxDecoration(color: context.colors.primaryContainer, shape: BoxShape.circle),
            child: Icon(icon, size: 56, color: context.colors.onPrimaryContainer),
          ),
          const SizedBox(height: 36),
          Text(eyebrow, style: context.text.labelMedium?.copyWith(color: context.colors.primary, letterSpacing: 1.6)),
          const SizedBox(height: 10),
          Text(title, style: context.text.displaySmall),
          const SizedBox(height: 16),
          Text(body, style: context.text.bodyLarge?.copyWith(color: context.colors.onSurfaceVariant)),
        ]),
      );
}

/// Standalone screen to change pickup/delivery later.
class FulfillmentScreen extends StatelessWidget {
  const FulfillmentScreen({super.key, this.changing = false});
  final bool changing;

  @override
  Widget build(BuildContext context) => Scaffold(appBar: AppBar(title: const Text('Pickup or delivery')), body: const SafeArea(child: FulfillmentChooser(changing: true)));
}

/// Pickup branch picker or delivery address with zone check (spec Phase 4).
class FulfillmentChooser extends ConsumerStatefulWidget {
  const FulfillmentChooser({super.key, this.changing = false});
  final bool changing;

  @override
  ConsumerState<FulfillmentChooser> createState() => _FulfillmentChooserState();
}

class _FulfillmentChooserState extends ConsumerState<FulfillmentChooser> {
  late FulfillmentType _type = ref.read(fulfillmentProvider).type;
  final _address = TextEditingController();
  bool _checking = false;
  String? _error;
  ZoneResult? _zone;
  ({String address, double lat, double lng})? _checked;

  @override
  void initState() {
    super.initState();
    _address.text = ref.read(fulfillmentProvider).address ?? '';
  }

  @override
  void dispose() {
    _address.dispose();
    super.dispose();
  }

  void _done() {
    if (widget.changing && context.canPop()) {
      context.pop();
    } else {
      context.go('/home');
    }
  }

  Future<void> _pickup(Hub hub) async {
    await ref.read(fulfillmentProvider.notifier).choosePickup(hub.id);
    if (mounted) _done();
  }

  Future<void> _check({required bool useLocation}) async {
    FocusScope.of(context).unfocus();
    setState(() {
      _checking = true;
      _error = null;
      _zone = null;
    });
    try {
      double lat, lng;
      String label;
      if (useLocation) {
        if (!await Geolocator.isLocationServiceEnabled()) throw const _Friendly('Location is turned off — type your address instead.');
        var perm = await Geolocator.checkPermission();
        if (perm == LocationPermission.denied) perm = await Geolocator.requestPermission();
        if (perm == LocationPermission.denied || perm == LocationPermission.deniedForever) {
          throw const _Friendly('Location access was declined — type your address instead.');
        }
        final pos = await Geolocator.getCurrentPosition(locationSettings: const LocationSettings(accuracy: LocationAccuracy.medium, timeLimit: Duration(seconds: 15)));
        lat = pos.latitude;
        lng = pos.longitude;
        label = 'Current location';
        try {
          final marks = await Geocoding().placemarkFromCoordinates(lat, lng);
          final m = marks.firstOrNull;
          if (m != null) {
            label = <String?>[m.street, m.subLocality, m.locality].whereType<String>().where((s) => s.isNotEmpty).toSet().join(', ');
            if (label.isEmpty) label = 'Current location';
          }
        } catch (_) {}
        _address.text = label;
      } else {
        final text = _address.text.trim();
        if (text.length < 3) throw const _Friendly('Enter a street, area or building name.');
        List<Location> found;
        try {
          found = await Geocoding().locationFromAddress(text.toLowerCase().contains('islamabad') || text.toLowerCase().contains('rawalpindi') ? '$text, Pakistan' : '$text, Islamabad, Pakistan');
        } catch (_) {
          found = const [];
        }
        if (found.isEmpty) throw const _Friendly("We couldn't find that address. Try adding the sector or area, e.g. \"Street 5, F-7/2\".");
        lat = found.first.latitude;
        lng = found.first.longitude;
        label = text;
      }
      final zone = await ref.read(apiProvider).zoneCheck(lat, lng);
      setState(() {
        _zone = zone;
        _checked = (address: label, lat: lat, lng: lng);
      });
    } on _Friendly catch (e) {
      setState(() => _error = e.message);
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } catch (_) {
      setState(() => _error = 'Something went wrong. Try again.');
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  Future<void> _confirmDelivery() async {
    final z = _zone, c = _checked;
    if (z == null || c == null || z.hub == null) return;
    await ref.read(fulfillmentProvider.notifier).chooseDelivery(hubId: z.hub!.id, address: c.address, lat: c.lat, lng: c.lng);
    if (mounted) _done();
  }

  @override
  Widget build(BuildContext context) {
    final hubs = ref.watch(hubsProvider);
    final current = ref.watch(fulfillmentProvider);
    return ListView(padding: const EdgeInsets.fromLTRB(24, 8, 24, 32), children: [
      if (!widget.changing) ...[
        Text('PICKUP OR DELIVERY', style: context.text.labelMedium?.copyWith(color: context.colors.primary, letterSpacing: 1.6)),
        const SizedBox(height: 10),
        Text('How would you like your bakes?', style: context.text.headlineMedium),
        const SizedBox(height: 20),
      ],
      SegmentedButton<FulfillmentType>(
        segments: const [
          ButtonSegment(value: FulfillmentType.pickup, icon: Icon(Icons.storefront_outlined), label: Text('Pickup')),
          ButtonSegment(value: FulfillmentType.delivery, icon: Icon(Icons.delivery_dining_outlined), label: Text('Delivery')),
        ],
        selected: {_type},
        onSelectionChanged: (s) => setState(() {
          _type = s.first;
          _error = null;
        }),
      ),
      const SizedBox(height: 20),
      if (_type == FulfillmentType.pickup) ...[
        Text('Choose your bakery', style: context.text.titleLarge),
        const SizedBox(height: 12),
        hubs.when(
          loading: () => const Padding(padding: EdgeInsets.all(24), child: LoadingView()),
          error: (e, _) => ErrorRetry(error: e, onRetry: () => ref.invalidate(hubsProvider)),
          data: (list) => Column(children: [
            for (final h in list)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: BakeryCard(
                  onTap: () => _pickup(h),
                  child: Row(children: [
                    Icon(Icons.storefront_rounded, color: context.colors.primary),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(h.name, style: context.text.titleMedium),
                        Text(h.address, style: context.text.bodySmall?.copyWith(color: context.colors.onSurfaceVariant)),
                      ]),
                    ),
                    if (current.type == FulfillmentType.pickup && current.hubId == h.id && current.onboarded)
                      Icon(Icons.check_circle, color: context.bakery.success)
                    else
                      const Icon(Icons.chevron_right),
                  ]),
                ),
              ),
          ]),
        ),
      ] else ...[
        Text('Where should we deliver?', style: context.text.titleLarge),
        const SizedBox(height: 6),
        Text('We deliver fresh within 15 km of our bakeries. Let\'s check your address.', style: context.text.bodyMedium?.copyWith(color: context.colors.onSurfaceVariant)),
        const SizedBox(height: 16),
        BakeryButton(label: 'Use my current location', icon: Icons.my_location, outlined: true, onPressed: _checking ? null : () => _check(useLocation: true)),
        const SizedBox(height: 12),
        TextField(
          controller: _address,
          textInputAction: TextInputAction.search,
          onSubmitted: (_) => _check(useLocation: false),
          decoration: InputDecoration(
            labelText: 'Street, area or building',
            hintText: 'e.g. House 12, Street 5, F-7/2',
            suffixIcon: IconButton(icon: const Icon(Icons.search), tooltip: 'Check address', onPressed: _checking ? null : () => _check(useLocation: false)),
          ),
        ),
        const SizedBox(height: 16),
        if (_checking)
          const Row(children: [SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2)), SizedBox(width: 12), Text('Checking your delivery zone…')]),
        if (_error != null) Text(_error!, style: TextStyle(color: context.colors.error)),
        if (_zone != null) _ZoneResultCard(zone: _zone!, onDeliver: _confirmDelivery, onPickup: () => _pickup(_zone!.hub!)),
      ],
    ]);
  }
}

class _ZoneResultCard extends StatelessWidget {
  const _ZoneResultCard({required this.zone, required this.onDeliver, required this.onPickup});
  final ZoneResult zone;
  final VoidCallback onDeliver;
  final VoidCallback onPickup;

  String get _km => zone.distanceKm == null ? '' : '${zone.distanceKm!.toStringAsFixed(1)} km';

  @override
  Widget build(BuildContext context) {
    final hub = zone.hub;
    if (hub == null) return const SizedBox.shrink();
    return BakeryCard(
      color: zone.inZone ? context.colors.tertiaryContainer : context.colors.secondaryContainer,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(zone.inZone ? Icons.check_circle_rounded : Icons.info_outline_rounded),
          const SizedBox(width: 10),
          Expanded(child: Text(zone.inZone ? 'Great news — we deliver to you' : 'Just outside our delivery zone', style: context.text.titleMedium)),
        ]),
        const SizedBox(height: 8),
        Text(zone.inZone
            ? 'Fresh from ${hub.name}, $_km away.'
            : "You're $_km from ${hub.name} — beyond our ${hub.deliveryRadiusKm.toStringAsFixed(0)} km fresh-delivery radius."),
        const SizedBox(height: 14),
        if (zone.inZone)
          BakeryButton(label: 'Deliver here', icon: Icons.delivery_dining, onPressed: onDeliver)
        else
          BakeryButton(label: 'Pick up from ${hub.name} instead', icon: Icons.storefront, onPressed: onPickup),
      ]),
    );
  }
}

class _Friendly implements Exception {
  const _Friendly(this.message);
  final String message;
}
