String normalizeCodeWrappedAppRefs(String input) {
  if (input.isEmpty ||
      !RegExp(r'\[\s*app\s*[:：]', caseSensitive: false).hasMatch(input)) {
    return input;
  }
  return input.replaceAllMapped(
    RegExp(
      r'`+\s*(\[\s*app\s*[:：]\s*[^\]\n]+?\s*\])\s*`+',
      caseSensitive: false,
    ),
    (Match match) => match.group(1) ?? match.group(0) ?? '',
  );
}
