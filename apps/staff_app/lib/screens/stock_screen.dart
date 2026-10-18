import 'package:crumb_core/crumb_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../state/data.dart';
import 'shell.dart';

/// Shelf stock and oven batches for one branch — feeds the customer app's live countdowns.
class StockScreen extends ConsumerWidget {
  const StockScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stock = ref.watch(stockProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Stock'), actions: const [LiveIndicator(), HubFilterButton(allowAll: false)]),
      body: stock.when(
        skipLoadingOnRefresh: true,
        loading: () => const LoadingView(),
        error: (e, _) => ErrorRetry(error: e, onRetry: () => ref.invalidate(stockProvider)),
        data: (s) => RefreshIndicator(
          onRefresh: () async => ref.invalidate(stockProvider),
          child: ListView.separated(
            padding: const EdgeInsets.all(12),
            itemCount: s.items.length,
            separatorBuilder: (_, _) => const SizedBox(height: 8),
            itemBuilder: (_, i) => _StockTile(item: s.items[i], hubId: s.hubId),
          ),
        ),
      ),
    );
  }
}

class _StockTile extends ConsumerStatefulWidget {
  const _StockTile({required this.item, required this.hubId});
  final StockItem item;
  final String hubId;

  @override
  ConsumerState<_StockTile> createState() => _StockTileState();
}

class _StockTileState extends ConsumerState<_StockTile> {
  bool _busy = false;

  Future<void> _run(Future<void> Function() action, String done) async {
    setState(() => _busy = true);
    try {
      await action();
      HapticFeedback.lightImpact();
      ref.invalidate(stockProvider);
      if (mounted) context.toast(done);
    } catch (e) {
      if (mounted) context.toast(errorText(e), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<int?> _askNumber(String title, String label, int initial, {String? helper}) {
    final ctl = TextEditingController(text: '$initial');
    return showDialog<int>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: ctl,
          autofocus: true,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          decoration: InputDecoration(labelText: label, helperText: helper),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, int.tryParse(ctl.text)), child: const Text('Save')),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.item.product;
    final s = widget.item.stock;
    final api = ref.read(apiProvider);
    final baking = s.isBaking(DateTime.now()) || s.nextBatchReadyAt != null;
    final made = p.isMadeToOrder;

    return BakeryCard(
      padding: const EdgeInsets.all(12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          SizedBox.square(dimension: 52, child: ProductImage(url: p.imageUrl, radius: 10)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(p.name, style: context.text.titleSmall),
              Text(made ? 'Baked to order · no shelf stock' : 'Batch #${s.currentBatchNumber} · ${p.bakeSchedule.label}',
                  style: context.text.bodySmall?.copyWith(color: context.colors.onSurfaceVariant)),
            ]),
          ),
          if (!made) ...[
            IconButton(
              tooltip: 'One less',
              onPressed: _busy || s.remainingBatchStock == 0 ? null : () => _run(() => api.setStock(p.id, hubId: widget.hubId, remaining: s.remainingBatchStock - 1), 'Updated'),
              icon: const Icon(Icons.remove_circle_outline),
            ),
            InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: _busy
                  ? null
                  : () async {
                      final n = await _askNumber('Count on the shelf', 'Pieces left', s.remainingBatchStock);
                      if (n != null) await _run(() => api.setStock(p.id, hubId: widget.hubId, remaining: n), 'Shelf count saved');
                    },
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                child: Text('${s.remainingBatchStock}',
                    style: context.text.headlineSmall?.copyWith(color: s.remainingBatchStock == 0 ? context.colors.error : (s.remainingBatchStock <= 5 ? context.bakery.warning : null))),
              ),
            ),
            IconButton(
              tooltip: 'One more',
              onPressed: _busy ? null : () => _run(() => api.setStock(p.id, hubId: widget.hubId, remaining: s.remainingBatchStock + 1), 'Updated'),
              icon: const Icon(Icons.add_circle_outline),
            ),
          ],
        ]),
        if (!made) ...[
          const SizedBox(height: 8),
          Row(children: [
            if (s.nextBatchReadyAt != null) LiveBakeCountdown(readyAt: s.nextBatchReadyAt!, label: 'Out in') else Text('No batch in the oven', style: context.text.bodySmall),
            const Spacer(),
            if (!baking)
              FilledButton.tonalIcon(
                onPressed: _busy
                    ? null
                    : () async {
                        final m = await _askNumber('Batch into the oven', 'Ready in (minutes)', 25, helper: 'Customers see a live countdown');
                        if (m != null && m > 0) await _run(() => api.startBatch(p.id, m, hubId: widget.hubId), 'Batch started — countdown is live');
                      },
                icon: const Icon(Icons.local_fire_department_outlined, size: 18),
                label: const Text('Start batch'),
                style: FilledButton.styleFrom(minimumSize: const Size(0, 40)),
              )
            else
              FilledButton.icon(
                onPressed: _busy
                    ? null
                    : () async {
                        final q = await _askNumber('Batch is out', 'Pieces to add to the shelf', 12);
                        if (q != null) await _run(() => api.batchOut(p.id, q, hubId: widget.hubId), 'Added $q to the shelf');
                      },
                icon: const Icon(Icons.check, size: 18),
                label: const Text('Batch out'),
                style: FilledButton.styleFrom(minimumSize: const Size(0, 40)),
              ),
          ]),
        ],
      ]),
    );
  }
}
