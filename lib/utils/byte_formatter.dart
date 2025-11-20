String formatBytes(int bytes, {int maxFractionDigits = 2}) {
  if (bytes <= 0) return '0 B';
  const units = ['B', 'KB', 'MB', 'GB', 'TB', 'PB'];
  double value = bytes.toDouble();
  int unitIndex = 0;
  while (value >= 1024 && unitIndex < units.length - 1) {
    value /= 1024;
    unitIndex++;
  }

  int fractionDigits;
  if (value >= 100) {
    fractionDigits = 0;
  } else if (value >= 10) {
    fractionDigits = 1;
  } else {
    fractionDigits = maxFractionDigits;
  }

  final formatted = value.toStringAsFixed(fractionDigits);
  return '$formatted ${units[unitIndex]}';
}
