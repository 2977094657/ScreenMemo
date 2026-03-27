String normalizeCodeWrappedAppRefs(String input) {
  if (input.isEmpty || !input.contains('[app:')) return input;
  return input.replaceAllMapped(
    RegExp(
      r'`+\s*(\[\s*app\s*[:：]\s*[^\]\n]+?\s*\])\s*`+',
      caseSensitive: false,
    ),
    (Match match) => match.group(1) ?? match.group(0) ?? '',
  );
}
