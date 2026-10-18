import 'package:crumb_core/crumb_core.dart';
import 'package:flutter/material.dart';

import 'branches_screen.dart';
import 'menu_screen.dart';
import 'promos_screen.dart';
import 'settings_screen.dart';
import 'team_screen.dart';

/// Admin home: everything that changes what customers see. All edits sync to every app instantly.
class ManageScreen extends StatelessWidget {
  const ManageScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final items = <(IconData, String, String, Widget)>[
      (Icons.bakery_dining_outlined, 'Menu', 'Products, prices, photos, allergens', const MenuScreen()),
      (Icons.storefront_outlined, 'Branches', 'Locations and delivery radius', const BranchesScreen()),
      (Icons.local_offer_outlined, 'Promo codes', 'Discounts and free delivery', const PromosScreen()),
      (Icons.tune_outlined, 'Business settings', 'Fees, prep times, cake options, loyalty', const SettingsScreen()),
      (Icons.groups_outlined, 'Team', 'Staff and admin accounts', const TeamScreen()),
    ];
    return Scaffold(
      appBar: AppBar(title: const Text('Manage')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        Text('Changes here appear in the customer app straight away.', style: context.text.bodyMedium?.copyWith(color: context.colors.onSurfaceVariant)),
        const SizedBox(height: 12),
        for (final (icon, title, subtitle, page) in items)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: BakeryCard(
              onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => page)),
              child: Row(children: [
                Icon(icon, color: context.colors.primary, size: 28),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(title, style: context.text.titleMedium),
                    Text(subtitle, style: context.text.bodySmall?.copyWith(color: context.colors.onSurfaceVariant)),
                  ]),
                ),
                const Icon(Icons.chevron_right),
              ]),
            ),
          ),
      ]),
    );
  }
}
