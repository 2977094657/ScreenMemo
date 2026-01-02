/// Splits a merged-event summary into parts separated by Markdown horizontal rules.
///
/// The merge prompt currently uses `---` as a delimiter between the merged summary
/// (first part) and original event summaries (remaining parts).
List<String> splitMergedEventSummaryParts(String summary) {
  final String normalized = summary.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
  final parts = normalized.split(RegExp(r'^\s*---+\s*$', multiLine: true));
  return parts.map((e) => e.trim()).where((e) => e.isNotEmpty).toList(growable: false);
}

