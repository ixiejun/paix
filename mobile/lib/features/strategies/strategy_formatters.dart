String formatPercent(double value, {int fractionDigits = 1}) {
  final sign = value > 0 ? '+' : '';
  return '$sign${value.toStringAsFixed(fractionDigits)}%';
}

String formatCompactInt(int value) {
  if (value.abs() >= 1000000000) {
    return '${(value / 1000000000).toStringAsFixed(1)}B';
  }
  if (value.abs() >= 1000000) {
    return '${(value / 1000000).toStringAsFixed(1)}M';
  }
  if (value.abs() >= 1000) {
    return '${(value / 1000).toStringAsFixed(1)}K';
  }
  return value.toString();
}

String formatUsd(double value) {
  final abs = value.abs();
  if (abs >= 1000000000) {
    return 'US\$${(value / 1000000000).toStringAsFixed(1)}B';
  }
  if (abs >= 1000000) {
    return 'US\$${(value / 1000000).toStringAsFixed(1)}M';
  }
  if (abs >= 1000) {
    return 'US\$${(value / 1000).toStringAsFixed(1)}K';
  }
  return 'US\$${value.toStringAsFixed(0)}';
}
