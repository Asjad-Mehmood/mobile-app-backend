import 'package:crumb_core/crumb_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../state/data.dart';
import '../state/prefs.dart';

class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProvider);
    final session = ref.watch(sessionProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Profile')),
      body: ListView(padding: const EdgeInsets.fromLTRB(16, 0, 16, 32), children: [
        if (user == null) ...[
          if (session.hasError)
            BakeryCard(
              child: Text("We couldn't reach the bakery to restore your sign-in. Pull to retry or check the server address below.",
                  style: TextStyle(color: context.colors.error)),
            ),
          const SizedBox(height: 12),
          BakeryCard(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text("Join the Baker's Dozen", style: context.text.headlineSmall),
              const SizedBox(height: 6),
              const Text('Collect a stamp on every order over Rs 1,000 — twelve stamps and your next pastry is on us.'),
              const SizedBox(height: 14),
              BakeryButton(label: 'Sign in or create account', onPressed: () => context.push('/auth')),
            ]),
          ),
        ] else ...[
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: CircleAvatar(
              radius: 26,
              backgroundColor: context.colors.primaryContainer,
              child: Text(user.name.isEmpty ? '?' : user.name[0].toUpperCase(), style: context.text.titleLarge?.copyWith(color: context.colors.onPrimaryContainer)),
            ),
            title: Text(user.name, style: context.text.titleLarge),
            subtitle: Text([user.email, ?user.phone].join(' · ')),
            trailing: IconButton(icon: const Icon(Icons.edit_outlined), tooltip: 'Edit profile', onPressed: () => _editProfile(context, ref, user)),
          ),
          const _LoyaltyCard(),
        ],
        const SizedBox(height: 16),
        Text('Settings', style: context.text.titleLarge),
        const SizedBox(height: 4),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.storefront_outlined),
          title: const Text('Pickup or delivery'),
          subtitle: Text(ref.watch(fulfillmentProvider).isDelivery ? 'Delivery · ${ref.watch(fulfillmentProvider).address ?? ''}' : 'Store pickup'),
          onTap: () => context.push('/fulfillment'),
        ),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.dark_mode_outlined),
          title: const Text('Appearance'),
          trailing: SegmentedButton<ThemeMode>(
            showSelectedIcon: false,
            segments: const [
              ButtonSegment(value: ThemeMode.light, icon: Icon(Icons.light_mode_outlined), tooltip: 'Light'),
              ButtonSegment(value: ThemeMode.system, icon: Icon(Icons.brightness_auto_outlined), tooltip: 'System'),
              ButtonSegment(value: ThemeMode.dark, icon: Icon(Icons.dark_mode_outlined), tooltip: 'Dark'),
            ],
            selected: {ref.watch(themeModeProvider)},
            onSelectionChanged: (s) => ref.read(themeModeProvider.notifier).set(s.first),
          ),
        ),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.dns_outlined),
          title: const Text('Bakery server'),
          subtitle: Text(ref.watch(serverUrlProvider)),
          onTap: () async {
            final url = await showServerUrlDialog(context, ref.read(serverUrlProvider));
            if (url == null) return;
            await ref.read(serverUrlProvider.notifier).set(url);
            refreshCustomerData(ref.invalidate);
            ref.invalidate(hubsProvider);
          },
        ),
        if (user != null) ...[
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.password_outlined),
            title: const Text('Change password'),
            onTap: () => _changePassword(context, ref),
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.logout, color: context.colors.error),
            title: Text('Sign out', style: TextStyle(color: context.colors.error)),
            onTap: () => ref.read(sessionProvider.notifier).signOut(),
          ),
        ],
        const SizedBox(height: 16),
        Center(child: Text('Crumb & Craft · Islamabad · Rawalpindi', style: context.text.bodySmall?.copyWith(color: context.colors.onSurfaceVariant))),
      ]),
    );
  }

  Future<void> _editProfile(BuildContext context, WidgetRef ref, AppUser user) async {
    final name = TextEditingController(text: user.name);
    final phone = TextEditingController(text: user.phone ?? '');
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Your details'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: name, decoration: const InputDecoration(labelText: 'Name')),
          const SizedBox(height: 12),
          TextField(controller: phone, keyboardType: TextInputType.phone, decoration: const InputDecoration(labelText: 'Mobile')),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Save')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      final updated = await ref.read(apiProvider).updateMe(name: name.text.trim(), phone: phone.text.trim());
      ref.read(sessionProvider.notifier).updateUser(updated);
    } catch (e) {
      if (context.mounted) context.toast(errorText(e), error: true);
    }
  }

  Future<void> _changePassword(BuildContext context, WidgetRef ref) async {
    final current = TextEditingController();
    final next = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Change password'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: current, obscureText: true, decoration: const InputDecoration(labelText: 'Current password')),
          const SizedBox(height: 12),
          TextField(controller: next, obscureText: true, decoration: const InputDecoration(labelText: 'New password', helperText: 'At least 8 characters')),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Change')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await ref.read(apiProvider).changePassword(current.text, next.text);
      if (context.mounted) context.toast('Password changed');
    } catch (e) {
      if (context.mounted) context.toast(errorText(e), error: true);
    }
  }
}

class _LoyaltyCard extends ConsumerStatefulWidget {
  const _LoyaltyCard();

  @override
  ConsumerState<_LoyaltyCard> createState() => _LoyaltyCardState();
}

class _LoyaltyCardState extends ConsumerState<_LoyaltyCard> {
  @override
  Widget build(BuildContext context) {
    final loyalty = ref.watch(loyaltyProvider);
    final seen = ref.watch(seenStampsProvider);
    return loyalty.when(
      loading: () => const Padding(padding: EdgeInsets.all(24), child: LoadingView()),
      error: (e, _) => ErrorRetry(error: e, onRetry: () => ref.invalidate(loyaltyProvider)),
      data: (l) {
        if (l == null) return const SizedBox.shrink();
        // Animate only stamps earned since the customer last looked (first visit: none).
        final newly = seen < 0 ? 0 : (l.stampsEarned - seen).clamp(0, l.stampsOnCard);
        if (seen != l.stampsEarned) {
          final seenNotifier = ref.read(seenStampsProvider.notifier);
          Future.delayed(const Duration(seconds: 3), () => seenNotifier.set(l.stampsEarned));
        }
        return BakeryCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(child: Text("Baker's Dozen", style: context.text.headlineSmall)),
              Text('${l.stampsOnCard}/${l.stampsPerReward}', style: context.text.titleMedium?.copyWith(color: context.bakery.waxSeal)),
            ]),
            const SizedBox(height: 4),
            Text(
              l.rewardsAvailable > 0
                  ? 'You have ${l.rewardsAvailable} free pastry ${l.rewardsAvailable == 1 ? 'reward' : 'rewards'} — claim it at checkout.'
                  : '${l.stampsPerReward - l.stampsOnCard} more stamps until a free pastry. One stamp per order over Rs 1,000.',
              style: context.text.bodyMedium?.copyWith(color: context.colors.onSurfaceVariant),
            ),
            const SizedBox(height: 16),
            StampCard(key: ValueKey(l.stampsEarned), stampsOnCard: l.stampsOnCard, newlyEarned: newly, slots: l.stampsPerReward),
          ]),
        );
      },
    );
  }
}
