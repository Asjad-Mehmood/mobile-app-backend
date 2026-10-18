import 'dart:async';
import 'dart:math';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../api/api_client.dart';
import '../format.dart';
import '../models/enums.dart';
import '../models/models.dart';
import '../theme/theme.dart';

// ── Buttons & cards ───────────────────────────────────────────────────────────

class BakeryButton extends StatelessWidget {
  const BakeryButton({super.key, required this.label, this.onPressed, this.icon, this.loading = false, this.outlined = false, this.expand = true});

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool loading;
  final bool outlined;
  final bool expand;

  @override
  Widget build(BuildContext context) {
    final child = loading
        ? SizedBox.square(dimension: 22, child: CircularProgressIndicator(strokeWidth: 2.5, color: outlined ? context.colors.primary : context.colors.onPrimary))
        : Row(mainAxisSize: MainAxisSize.min, children: [
            if (icon != null) ...[Icon(icon, size: 20), const SizedBox(width: 8)],
            Flexible(child: Text(label, overflow: TextOverflow.ellipsis)),
          ]);
    final action = loading ? null : onPressed;
    final button = outlined ? OutlinedButton(onPressed: action, child: child) : FilledButton(onPressed: action, child: child);
    return expand ? SizedBox(width: double.infinity, child: button) : button;
  }
}

class BakeryCard extends StatelessWidget {
  const BakeryCard({super.key, required this.child, this.onTap, this.padding = const EdgeInsets.all(16), this.color});
  final Widget child;
  final VoidCallback? onTap;
  final EdgeInsetsGeometry padding;
  final Color? color;

  @override
  Widget build(BuildContext context) => Card(
        color: color,
        clipBehavior: Clip.antiAlias,
        child: InkWell(onTap: onTap, child: Padding(padding: padding, child: child)),
      );
}

class SectionHeader extends StatelessWidget {
  const SectionHeader(this.title, {super.key, this.trailing, this.padding = const EdgeInsets.fromLTRB(16, 20, 16, 8)});
  final String title;
  final Widget? trailing;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) => Padding(
        padding: padding,
        child: Row(children: [Expanded(child: Text(title, style: context.text.titleLarge)), ?trailing]),
      );
}

// ── Badges ────────────────────────────────────────────────────────────────────

class Pill extends StatelessWidget {
  const Pill(this.label, {super.key, this.icon, this.background, this.foreground});
  final String label;
  final IconData? icon;
  final Color? background;
  final Color? foreground;

  @override
  Widget build(BuildContext context) {
    final fg = foreground ?? context.colors.onSecondaryContainer;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: background ?? context.colors.secondaryContainer, borderRadius: BorderRadius.circular(20)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        if (icon != null) ...[Icon(icon, size: 14, color: fg), const SizedBox(width: 4)],
        Text(label, style: context.text.labelSmall?.copyWith(color: fg)),
      ]),
    );
  }
}

class AllergenBadge extends StatelessWidget {
  const AllergenBadge(this.allergen, {super.key});
  final Allergen allergen;

  @override
  Widget build(BuildContext context) => Pill(
        'Contains ${allergen.label.toLowerCase()}',
        icon: Icons.warning_amber_rounded,
        background: context.colors.errorContainer,
        foreground: context.colors.onErrorContainer,
      );
}

class DietaryTagChip extends StatelessWidget {
  const DietaryTagChip(this.tag, {super.key});
  final DietaryTag tag;

  @override
  Widget build(BuildContext context) =>
      Pill(tag.label, icon: Icons.eco_outlined, background: context.colors.tertiaryContainer, foreground: context.colors.onTertiaryContainer);
}

class StatusChip extends StatelessWidget {
  const StatusChip(this.status, {super.key, this.type = FulfillmentType.pickup});
  final OrderStatus status;
  final FulfillmentType type;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final (bg, fg) = switch (status) {
      OrderStatus.cancelled => (c.errorContainer, c.onErrorContainer),
      OrderStatus.completed => (c.surfaceContainerHighest, c.onSurfaceVariant),
      OrderStatus.ready => (c.tertiaryContainer, c.onTertiaryContainer),
      OrderStatus.confirmed => (c.secondaryContainer, c.onSecondaryContainer),
      _ => (c.primaryContainer, c.onPrimaryContainer),
    };
    return Pill(status.titleFor(type), background: bg, foreground: fg);
  }
}

// ── Inputs ────────────────────────────────────────────────────────────────────

class QuantitySelector extends StatelessWidget {
  const QuantitySelector({super.key, required this.value, required this.onChanged, this.min = 1, this.max = 50, this.compact = false});
  final int value;
  final ValueChanged<int> onChanged;
  final int min;
  final int max;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final size = compact ? 32.0 : 44.0;
    Widget btn(IconData icon, int next, String label) => SizedBox.square(
          dimension: size,
          child: IconButton.filledTonal(
            tooltip: label,
            padding: EdgeInsets.zero,
            iconSize: compact ? 16 : 20,
            onPressed: next < min || next > max
                ? null
                : () {
                    HapticFeedback.selectionClick();
                    onChanged(next);
                  },
            icon: Icon(icon),
          ),
        );
    return Row(mainAxisSize: MainAxisSize.min, children: [
      btn(Icons.remove, value - 1, 'Decrease quantity'),
      SizedBox(
        width: compact ? 32 : 44,
        child: Text('$value', textAlign: TextAlign.center, style: compact ? context.text.titleSmall : context.text.titleMedium),
      ),
      btn(Icons.add, value + 1, 'Increase quantity'),
    ]);
  }
}

// ── Images ────────────────────────────────────────────────────────────────────

class ProductImage extends StatelessWidget {
  const ProductImage({super.key, this.url, this.radius = 16, this.aspectRatio, this.fit = BoxFit.cover});
  final String? url;
  final double radius;
  final double? aspectRatio;
  final BoxFit fit;

  @override
  Widget build(BuildContext context) {
    final placeholder = Container(
      color: context.colors.surfaceContainerHigh,
      alignment: Alignment.center,
      child: Icon(Icons.bakery_dining_outlined, size: 36, color: context.bakery.crumb),
    );
    Widget img = url == null || url!.isEmpty
        ? placeholder
        : CachedNetworkImage(
            imageUrl: url!,
            fit: fit,
            fadeInDuration: const Duration(milliseconds: 200),
            placeholder: (_, _) => placeholder,
            errorWidget: (_, _, _) => placeholder,
          );
    img = ClipRRect(borderRadius: BorderRadius.circular(radius), child: SizedBox.expand(child: img));
    return aspectRatio == null ? img : AspectRatio(aspectRatio: aspectRatio!, child: img);
  }
}

// ── States ────────────────────────────────────────────────────────────────────

class EmptyState extends StatelessWidget {
  const EmptyState({super.key, required this.icon, required this.title, this.message, this.action, this.onAction});
  final IconData icon;
  final String title;
  final String? message;
  final String? action;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) => Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(32),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(
              padding: const EdgeInsets.all(22),
              decoration: BoxDecoration(color: context.colors.secondaryContainer, shape: BoxShape.circle),
              child: Icon(icon, size: 40, color: context.colors.onSecondaryContainer),
            ),
            const SizedBox(height: 20),
            Text(title, style: context.text.headlineSmall, textAlign: TextAlign.center),
            if (message != null) ...[
              const SizedBox(height: 8),
              Text(message!, style: context.text.bodyMedium?.copyWith(color: context.colors.onSurfaceVariant), textAlign: TextAlign.center),
            ],
            if (action != null && onAction != null) ...[
              const SizedBox(height: 24),
              BakeryButton(label: action!, onPressed: onAction, expand: false),
            ],
          ]),
        ),
      );
}

/// Error view with a retry button; understands offline errors.
class ErrorRetry extends StatelessWidget {
  const ErrorRetry({super.key, required this.error, required this.onRetry});
  final Object error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final offline = error is ApiException && (error as ApiException).isNetwork;
    return EmptyState(
      icon: offline ? Icons.wifi_off_rounded : Icons.error_outline_rounded,
      title: offline ? "Can't reach the bakery" : 'Something went wrong',
      message: error is ApiException ? '$error' : 'Please try again.',
      action: 'Try again',
      onAction: onRetry,
    );
  }
}

class LoadingView extends StatelessWidget {
  const LoadingView({super.key});
  @override
  Widget build(BuildContext context) => const Center(child: CircularProgressIndicator());
}

String errorText(Object e) => e is ApiException ? e.message : 'Something went wrong. Please try again.';

// ── Live bake countdown ───────────────────────────────────────────────────────

/// "Next batch of Butter Croissants out of the oven in 12:34".
class LiveBakeCountdown extends StatefulWidget {
  const LiveBakeCountdown({super.key, required this.readyAt, this.label = 'Fresh batch in', this.compact = false});
  final DateTime readyAt;
  final String label;
  final bool compact;

  @override
  State<LiveBakeCountdown> createState() => _LiveBakeCountdownState();
}

class _LiveBakeCountdownState extends State<LiveBakeCountdown> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => mounted ? setState(() {}) : null);
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final left = widget.readyAt.difference(DateTime.now());
    final done = left.isNegative;
    final text = done ? 'Coming out of the oven…' : '${widget.label} ${countdown(left)}';
    return Pill(
      text,
      icon: Icons.local_fire_department_rounded,
      background: context.colors.primaryContainer,
      foreground: context.colors.onPrimaryContainer,
    );
  }
}

// ── Pricing summary ───────────────────────────────────────────────────────────

class PricingSummary extends StatelessWidget {
  const PricingSummary({super.key, required this.pricing, this.symbol = 'Rs', this.promoCode});
  final Pricing pricing;
  final String symbol;
  final String? promoCode;

  @override
  Widget build(BuildContext context) {
    Widget row(String label, int value, {bool bold = false, bool discount = false, Color? color}) {
      final style = bold ? context.text.titleMedium : context.text.bodyMedium;
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(children: [
          Expanded(child: Text(label, style: style?.copyWith(color: color))),
          Text(discount ? money(-value, symbol) : money(value, symbol), style: style?.copyWith(color: color)),
        ]),
      );
    }

    final green = context.bakery.success;
    return Column(children: [
      row('Subtotal', pricing.subtotal),
      if (pricing.customCakeSurcharge > 0) row('Cake size & flavours', pricing.customCakeSurcharge),
      row('Packaging', pricing.packagingFee),
      if (pricing.deliveryFee > 0) row('Delivery', pricing.deliveryFee),
      if (pricing.promoDiscount > 0) row(promoCode == null ? 'Promo' : 'Promo ($promoCode)', pricing.promoDiscount, discount: true, color: green),
      if (pricing.loyaltyDiscount > 0) row('Loyalty reward', pricing.loyaltyDiscount, discount: true, color: green),
      const Divider(height: 20),
      row('Total', pricing.total, bold: true),
    ]);
  }
}

// ── QR ────────────────────────────────────────────────────────────────────────

class PickupQr extends StatelessWidget {
  const PickupQr({super.key, required this.data, this.size = 180});
  final String data;
  final double size;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
        child: QrImageView(
          data: data,
          size: size,
          backgroundColor: Colors.white,
          eyeStyle: const QrEyeStyle(eyeShape: QrEyeShape.square, color: Color(0xFF2A1F1B)),
          dataModuleStyle: const QrDataModuleStyle(dataModuleShape: QrDataModuleShape.square, color: Color(0xFF2A1F1B)),
          semanticsLabel: 'Pickup QR code',
        ),
      );
}

// ── Loyalty stamp card ────────────────────────────────────────────────────────

/// "Baker's Dozen" card; the last [newlyEarned] stamps are pressed in with a wax-seal animation.
class StampCard extends StatelessWidget {
  const StampCard({super.key, required this.stampsOnCard, this.newlyEarned = 0, this.slots = 12, this.columns = 4});
  final int stampsOnCard;
  final int newlyEarned;
  final int slots;
  final int columns;

  @override
  Widget build(BuildContext context) {
    final firstNew = max(0, stampsOnCard - newlyEarned);
    return Semantics(
      label: '$stampsOnCard of $slots stamps collected',
      excludeSemantics: true,
      child: GridView.count(
        crossAxisCount: columns,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        mainAxisSpacing: 10,
        crossAxisSpacing: 10,
        children: [
          for (var i = 0; i < slots; i++)
            i < stampsOnCard
                ? WaxSeal(animate: i >= firstNew, delay: Duration(milliseconds: i >= firstNew ? 350 + (i - firstNew) * 320 : 0))
                : _EmptySlot(number: i + 1),
        ],
      ),
    );
  }
}

class WaxSeal extends StatefulWidget {
  const WaxSeal({super.key, this.animate = false, this.delay = Duration.zero});
  final bool animate;
  final Duration delay;

  @override
  State<WaxSeal> createState() => _WaxSealState();
}

class _WaxSealState extends State<WaxSeal> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 650), value: widget.animate ? 0 : 1);

  @override
  void initState() {
    super.initState();
    if (widget.animate) {
      Future.delayed(widget.delay, () {
        if (mounted) {
          HapticFeedback.lightImpact();
          _c.forward();
        }
      });
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final seal = context.bakery.waxSeal;
    return AnimatedBuilder(
      animation: _c,
      builder: (context, child) {
        final t = Curves.elasticOut.transform(_c.value);
        final scale = 2.4 - 1.4 * t;
        return Opacity(
          opacity: (_c.value * 6).clamp(0, 1),
          child: Transform.rotate(angle: -0.6 * (1 - t), child: Transform.scale(scale: scale, child: child)),
        );
      },
      child: CustomPaint(
        painter: _SealPainter(seal),
        child: Center(
          child: Text('C&C',
              style: TextStyle(fontFamily: 'PlayfairDisplay', package: 'crumb_core', fontWeight: FontWeight.w700, color: Colors.white, fontSize: 13)),
        ),
      ),
    );
  }
}

class _SealPainter extends CustomPainter {
  _SealPainter(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final r = size.shortestSide / 2;
    final c = Offset(size.width / 2, size.height / 2);
    final path = Path();
    const points = 72;
    for (var i = 0; i <= points; i++) {
      final t = 2 * pi * i / points;
      final radius = r * (0.93 + 0.05 * sin(14 * t));
      final p = Offset(c.dx + radius * cos(t), c.dy + radius * sin(t));
      i == 0 ? path.moveTo(p.dx, p.dy) : path.lineTo(p.dx, p.dy);
    }
    path.close();
    canvas.drawPath(path, Paint()..color = color);
    canvas.drawCircle(
        c,
        r * 0.68,
        Paint()
          ..color = Colors.white.withValues(alpha: 0.55)
          ..style = PaintingStyle.stroke
          ..strokeWidth = r * 0.06);
    canvas.drawCircle(Offset(c.dx - r * 0.28, c.dy - r * 0.3), r * 0.32, Paint()..color = Colors.white.withValues(alpha: 0.12));
  }

  @override
  bool shouldRepaint(_SealPainter old) => old.color != color;
}

class _EmptySlot extends StatelessWidget {
  const _EmptySlot({required this.number});
  final int number;

  @override
  Widget build(BuildContext context) => CustomPaint(
        painter: _DashedCircle(context.colors.outline.withValues(alpha: 0.6)),
        child: Center(child: Text('$number', style: context.text.labelLarge?.copyWith(color: context.colors.onSurfaceVariant))),
      );
}

class _DashedCircle extends CustomPainter {
  _DashedCircle(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final r = size.shortestSide / 2 * 0.86;
    final c = Offset(size.width / 2, size.height / 2);
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    const dashes = 24;
    for (var i = 0; i < dashes; i++) {
      final start = 2 * pi * i / dashes;
      canvas.drawArc(Rect.fromCircle(center: c, radius: r), start, pi / dashes, false, paint);
    }
  }

  @override
  bool shouldRepaint(_DashedCircle old) => old.color != color;
}

// ── Live connection dot ───────────────────────────────────────────────────────

class LiveDot extends StatelessWidget {
  const LiveDot({super.key, required this.live, this.showLabel = true});
  final bool live;
  final bool showLabel;

  @override
  Widget build(BuildContext context) {
    final color = live ? context.bakery.success : context.colors.outline;
    return Tooltip(
      message: live ? 'Live — updates sync instantly' : 'Reconnecting…',
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Container(width: 8, height: 8, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        if (showLabel) ...[const SizedBox(width: 6), Text(live ? 'Live' : 'Offline', style: context.text.labelSmall?.copyWith(color: color))],
      ]),
    );
  }
}

// ── Server URL dialog (both apps) ─────────────────────────────────────────────

Future<String?> showServerUrlDialog(BuildContext context, String current) {
  final ctl = TextEditingController(text: current);
  return showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Bakery server'),
      content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('The address of your Crumb & Craft API, e.g. https://crumb-api.onrender.com'),
        const SizedBox(height: 12),
        TextField(controller: ctl, keyboardType: TextInputType.url, autocorrect: false, decoration: const InputDecoration(labelText: 'Server URL')),
      ]),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, ''), child: const Text('Reset')),
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.pop(ctx, ctl.text.trim()), child: const Text('Save')),
      ],
    ),
  );
}
