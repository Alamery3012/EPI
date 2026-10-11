/// Arabic-aware name normalisation and similarity for duplicate warnings
/// (FRS-REG-07).
library;

final _diacritics = RegExp('[ً-ٰٟـ]');
final _spaces = RegExp(r'\s+');

String normalizeName(String s) {
  var t = s.trim().toLowerCase().replaceAll(_diacritics, '');
  t = t
      .replaceAll(RegExp('[أإآٱ]'), 'ا')
      .replaceAll('ة', 'ه')
      .replaceAll('ى', 'ي')
      .replaceAll('ؤ', 'و')
      .replaceAll('ئ', 'ي');
  return t.replaceAll(_spaces, ' ');
}

String normalizePhone(String s) {
  // Arabic-Indic digits to ASCII, then keep digits only
  var d = s.replaceAllMapped(RegExp('[٠-٩]'), (m) => (m[0]!.codeUnitAt(0) - 0x0660).toString());
  d = d.replaceAll(RegExp(r'[^0-9]'), '');
  if (d.startsWith('00967')) d = d.substring(5);
  if (d.startsWith('967')) d = d.substring(3);
  if (d.startsWith('0')) d = d.substring(1);
  return d;
}

/// Yemeni mobile: 9 digits starting with 7 (format TBC, open question Q3).
bool isValidYemenMobile(String s) {
  final d = normalizePhone(s);
  return RegExp(r'^7[01378]\d{7}$').hasMatch(d);
}

int levenshtein(String a, String b) {
  if (a == b) return 0;
  if (a.isEmpty) return b.length;
  if (b.isEmpty) return a.length;
  var prev = List<int>.generate(b.length + 1, (i) => i);
  for (var i = 1; i <= a.length; i++) {
    final cur = List<int>.filled(b.length + 1, 0);
    cur[0] = i;
    for (var j = 1; j <= b.length; j++) {
      final cost = a.codeUnitAt(i - 1) == b.codeUnitAt(j - 1) ? 0 : 1;
      cur[j] = [prev[j] + 1, cur[j - 1] + 1, prev[j - 1] + cost].reduce((x, y) => x < y ? x : y);
    }
    prev = cur;
  }
  return prev[b.length];
}

bool similarNames(String a, String b) {
  final x = normalizeName(a), y = normalizeName(b);
  if (x.isEmpty || y.isEmpty) return false;
  if (x == y) return true;
  final limit = x.length > 12 ? 2 : 1;
  return levenshtein(x, y) <= limit;
}
