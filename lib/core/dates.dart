/// Date-only helpers. All clinical dates are calendar dates with no time,
/// stored as ISO strings (yyyy-MM-dd) and handled in UTC to avoid DST shifts.
library;

DateTime dateOnly(DateTime d) => DateTime.utc(d.year, d.month, d.day);

DateTime today() => dateOnly(DateTime.now());

DateTime addDays(DateTime d, int days) => DateTime.utc(d.year, d.month, d.day + days);

int daysBetween(DateTime from, DateTime to) => dateOnly(to).difference(dateOnly(from)).inDays;

DateTime maxDate(DateTime a, DateTime b) => a.isAfter(b) ? a : b;

String iso(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

DateTime parseIso(String s) {
  final p = s.split('-');
  return DateTime.utc(int.parse(p[0]), int.parse(p[1]), int.parse(p[2]));
}

DateTime? tryParseIso(String? s) {
  if (s == null || s.isEmpty) return null;
  try {
    return parseIso(s);
  } catch (_) {
    return null;
  }
}

/// dd/mm/yyyy, Gregorian (FRS-DOC-03, open question Q4).
String fmt(DateTime? d) {
  if (d == null) return '-';
  return '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
}

String ageText(DateTime dob, String lang, {DateTime? at}) {
  final days = daysBetween(dob, at ?? today());
  if (days < 0) return '-';
  if (days < 60) {
    final w = days ~/ 7;
    if (lang == 'ar') return days < 14 ? '$days يومًا' : '$w أسابيع';
    return days < 14 ? '$days days' : '$w weeks';
  }
  final months = (days / 30.44).floor();
  if (months < 24) return lang == 'ar' ? '$months شهرًا' : '$months months';
  final y = months ~/ 12;
  final m = months % 12;
  return lang == 'ar' ? '$y سنة و$m شهر' : '$y y $m m';
}
