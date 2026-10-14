import 'package:intl/intl.dart';

/// Compact count: 950, 1.2K, 12K, 123K, 1.2M (two significant digits, never
/// dropping integer digits).
String formatCompact(num n, {String? locale}) {
  if (n.abs() < 1000) return NumberFormat.decimalPattern(locale).format(n);
  return (NumberFormat.compact(locale: locale)..significantDigits = 2).format(n);
}

/// Full count with grouping: 1,234,567.
String formatCount(num n, {String? locale}) => NumberFormat.decimalPattern(locale).format(n);

const _units = ['B', 'KB', 'MB', 'GB', 'TB', 'PB'];

/// Bytes in decimal (SI) units, matching the labels: 3.4 GB = 3.4 × 10⁹ bytes.
String formatBytes(num bytes, {String? locale}) {
  var v = bytes.toDouble();
  var i = 0;
  while (v.abs() >= 1000 && i < _units.length - 1) {
    v /= 1000;
    i++;
  }
  final pattern = i == 0 || v.abs() >= 100 ? '#,##0' : '#,##0.#';
  return '${NumberFormat(pattern, locale).format(v)} ${_units[i]}';
}

/// Ratio 0–1 as a percent: 87%, or 4.5% below 10%.
String formatPercent(double ratio, {String? locale}) {
  final digits = ratio > 0 && ratio < 0.1 ? 1 : 0;
  return NumberFormat.decimalPercentPattern(locale: locale, decimalDigits: digits).format(ratio);
}
