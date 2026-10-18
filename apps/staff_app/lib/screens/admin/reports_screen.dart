import 'dart:math';

import 'package:crumb_core/crumb_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../state/data.dart';
import '../shell.dart';

class ReportsScreen extends ConsumerStatefulWidget {
  const ReportsScreen({super.key});

  @override
  ConsumerState<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends ConsumerState<ReportsScreen> {
  int _days = 7;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final q = (from: isoDate(now.subtract(Duration(days: _days - 1))), to: isoDate(now), hubId: ref.watch(hubFilterProvider));
    final report = ref.watch(reportProvider(q));

    // Live: new orders refresh the numbers.
    ref.listen(syncEventsProvider, (_, e) {
      if (e.value?.isOrder ?? false) ref.invalidate(reportProvider(q));
    });

    return Scaffold(
      appBar: AppBar(
        title: const Text('Reports'),
        actions: const [HubFilterButton()],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(56),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
            child: SegmentedButton<int>(
              showSelectedIcon: false,
              segments: const [
                ButtonSegment(value: 1, label: Text('Today')),
                ButtonSegment(value: 7, label: Text('7 days')),
                ButtonSegment(value: 30, label: Text('30 days')),
                ButtonSegment(value: 90, label: Text('90 days')),
              ],
              selected: {_days},
              onSelectionChanged: (s) => setState(() => _days = s.first),
            ),
          ),
        ),
      ),
      body: report.when(
        skipLoadingOnRefresh: true,
        loading: () => const LoadingView(),
        error: (e, _) => ErrorRetry(error: e, onRetry: () => ref.invalidate(reportProvider(q))),
        data: (r) => RefreshIndicator(
          onRefresh: () async => ref.invalidate(reportProvider(q)),
          child: ListView(padding: const EdgeInsets.all(16), children: [
            LayoutBuilder(builder: (context, c) {
              final w = c.maxWidth >= 700 ? (c.maxWidth - 36) / 4 : (c.maxWidth - 12) / 2;
              final tiles = [
                ('Revenue', money(r.revenue)),
                ('Orders', '${r.orders}'),
                ('Average order', money(r.averageOrder)),
                ('Customers', '${r.customers}'),
                ('Deliveries', '${r.deliveries}'),
                ('Cancelled', '${r.cancelled}'),
              ];
              return Wrap(spacing: 12, runSpacing: 12, children: [
                for (final (label, value) in tiles)
                  SizedBox(
                    width: w,
                    child: BakeryCard(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(label, style: context.text.labelMedium?.copyWith(color: context.colors.onSurfaceVariant)),
                        const SizedBox(height: 4),
                        FittedBox(fit: BoxFit.scaleDown, child: Text(value, style: context.text.headlineSmall)),
                      ]),
                    ),
                  ),
              ]);
            }),
            if (_days > 1) ...[
              const SectionHeader('Revenue by day', padding: EdgeInsets.only(top: 24, bottom: 10)),
              SizedBox(height: 200, child: _BarChart(points: [for (final d in r.byDay) (d.day.substring(5), d.revenue)])),
            ],
            if (r.byHub.length > 1) ...[
              const SectionHeader('By branch', padding: EdgeInsets.only(top: 24, bottom: 6)),
              for (final h in r.byHub)
                ListTile(contentPadding: EdgeInsets.zero, title: Text(h.hubName), subtitle: Text('${h.orders} orders'), trailing: Text(money(h.revenue), style: context.text.titleSmall)),
            ],
            const SectionHeader('Best sellers', padding: EdgeInsets.only(top: 24, bottom: 6)),
            if (r.topProducts.isEmpty) const Text('No sales in this period yet.'),
            for (final (i, p) in r.topProducts.indexed)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: CircleAvatar(radius: 14, child: Text('${i + 1}', style: context.text.labelSmall)),
                title: Text(p.name),
                subtitle: Text('${p.quantity} sold'),
                trailing: Text(money(p.revenue), style: context.text.titleSmall),
              ),
          ]),
        ),
      ),
    );
  }
}

class _BarChart extends StatelessWidget {
  const _BarChart({required this.points});
  final List<(String, int)> points;

  @override
  Widget build(BuildContext context) {
    if (points.isEmpty) return const Center(child: Text('No sales in this period yet.'));
    final maxV = points.map((p) => p.$2).reduce(max).clamp(1, 1 << 31);
    final showEvery = (points.length / 8).ceil();
    return LayoutBuilder(builder: (context, c) {
      final barW = (c.maxWidth / points.length - 6).clamp(4.0, 48.0);
      return Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
        for (final (i, (label, v)) in points.indexed)
          Expanded(
            child: Tooltip(
              message: '$label · ${money(v)}',
              child: Column(mainAxisAlignment: MainAxisAlignment.end, children: [
                Container(
                  width: barW,
                  height: max(2, (c.maxHeight - 24) * v / maxV),
                  decoration: BoxDecoration(color: context.colors.primary, borderRadius: const BorderRadius.vertical(top: Radius.circular(4))),
                ),
                const SizedBox(height: 6),
                SizedBox(height: 16, child: Text(i % showEvery == 0 ? label : '', style: context.text.labelSmall, overflow: TextOverflow.visible, softWrap: false)),
              ]),
            ),
          ),
      ]);
    });
  }
}
