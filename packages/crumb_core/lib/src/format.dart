import 'package:intl/intl.dart';

import 'models/models.dart';

final _money = NumberFormat.decimalPattern('en_PK');

/// "Rs 1,400"
String money(int rupees, [String symbol = 'Rs']) => rupees < 0 ? '−$symbol ${_money.format(-rupees)}' : '$symbol ${_money.format(rupees)}';

/// "08:00 AM" from minute of day.
String minuteLabel(int minute) {
  final h = minute ~/ 60 % 24;
  final m = minute % 60;
  final h12 = h % 12 == 0 ? 12 : h % 12;
  return '${h12.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')} ${h < 12 ? 'AM' : 'PM'}';
}

String dateTimeLabel(DateTime? t) => t == null ? '' : DateFormat('d MMM, h:mm a').format(t.toLocal());
String timeLabel(DateTime? t) => t == null ? '' : DateFormat('h:mm a').format(t.toLocal());

/// "Today", "Tomorrow" or "Tue 20 Oct" for a yyyy-MM-dd date.
String dayLabelFor(String isoDate, {DateTime? now}) {
  final d = DateTime.tryParse(isoDate);
  if (d == null) return isoDate;
  final today = DateUtils.dateOnly(now ?? DateTime.now());
  final diff = DateUtils.dateOnly(d).difference(today).inDays;
  if (diff == 0) return 'Today';
  if (diff == 1) return 'Tomorrow';
  return DateFormat('EEE d MMM').format(d);
}

String isoDate(DateTime d) => DateFormat('yyyy-MM-dd').format(d);

/// "12:34" or "1:02:03" countdown.
String countdown(Duration d) {
  if (d.isNegative) return '0:00';
  final h = d.inHours, m = d.inMinutes % 60, s = d.inSeconds % 60;
  final mm = m.toString().padLeft(2, '0'), ss = s.toString().padLeft(2, '0');
  return h > 0 ? '$h:$mm:$ss' : '$m:$ss';
}

/// Slot label for an order, e.g. "Tomorrow · 10:00 AM - 12:00 PM".
String slotLabel(OrderSlot s) => '${dayLabelFor(s.date)} · ${s.label}';

class DateUtils {
  static DateTime dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);
}

/// Client-side preview of the server's cake price engine (the server stays authoritative).
({int unitPrice, int sizeUplift, int flavourSurcharge, int egglessSurcharge}) previewCakePrice(BusinessSettings s, int basePrice, CakeChoice c) {
  final size = s.cakeSizes.where((x) => x.id == c.sizeId).firstOrNull;
  if (size == null) return (unitPrice: basePrice, sizeUplift: 0, flavourSurcharge: 0, egglessSurcharge: 0);
  int sur(List<PricedOption> list, String id) => list.where((o) => o.id == id).firstOrNull?.surcharge ?? 0;
  final sponge = s.sponges.where((o) => o.id == c.spongeId).firstOrNull;
  final uplift = (basePrice * (size.multiplier - 1)).round();
  final flavour = ((sur(s.sponges, c.spongeId) + sur(s.fillings, c.fillingId) + sur(s.frostings, c.frostingId)) * size.multiplier).round();
  final eggless = c.eggless && !(sponge?.isEggless ?? false) ? s.egglessSurcharge : 0;
  return (unitPrice: basePrice + uplift + flavour + eggless, sizeUplift: uplift, flavourSurcharge: flavour, egglessSurcharge: eggless);
}
