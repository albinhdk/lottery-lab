import 'package:intl/intl.dart';

final NumberFormat _intFmt = NumberFormat.decimalPattern('zh_CN');

String fmtInt(num? value) {
  if (value == null) return '—';
  return _intFmt.format(value);
}

String fmtMoney(num? value) {
  if (value == null || value == 0) return '—';
  final v = value.toDouble();
  if (v >= 100000000) {
    return '${(v / 100000000).toStringAsFixed(2)} 亿';
  }
  if (v >= 10000) {
    return '${(v / 10000).toStringAsFixed(1)} 万';
  }
  return fmtInt(value);
}

String fmtPct(num? value, {int digits = 1}) {
  if (value == null) return '—';
  return '${(value * 100).toStringAsFixed(digits)}%';
}

String fmtP(double? p) {
  if (p == null) return '—';
  if (p < 0.0001) return '<0.0001';
  return p.toStringAsFixed(4);
}

String fmtSigned(double value, {int digits = 2}) {
  final s = value.toStringAsFixed(digits);
  return value > 0 ? '+$s' : s;
}

String fmtDateShort(String? iso) {
  if (iso == null || iso.isEmpty) return '—';
  return iso;
}

String fmtIsoDate(DateTime d) {
  final m = d.month.toString().padLeft(2, '0');
  final day = d.day.toString().padLeft(2, '0');
  return '${d.year}-$m-$day';
}
