/// Exact conversion between what staff type into a rupee field and integer
/// paise — the only way keyboard input becomes money.
///
/// `double.tryParse(text) * 100` is wrong for money: binary floating point
/// cannot represent most decimal fractions, so `1.005 * 100` rounds to 100
/// paise and `4.35 * 100` is 434.99999999999994. This parser never touches a
/// double: it splits the text into rupees and paise digits and combines them
/// with integer arithmetic.
library;

/// The largest amount a rupee field accepts: ₹1,00,00,000.00 (one crore).
/// Far above any real counter bill, so a typo with extra zeros is refused
/// instead of being recorded.
const int maxRupeeInputPaise = 10000000 * 100;

/// What a rupee field says when [parseRupeesToPaise] refuses its text.
const String rupeeInputError = 'Enter an amount in rupees, like 250 or 250.50.';

/// Western grouping: `1,000` · `100,000` · `1,000,000`.
final RegExp _western = RegExp(r'^\d{1,3}(,\d{3})+$');

/// Indian grouping: `1,00,000` · `10,00,000` (lakh / crore).
final RegExp _indian = RegExp(r'^\d{1,2}(,\d{2})*,\d{3}$');

final RegExp _digits = RegExp(r'^\d*$');

/// Whole paise for a rupee amount typed by staff, or null when [input] is not
/// a plain non-negative rupee amount.
///
/// Accepts digits with an optional `.` and at most two fraction digits
/// (`250`, `250.5`, `250.50`, `.5`, `250.`), surrounding spaces, and
/// thousands commas in Western (`1,000.50`) or Indian (`1,00,000`) grouping.
/// Refuses empty text, signs (so no negatives), more than two decimals,
/// anything non-numeric, misplaced commas (`1,5` is never read as 15), and
/// amounts above [maxRupeeInputPaise].
int? parseRupeesToPaise(String input) {
  final text = input.trim();
  // Longest legal text is "1,00,00,000.00" (14 chars); anything far longer is
  // not an amount, and is refused before any digit is read.
  if (text.isEmpty || text.length > 20) return null;

  final dot = text.indexOf('.');
  if (dot != text.lastIndexOf('.')) return null; // two decimal points
  var whole = dot < 0 ? text : text.substring(0, dot);
  final fraction = dot < 0 ? '' : text.substring(dot + 1);

  if (fraction.length > 2 || !_digits.hasMatch(fraction)) return null;
  if (whole.contains(',')) {
    if (!_western.hasMatch(whole) && !_indian.hasMatch(whole)) return null;
    whole = whole.replaceAll(',', '');
  }
  if (!_digits.hasMatch(whole)) return null;
  if (whole.isEmpty && fraction.isEmpty) return null; // "." alone

  // Leading zeros carry no value; strip them so the length check below is
  // about magnitude, not formatting ("000250" is ₹250).
  final significant = whole.replaceFirst(RegExp(r'^0+'), '');
  // One crore has 8 digits, so 10+ can only be over the limit (and could
  // overflow an int on the web); 9 digits are refused by value below.
  if (significant.length > 9) return null;

  final rupees = significant.isEmpty ? 0 : int.parse(significant);
  final paise = int.parse(fraction.padRight(2, '0'));
  final total = rupees * 100 + paise;
  return total > maxRupeeInputPaise ? null : total;
}

/// [paise] as the text a rupee field is prefilled with: `"19.99"`, `"500.00"`.
/// Integer arithmetic only, and always re-parses to the same paise.
String paiseToRupeeInput(int paise) {
  final sign = paise < 0 ? '-' : '';
  final abs = paise.abs();
  return '$sign${abs ~/ 100}.${(abs % 100).toString().padLeft(2, '0')}';
}
