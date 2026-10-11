/// Child ID = device code + 6-digit sequence + Luhn check digit (FRS-REG-06),
/// for example `ADN07-000123-4`.
library;

int luhnCheckDigit(String digits) {
  var sum = 0;
  var doubleIt = true;
  for (var i = digits.length - 1; i >= 0; i--) {
    var n = digits.codeUnitAt(i) - 48;
    if (n < 0 || n > 9) continue;
    if (doubleIt) {
      n *= 2;
      if (n > 9) n -= 9;
    }
    sum += n;
    doubleIt = !doubleIt;
  }
  return (10 - (sum % 10)) % 10;
}

String makeChildId(String deviceCode, int seq) {
  final s = seq.toString().padLeft(6, '0');
  return '${deviceCode.toUpperCase()}-$s-${luhnCheckDigit(s)}';
}

bool isValidChildId(String id) {
  final parts = id.split('-');
  if (parts.length != 3) return false;
  final check = int.tryParse(parts[2]);
  return check != null && luhnCheckDigit(parts[1]) == check;
}
