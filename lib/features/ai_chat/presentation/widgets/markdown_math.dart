import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_math_fork/flutter_math.dart' as fm;
import 'package:markdown/markdown.dart' as md;
import 'package:shimmer/shimmer.dart';
import 'dart:async';
import 'dart:io';
import 'package:screen_memo/data/database/screenshot_database.dart';
import 'package:screen_memo/features/ai_chat/presentation/widgets/chat_markdown_chart.dart';
import 'package:screen_memo/l10n/app_localizations.dart';
import 'package:screen_memo/features/gallery/presentation/widgets/screenshot_image_widget.dart';
import 'package:screen_memo/features/nsfw/application/nsfw_preference_service.dart';
import 'package:screen_memo/app/navigation/navigation_service.dart';
import 'package:screen_memo/core/performance/ui_perf_logger.dart';
import 'package:screen_memo/models/screenshot_record.dart';
import 'package:screen_memo/models/app_info.dart';
import 'package:screen_memo/core/theme/app_theme.dart';
import 'package:screen_memo/core/logging/flutter_logger.dart';
import 'package:url_launcher/url_launcher.dart';

/// 说明：
/// - 仅在 AI 对话页面使用，用于渲染 Markdown 中的 LaTeX 数学公式；<think> 思考块在此阶段被移除。
/// - 复刻 rikkahub 的预处理：
///   * 将行内公式 \( ... \) 转为 <math-inline>...</math-inline>
///   * 将块级公式 \[ ... \] 转为 <math-block>...</math-block>
///   * 移除 <think>...</think>（不在可见正文中显示；思考在 UI 的 Reasoning 卡片展示）
///   * 跳过代码块 (```...```) 与行内代码 (`...`)
/// - 使用 flutter_markdown 的 builders 将 <math-inline>/<math-block> 渲染为 TeX。
/// - 通过自定义 BlockSyntax 将 ```chart-v1``` fenced block 渲染为聊天图表卡片。
///
/// 集成方式：
/// 1) 在构建聊天 Markdown 时：
///    final config = MarkdownMathConfig(
///      inlineTextStyle: Theme.of(context).textTheme.bodyMedium,
///      blockTextStyle: Theme.of(context).textTheme.bodyMedium,
///    );
///    final data = preprocessForChatMarkdown(originalText);
///    MarkdownBody(
///      data: data,
///      builders: config.builders,
///      blockSyntaxes: config.blockSyntaxes,
///      styleSheet: ...,
///    )
///
/// 2) 需要在 pubspec.yaml 添加：
///    dependencies:
///      flutter_math_fork: ^0.7.2
///
// Keep the evidence loading shimmer consistent with the "thinking" shimmer.
const Color _kThinkingShimmerHighlightColor = Color(0xFFFFFBEB);
// TEMP (debug-only): show evidence resolve state under each image/placeholder.
// Remove once the restore/render issue is confirmed fixed.
const bool _kChatEvidenceDebugUi = kDebugMode;
const String _kGeneratedImageBlockTag = 'generated-image-block';
const String _kGeneratedImageLoadingBlockTag = 'generated-image-loading-block';
const String _kGeneratedImageFilenameAttribute = 'filename';
const String _kGeneratedImageLoadingIdAttribute = 'id';
final RegExp _generatedImageMarkerPattern = RegExp(
  r'\[\s*generated-image(?:-loading)?\s*:\s*([^\]\s]+)\s*\]',
  caseSensitive: false,
);

void _logMarkdownPerf(String name, {String? detail, Stopwatch? stopwatch}) {
  final String d0 = (detail ?? '').trim();
  final String d = [
    if (stopwatch != null) 'ms=${stopwatch.elapsedMilliseconds}',
    if (d0.isNotEmpty) d0,
  ].join(' ');
  unawaited(
    FlutterLogger.nativeInfo(
      'AI_CHAT_PERF',
      d.isEmpty ? name : '$name $d',
    ).catchError((_) {}),
  );
}

bool containsGeneratedImageMarker(String content) {
  return _generatedImageMarkerPattern.hasMatch(content);
}

String generatedImageMarkerDebugSummary(String content) {
  return _generatedImageMarkerPattern
      .allMatches(content)
      .map((m) => (m.group(0) ?? '').trim())
      .where((m) => m.isNotEmpty)
      .join('|');
}

String _shortenDebugText(String s, {int max = 72}) {
  final String t = s.trim();
  if (t.length <= max) return t;
  return '…' + t.substring(t.length - max);
}

bool _looksLikeAbsoluteEvidencePath(String value) {
  final String v = value.trim();
  if (v.isEmpty) return false;
  return v.startsWith('/') ||
      v.startsWith('\\\\') ||
      RegExp(r'^[A-Za-z]:[\\/]').hasMatch(v);
}

/// 将原文预处理为带 <math-inline>/<math-block> 与思考引用块的 Markdown 文本。
String preprocessForChatMarkdown(String content) {
  // 先分段，跳过代码块
  final codeFence = RegExp(r'```[\s\S]*?```', multiLine: true);
  final segments = <_Seg>[];
  int cursor = 0;
  for (final m in codeFence.allMatches(content)) {
    if (m.start > cursor) {
      segments.add(_Seg(false, content.substring(cursor, m.start)));
    }
    segments.add(_Seg(true, content.substring(m.start, m.end)));
    cursor = m.end;
  }
  if (cursor < content.length) {
    segments.add(_Seg(false, content.substring(cursor)));
  }

  final buf = StringBuffer();
  for (final seg in segments) {
    if (seg.isCode) {
      buf.write(seg.text);
    } else {
      // 对非代码块内容：先移除 <think>，再做 LaTeX 转标签（跳过行内代码片段）
      final s1 = _removeThinkBlocks(seg.text);
      final s2 = _replaceLatexToTagsSkippingInlineCode(s1);
      final s3 = _normalizeEvidenceTagsSkippingInlineCode(s2);
      final s4 = _removeTrailingPunctuationAfterEvidence(s3);
      final s5 = _ensureEvidenceBlocksOnOwnLine(s4);
      final s6 = _removeParenthesesAroundMarkdownLinksSkippingInlineCode(s5);
      final s7 = _ensureGeneratedImagesOnOwnLine(s6);
      buf.write(s7);
    }
  }
  return buf.toString();
}

/// 从可见正文中移除 <think>...</think>（支持缺失闭合标签）。
String _removeThinkBlocks(String text) {
  final thinkRegex = RegExp(
    r'<think>([\s\S]*?)(?:</think>|$)',
    multiLine: true,
  );
  return text.replaceAll(thinkRegex, '');
}

/// 规范化模型输出的 evidence 引用格式，尽量修复以下常见错误：
/// - 大小写不一致：[Evidence: ...] -> [evidence: ...]
/// - 多证据塞进同一对括号：[evidence: a, b] -> [evidence: a] [evidence: b]
/// - 各类分隔符（,，、;；）混用
///
/// 注意：仅用于渲染阶段的“容错修复”，不改变原始消息存储。
/// 仅处理普通文本；行内代码 (`...`) 内容保持原样。
String _normalizeEvidenceTagsSkippingInlineCode(String input) {
  final inlineCode = RegExp(r'`[^`\n]*`'); // 单行内联代码
  final parts = <String>[];
  int p = 0;
  for (final m in inlineCode.allMatches(input)) {
    if (m.start > p) {
      parts.add(_normalizeEvidenceTags(input.substring(p, m.start)));
    }
    parts.add(input.substring(m.start, m.end)); // 保持内联代码原样
    p = m.end;
  }
  if (p < input.length) {
    parts.add(_normalizeEvidenceTags(input.substring(p)));
  }
  return parts.join();
}

String _normalizeEvidenceTags(String input) {
  final evAny = RegExp(
    r'\[\s*evidence\s*[:：]\s*([^\]]+)\]',
    caseSensitive: false,
  );
  return input.replaceAllMapped(evAny, (m) {
    final String rawInside = (m.group(1) ?? '').trim();
    if (rawInside.isEmpty) return m.group(0) ?? '';
    if (_looksLikeAbsoluteEvidencePath(rawInside)) {
      return '[evidence: $rawInside]';
    }

    // 统一分隔符为逗号，便于拆分
    String normalized = rawInside.replaceAll(RegExp(r'[，、;；]+'), ',');

    // 允许用空格/逗号分隔多个证据
    final List<String> tokens = normalized
        .split(RegExp(r'[\s,]+'))
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .map((s) => s.replaceAll(RegExp(r'^[,，、;；。\.]+'), ''))
        .map((s) => s.replaceAll(RegExp(r'[,，、;；。\.]+$'), ''))
        .where((s) => s.isNotEmpty)
        .toList();

    if (tokens.isEmpty) return m.group(0) ?? '';
    return tokens.map((t) => '[evidence: $t]').join(' ');
  });
}

/// 去除紧跟在 [evidence: FILENAME.EXT] 后面的句号（英文 . 或中文 。）
String _removeTrailingPunctuationAfterEvidence(String input) {
  // 仅处理非代码段文本，这里输入已是单段的普通文本
  // 情况1：无空格直接跟句号，例如: [evidence: a.png]. 或 。
  input = input.replaceAllMapped(
    RegExp(r'(\[evidence:\s*[^\]]+?\s*\])[。\.](?!\S)'),
    (m) => m.group(1) ?? '',
  );
  // 情况2：后面有若干空格再句号，例如: [evidence: a.png]   .
  input = input.replaceAllMapped(
    RegExp(r'(\[evidence:\s*[^\]]+?\s*\])\s*[。\.]'),
    (m) => m.group(1) ?? '',
  );
  return input;
}

String _removeParenthesesAroundMarkdownLinksSkippingInlineCode(String input) {
  final inlineCode = RegExp(r'`[^`\n]*`');
  final parts = <String>[];
  int p = 0;
  for (final m in inlineCode.allMatches(input)) {
    if (m.start > p) {
      parts.add(
        _removeParenthesesAroundMarkdownLinks(input.substring(p, m.start)),
      );
    }
    parts.add(input.substring(m.start, m.end));
    p = m.end;
  }
  if (p < input.length) {
    parts.add(_removeParenthesesAroundMarkdownLinks(input.substring(p)));
  }
  return parts.join();
}

String _removeParenthesesAroundMarkdownLinks(String input) {
  return input.replaceAllMapped(
    RegExp(r'\((\[[^\]\n]+\]\([^)]+\))\)'),
    (m) => m.group(1) ?? m.group(0) ?? '',
  );
}

/// 将含有 [evidence: ...] 的行进行重排：
/// - 若一行同时包含文字与 evidence，则将 evidence 序列（仅由空白分隔的一组 evidence）单独放到一行；
/// - 若一行仅包含若干 evidence 与空白，则保持在同一行（可并排显示多张图片）。
/// - 仅处理普通文本行；代码块在上层已被剥离，不在此函数内处理。
String _ensureEvidenceBlocksOnOwnLine(String input) {
  final lines = input.replaceAll('\r\n', '\n').split('\n');
  final ev = RegExp(r'\[evidence:\s*[^\]]+?\s*\]');
  final out = StringBuffer();
  for (final line in lines) {
    if (!ev.hasMatch(line)) {
      out.writeln(line);
      continue;
    }
    int cursor = 0;
    final matches = ev.allMatches(line).toList();
    if (matches.isEmpty) {
      out.writeln(line);
      continue;
    }
    List<String> group = <String>[];
    bool wroteSomething = false;
    for (int i = 0; i < matches.length; i++) {
      final m = matches[i];
      final between = line.substring(cursor, m.start);
      final hasText = between.trim().isNotEmpty;
      if (group.isEmpty) {
        if (hasText) {
          out.writeln(between.trim());
          wroteSomething = true;
        }
        group.add(m.group(0)!);
      } else {
        // 已有 evidence 组，判断中间是否仅为空白
        if (hasText) {
          // 先输出上一组 evidence
          out.writeln(group.join(' '));
          wroteSomething = true;
          group = <String>[];
          // 再输出文字
          out.writeln(between.trim());
        }
        group.add(m.group(0)!);
      }
      cursor = m.end;
    }
    if (group.isNotEmpty) {
      // evidence 组独占一行
      out.writeln(group.join(' '));
      wroteSomething = true;
    }
    final tail = line.substring(cursor);
    if (tail.trim().isNotEmpty) {
      // 尾部若还有文字，则单独成行
      out.writeln(tail.trim());
      wroteSomething = true;
    }
    if (!wroteSomething) {
      out.writeln('');
    }
  }
  // 在纯 evidence 行的前后加一个空行，进一步确保与文字段落分隔
  final evLine = RegExp(r'^(?:\s*\[evidence:[^\]]+\]\s*)+$');
  final normalized = out.toString().replaceAll('\r\n', '\n');
  final sb = StringBuffer();
  final ls = normalized.split('\n');
  for (int i = 0; i < ls.length; i++) {
    final cur = ls[i];
    final isEv = evLine.hasMatch(cur.trim());
    final prev = i > 0 ? ls[i - 1] : null;
    final next = i + 1 < ls.length ? ls[i + 1] : null;
    final prevIsEv = prev != null && evLine.hasMatch(prev.trim());
    final nextIsEv = next != null && evLine.hasMatch(next.trim());

    // 在 evidence-only 行前后添加空行（但相邻 evidence 行之间不加）
    if (isEv && (prev != null) && prev.trim().isNotEmpty && !prevIsEv) {
      sb.writeln('');
    }
    sb.writeln(cur);
    if (isEv && (next != null) && next.trim().isNotEmpty && !nextIsEv) {
      sb.writeln('');
    }
  }
  var s = sb.toString();
  if (s.endsWith('\n')) s = s.substring(0, s.length - 1);
  return s;
}

String _ensureGeneratedImagesOnOwnLine(String input) {
  final List<String> lines = input.replaceAll('\r\n', '\n').split('\n');
  final StringBuffer out = StringBuffer();
  for (final String line in lines) {
    if (!_generatedImageMarkerPattern.hasMatch(line)) {
      out.writeln(line);
      continue;
    }
    int cursor = 0;
    final List<RegExpMatch> matches = _generatedImageMarkerPattern
        .allMatches(line)
        .toList();
    for (final RegExpMatch match in matches) {
      final String before = line.substring(cursor, match.start).trim();
      if (before.isNotEmpty) out.writeln(before);
      final String filename = (match.group(1) ?? '').trim();
      if (filename.isNotEmpty) {
        out.writeln();
        final String raw = match.group(0) ?? '';
        final bool loading = raw.toLowerCase().contains(
          'generated-image-loading',
        );
        out.writeln(
          loading
              ? '[generated-image-loading: $filename]'
              : '[generated-image: $filename]',
        );
        out.writeln();
      }
      cursor = match.end;
    }
    final String tail = line.substring(cursor).trim();
    if (tail.isNotEmpty) out.writeln(tail);
  }
  String result = out.toString();
  if (result.endsWith('\n')) result = result.substring(0, result.length - 1);
  unawaited(
    FlutterLogger.nativeInfo(
      'AI_IMAGE',
      'md.preprocess.generated_markers in=${_generatedImageMarkerPattern.allMatches(input).length} out=${_generatedImageMarkerPattern.allMatches(result).length} markers=${generatedImageMarkerDebugSummary(result)}',
    ),
  );
  return result;
}

/// 自定义块语法：将独占一行的 [generated-image: FILENAME.EXT] 解析为生成图块。
class GeneratedImageBlockSyntax extends md.BlockSyntax {
  const GeneratedImageBlockSyntax();

  static final RegExp _pattern = RegExp(
    r'^[ ]{0,3}\[\s*generated-image\s*:\s*([^\]\s]+)\s*\][ \t]*$',
    caseSensitive: false,
  );

  @override
  RegExp get pattern => _pattern;

  @override
  md.Node parse(md.BlockParser parser) {
    final Match match = _pattern.firstMatch(parser.current.content)!;
    parser.advance();
    final md.Element element = md.Element.empty(_kGeneratedImageBlockTag);
    element.attributes[_kGeneratedImageFilenameAttribute] =
        (match.group(1) ?? '').trim();
    unawaited(
      FlutterLogger.nativeInfo(
        'AI_IMAGE',
        'md.parse.generated_block filename=${element.attributes[_kGeneratedImageFilenameAttribute]}',
      ),
    );
    return element;
  }
}

/// 自定义块语法：将独占一行的 [generated-image-loading: ID] 解析为生图骨架块。
class GeneratedImageLoadingBlockSyntax extends md.BlockSyntax {
  const GeneratedImageLoadingBlockSyntax();

  static final RegExp _pattern = RegExp(
    r'^[ ]{0,3}\[\s*generated-image-loading\s*:\s*([^\]\s]+)\s*\][ \t]*$',
    caseSensitive: false,
  );

  @override
  RegExp get pattern => _pattern;

  @override
  md.Node parse(md.BlockParser parser) {
    final Match match = _pattern.firstMatch(parser.current.content)!;
    parser.advance();
    final md.Element element = md.Element.empty(
      _kGeneratedImageLoadingBlockTag,
    );
    element.attributes[_kGeneratedImageLoadingIdAttribute] =
        (match.group(1) ?? '').trim();
    unawaited(
      FlutterLogger.nativeInfo(
        'AI_IMAGE',
        'md.parse.loading_block id=${element.attributes[_kGeneratedImageLoadingIdAttribute]}',
      ),
    );
    return element;
  }
}

/// 在跳过行内代码 (`...`) 的前提下，将 \(..\)/\[..] 替换成 <math-inline>/<math-block> 标签。
String _replaceLatexToTagsSkippingInlineCode(String input) {
  final inlineCode = RegExp(r'`[^`\n]*`'); // 单行内联代码
  final parts = <String>[];
  int p = 0;
  for (final m in inlineCode.allMatches(input)) {
    if (m.start > p) {
      parts.add(_replaceLatexToTags(input.substring(p, m.start)));
    }
    parts.add(input.substring(m.start, m.end)); // 保持内联代码原样
    p = m.end;
  }
  if (p < input.length) {
    parts.add(_replaceLatexToTags(input.substring(p)));
  }
  return parts.join();
}

/// 将 \(..\) -> <math-inline>..</math-inline>
/// 将 \[..] -> <math-block>..</math-block>
String _replaceLatexToTags(String text) {
  // 块级 \[ ... \]（支持跨行）
  text = text.replaceAllMapped(
    RegExp(r'\\\[(.+?)\\\]', dotAll: true),
    (m) => '\n<math-block>${(m.group(1) ?? '').trim()}</math-block>\n',
  );

  // 行内 \( ... \)（不跨行）
  text = text.replaceAllMapped(
    RegExp(r'\\\((.+?)\\\)'),
    (m) => '<math-inline>${(m.group(1) ?? '').trim()}</math-inline>',
  );

  return text;
}

/// 自定义 Inline 语法：将 [evidence: FILENAME.EXT] 解析为 evidence 元素
class EvidenceInlineSyntax extends md.InlineSyntax {
  EvidenceInlineSyntax() : super(r'\[evidence:\s*([^\]]+?)\s*\]');

  @override
  bool onMatch(md.InlineParser parser, Match match) {
    final name = (match.group(1) ?? '').trim();
    if (name.isEmpty) return false;
    final el = md.Element.text('evidence', name);
    parser.addNode(el);
    return true;
  }
}

/// 自定义 Inline 语法：将 [generated-image: FILENAME.EXT] 解析为生成图元素。
class GeneratedImageInlineSyntax extends md.InlineSyntax {
  GeneratedImageInlineSyntax()
    : super(
        r'\[\s*generated-image\s*:\s*([^\]\s]+)\s*\]',
        caseSensitive: false,
      );

  @override
  bool onMatch(md.InlineParser parser, Match match) {
    final String name = (match.group(1) ?? '').trim();
    if (name.isEmpty) return false;
    final md.Element el = md.Element.text('generated-image', name);
    parser.addNode(el);
    unawaited(
      FlutterLogger.nativeInfo(
        'AI_IMAGE',
        'md.parse.generated_inline filename=$name',
      ),
    );
    return true;
  }
}

/// 自定义 Inline 语法：将 [generated-image-loading: ID] 解析为生成图骨架元素。
class GeneratedImageLoadingInlineSyntax extends md.InlineSyntax {
  GeneratedImageLoadingInlineSyntax()
    : super(
        r'\[\s*generated-image-loading\s*:\s*([^\]\s]+)\s*\]',
        caseSensitive: false,
      );

  @override
  bool onMatch(md.InlineParser parser, Match match) {
    final String id = (match.group(1) ?? '').trim();
    if (id.isEmpty) return false;
    final md.Element el = md.Element.text('generated-image-loading', id);
    parser.addNode(el);
    unawaited(
      FlutterLogger.nativeInfo('AI_IMAGE', 'md.parse.loading_inline id=$id'),
    );
    return true;
  }
}

class AppInlineSyntax extends md.InlineSyntax {
  AppInlineSyntax()
    : super(r'\[\s*app\s*[:：]\s*([^\]]+?)\s*\]', caseSensitive: false);

  @override
  bool onMatch(md.InlineParser parser, Match match) {
    final String raw = (match.group(1) ?? '').trim();
    if (raw.isEmpty) return false;
    final md.Element el = md.Element.text('app-ref', raw);
    parser.addNode(el);
    return true;
  }
}

class _ParsedAppRef {
  const _ParsedAppRef({
    required this.label,
    required this.packageName,
    required this.lookupNameLower,
  });

  final String label;
  final String packageName;
  final String lookupNameLower;
}

bool _looksLikeAndroidPackageName(String text) {
  final String trimmed = text.trim();
  if (trimmed.isEmpty) return false;
  return RegExp(r'^[a-zA-Z0-9]+(\.[a-zA-Z0-9_]+)+$').hasMatch(trimmed);
}

_ParsedAppRef _parseAppRef(String raw) {
  final List<String> parts = raw
      .split('|')
      .map((String e) => e.trim())
      .where((String e) => e.isNotEmpty)
      .toList(growable: false);

  String label = '';
  String packageName = '';
  for (final String part in parts) {
    final String lower = part.toLowerCase();
    if ((lower.startsWith('pkg=') || lower.startsWith('package=')) &&
        packageName.isEmpty) {
      packageName = part.substring(part.indexOf('=') + 1).trim();
      continue;
    }
    if (lower.startsWith('name=') && label.isEmpty) {
      label = part.substring(part.indexOf('=') + 1).trim();
      continue;
    }
    if (_looksLikeAndroidPackageName(part) && packageName.isEmpty) {
      packageName = part;
      continue;
    }
    if (label.isEmpty) label = part;
  }

  if (label.isEmpty && packageName.isNotEmpty) {
    label = packageName;
  }

  return _ParsedAppRef(
    label: label,
    packageName: packageName,
    lookupNameLower: label.trim().toLowerCase(),
  );
}

/// 渲染 <math-inline> 与 <math-block> 的 builder。
class _MathBuilder extends MarkdownElementBuilder {
  _MathBuilder({this.inlineTextStyle, this.blockTextStyle});

  final TextStyle? inlineTextStyle;
  final TextStyle? blockTextStyle;

  @override
  Widget? visitElementAfter(element, TextStyle? preferredStyle) {
    final latex = element.textContent.trim();
    final tag = element.tag;
    if (tag == 'math-block') {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: fm.Math.tex(
          latex,
          textStyle: (blockTextStyle ?? preferredStyle),
          mathStyle: fm.MathStyle.display,
        ),
      );
    } else if (tag == 'math-inline') {
      return fm.Math.tex(
        latex,
        textStyle: (inlineTextStyle ?? preferredStyle),
        mathStyle: fm.MathStyle.text,
      );
    }
    return null;
  }
}

class _ChartBlockBuilder extends MarkdownElementBuilder {
  @override
  bool isBlockElement() => true;

  @override
  Widget? visitElementAfterWithContext(
    BuildContext context,
    md.Element element,
    TextStyle? preferredStyle,
    TextStyle? parentStyle,
  ) {
    final String encoded =
        (element.attributes[kChartBlockPayloadAttribute] ?? element.textContent)
            .trim();
    final String? rawJson = decodeChartBlockPayload(encoded);
    return ChatMarkdownChartBlock(
      rawJson: rawJson ?? '',
      spec: rawJson == null ? null : ChatChartSpecV1.tryParseJson(rawJson),
    );
  }
}

class _LinkChipBuilder extends MarkdownElementBuilder {
  @override
  Widget? visitElementAfterWithContext(
    BuildContext context,
    md.Element element,
    TextStyle? preferredStyle,
    TextStyle? parentStyle,
  ) {
    final String href = (element.attributes['href'] ?? '').trim();
    if (href.isEmpty) return null;

    final ThemeData theme = Theme.of(context);
    final bool dark = theme.brightness == Brightness.dark;
    final Color accent = dark
        ? const Color(0xFF7DB7FF)
        : const Color(0xFF2563EB);
    final TextStyle baseStyle =
        preferredStyle ??
        parentStyle ??
        theme.textTheme.bodyMedium ??
        const TextStyle(fontSize: 13, height: 1.2);
    final String host = _markdownLinkHost(element.textContent, href);
    final Widget fallback = Icon(Icons.link_rounded, size: 13, color: accent);
    final Widget icon = host.isEmpty
        ? fallback
        : ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: Image.network(
              _markdownFaviconUrlForHost(host),
              width: 16,
              height: 16,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => fallback,
            ),
          );

    final Widget chip = SizedBox(
      width: 20,
      height: 20,
      child: Center(child: icon),
    );

    final Widget tappable = GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => _openMarkdownLink(href),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 1, vertical: 1),
        child: chip,
      ),
    );

    return Text.rich(
      TextSpan(
        style: baseStyle,
        children: <InlineSpan>[
          WidgetSpan(alignment: PlaceholderAlignment.middle, child: tappable),
        ],
      ),
    );
  }
}

String _markdownLinkHost(String rawText, String href) {
  final String fromHref = _markdownHostFromText(href);
  if (fromHref.isNotEmpty) return fromHref;
  return _markdownHostFromText(rawText);
}

String _markdownHostFromText(String value) {
  String s = value.trim();
  if (s.isEmpty) return '';
  final Uri? uri = Uri.tryParse(s);
  final String parsedHost = uri?.host.trim() ?? '';
  if (parsedHost.isNotEmpty) {
    return parsedHost.startsWith('www.') ? parsedHost.substring(4) : parsedHost;
  }
  s = s.replaceFirst(RegExp(r'^[a-zA-Z][a-zA-Z0-9+.-]*://'), '');
  s = s.split(RegExp(r'[,\s]+')).first.trim();
  s = s.split('/').first.split('?').first.split('#').first;
  if (s.contains('@')) s = s.split('@').last;
  if (s.contains(':')) s = s.split(':').first;
  if (!s.contains('.')) return '';
  return s.startsWith('www.') ? s.substring(4) : s;
}

String _markdownFaviconUrlForHost(String host) {
  final String h = _markdownHostFromText(host);
  if (h.isEmpty) return '';
  return 'https://favicon.im/${Uri.encodeComponent(h)}';
}

Future<void> _openMarkdownLink(String href) async {
  final Uri? uri = Uri.tryParse(href.trim());
  if (uri == null) return;
  try {
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  } catch (_) {}
}

class _AppRefBuilder extends MarkdownElementBuilder {
  _AppRefBuilder({
    required this.appIconByPackage,
    required this.appIconByNameLower,
    required this.appNameByPackage,
  });

  final Map<String, Uint8List?> appIconByPackage;
  final Map<String, Uint8List?> appIconByNameLower;
  final Map<String, String> appNameByPackage;

  @override
  Widget? visitElementAfterWithContext(
    BuildContext context,
    element,
    TextStyle? preferredStyle,
    TextStyle? parentStyle,
  ) {
    final String raw = element.textContent.trim();
    if (raw.isEmpty) return null;

    final _ParsedAppRef parsed = _parseAppRef(raw);
    Uint8List? iconBytes;
    String label = parsed.label.trim();

    if (parsed.packageName.isNotEmpty) {
      iconBytes = appIconByPackage[parsed.packageName];
      final String mappedName = (appNameByPackage[parsed.packageName] ?? '')
          .trim();
      if (label.isEmpty && mappedName.isNotEmpty) {
        label = mappedName;
      }
    }
    if (iconBytes == null && parsed.lookupNameLower.isNotEmpty) {
      iconBytes = appIconByNameLower[parsed.lookupNameLower];
    }

    if (label.isEmpty) label = raw;
    final ThemeData theme = Theme.of(context);
    final ColorScheme colorScheme = theme.colorScheme;
    final TextStyle fallbackStyle =
        theme.textTheme.bodyMedium ??
        const TextStyle(fontSize: 13, height: 1.2);
    final TextStyle textStyle = (preferredStyle ?? parentStyle ?? fallbackStyle)
        .copyWith(
          fontSize:
              (preferredStyle?.fontSize ??
              parentStyle?.fontSize ??
              fallbackStyle.fontSize ??
              13),
          height:
              preferredStyle?.height ??
              parentStyle?.height ??
              fallbackStyle.height ??
              1.2,
          color:
              preferredStyle?.color ??
              parentStyle?.color ??
              fallbackStyle.color ??
              colorScheme.onSurface,
        );

    final Widget leading = (iconBytes != null && iconBytes.isNotEmpty)
        ? ClipRRect(
            borderRadius: BorderRadius.circular(AppTheme.radiusSm),
            child: Image.memory(
              iconBytes,
              width: 16,
              height: 16,
              fit: BoxFit.cover,
              filterQuality: FilterQuality.low,
            ),
          )
        : Icon(
            Icons.apps_rounded,
            size: 16,
            color:
                textStyle.color?.withValues(alpha: 0.85) ??
                colorScheme.onSurfaceVariant,
          );

    final Widget chip = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 1, vertical: 1),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.9),
          borderRadius: BorderRadius.circular(AppTheme.radiusSm),
          border: Border.all(
            color: colorScheme.outline.withValues(alpha: 0.55),
            width: 1,
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              leading,
              if (label.isNotEmpty) const SizedBox(width: 5),
              if (label.isNotEmpty)
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 180),
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: textStyle.copyWith(
                      fontWeight: FontWeight.w600,
                      height: 1.1,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );

    return Text.rich(
      TextSpan(
        style: textStyle,
        children: <InlineSpan>[
          WidgetSpan(alignment: PlaceholderAlignment.middle, child: chip),
        ],
      ),
    );
  }
}

class _EvidenceBuilder extends MarkdownElementBuilder {
  _EvidenceBuilder({
    required this.evidenceNameToPath,
    required this.orderedEvidencePaths,
    required this.showLoadingPlaceholder,
    required this.screenshotByPath,
    this.perfLogger,
  });

  final Map<String, String> evidenceNameToPath;
  final List<String> orderedEvidencePaths;
  final bool showLoadingPlaceholder;
  final Map<String, ScreenshotRecord?> screenshotByPath;
  final UiPerfLogger? perfLogger;
  static final Set<String> _loggedMissing = <String>{};
  static final Set<String> _loggedPlaceholder = <String>{};
  static final Set<String> _loggedResolved = <String>{};

  @override
  Widget? visitElementAfter(element, TextStyle? preferredStyle) {
    // InlineSyntax 解析将文件名放在 textContent 中
    final String? name = element.textContent.trim();
    if (name == null || name.isEmpty) return null;
    String? resolvedPath = evidenceNameToPath[name];
    // 兜底：若解析表未命中，但 name 本身看起来就是绝对路径，则直接使用
    if (resolvedPath == null || resolvedPath.isEmpty) {
      if (_looksLikeAbsoluteEvidencePath(name)) {
        resolvedPath = name;
      }
    }
    if (resolvedPath == null || resolvedPath.isEmpty) {
      // While evidence paths are being resolved (e.g. on page restore), render a
      // fixed-size skeleton instead of showing the raw tag text.
      if (showLoadingPlaceholder) {
        final int loggerId = (perfLogger == null)
            ? 0
            : identityHashCode(perfLogger!);
        if (_loggedPlaceholder.add('$loggerId|$name')) {
          perfLogger?.log('evidence.placeholder', detail: 'name=$name');
        }
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Builder(
            builder: (context) {
              Widget wrapDebug(Widget child) {
                if (!_kChatEvidenceDebugUi) return child;
                final String p = resolvedPath ?? '';
                final String dbg =
                    'evidence="$name"\nloading=$showLoadingPlaceholder\nhasKey=${evidenceNameToPath.containsKey(name)} mapSize=${evidenceNameToPath.length}\npath="${_shortenDebugText(p)}"';
                return Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    child,
                    const SizedBox(height: 2),
                    Text(
                      dbg,
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        fontSize: 10,
                        height: 1.05,
                        fontFamily: 'monospace',
                        color: Theme.of(
                          context,
                        ).colorScheme.onSurfaceVariant.withValues(alpha: 0.85),
                      ),
                    ),
                  ],
                );
              }

              final BorderRadius br = BorderRadius.circular(AppTheme.radiusLg);
              final Color base = Theme.of(
                context,
              ).colorScheme.surfaceContainerHighest.withValues(alpha: 0.65);
              return wrapDebug(
                Container(
                  constraints: const BoxConstraints.tightFor(
                    width: 96,
                    height: 168,
                  ),
                  decoration: BoxDecoration(
                    border: Border.all(
                      color: Theme.of(
                        context,
                      ).colorScheme.outline.withValues(alpha: 0.12),
                      width: 1,
                    ),
                    borderRadius: br,
                  ),
                  child: ClipRRect(
                    borderRadius: br,
                    child: Shimmer.fromColors(
                      baseColor: base,
                      highlightColor: _kThinkingShimmerHighlightColor,
                      direction: ShimmerDirection.ltr,
                      period: const Duration(milliseconds: 2200),
                      child: Container(color: base),
                    ),
                  ),
                ),
              );
            },
          ),
        );
      }
      // 便于排查：当引用格式正确但无法解析到本地文件时，打一次日志（去重）。
      final int loggerId = (perfLogger == null)
          ? 0
          : identityHashCode(perfLogger!);
      if (_loggedMissing.add('$loggerId|$name')) {
        try {
          FlutterLogger.nativeWarn('UI.Chat-Evidence', '无法解析证据引用：' + name);
        } catch (_) {}
        perfLogger?.log('evidence.unresolved', detail: 'name=$name');
      }
      // 未匹配到文件名时，回退为可选的明文占位，避免渲染空白
      return Builder(
        builder: (context) => Text(
          '${AppLocalizations.of(context).evidencePrefix}$name]',
          style: preferredStyle,
        ),
      );
    }
    final int loggerId = (perfLogger == null)
        ? 0
        : identityHashCode(perfLogger!);
    if (_loggedResolved.add('$loggerId|$resolvedPath')) {
      perfLogger?.log('evidence.resolved', detail: 'name=$name');
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Builder(
        builder: (context) {
          Widget wrapDebug(Widget child) {
            if (!_kChatEvidenceDebugUi) return child;
            final String p = resolvedPath ?? '';
            final bool exists = p.isNotEmpty ? File(p).existsSync() : false;
            final String dbg =
                'evidence="$name"\nloading=$showLoadingPlaceholder\nhasKey=${evidenceNameToPath.containsKey(name)} mapSize=${evidenceNameToPath.length}\nexists=$exists\npath="${_shortenDebugText(p)}"';
            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                child,
                const SizedBox(height: 2),
                Text(
                  dbg,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    fontSize: 10,
                    height: 1.05,
                    fontFamily: 'monospace',
                    color: Theme.of(
                      context,
                    ).colorScheme.onSurfaceVariant.withValues(alpha: 0.85),
                  ),
                ),
              ],
            );
          }

          final BorderRadius br = BorderRadius.circular(AppTheme.radiusLg);
          final String path = resolvedPath!.trim();
          final File file = File(path);
          final ScreenshotRecord? screenshot = screenshotByPath[path];
          final bool extraNsfwMask =
              NsfwPreferenceService.instance.isAiNsfwCached(filePath: path) ||
              NsfwPreferenceService.instance.isSegmentNsfwCached(
                filePath: path,
              );
          final ImageProvider imageProvider = ResizeImage(
            FileImage(file),
            width: 192,
          );
          final Widget thumbCore = ScreenshotImageWidget(
            file: file,
            imageProvider: imageProvider,
            privacyMode: true,
            extraNsfwMask: extraNsfwMask,
            screenshot: screenshot,
            width: 96,
            height: 168,
            fit: BoxFit.cover,
            borderRadius: br,
            targetWidth: 192,
            showNsfwButton: true,
            showTimelineJumpButton: true,
            onReveal: () {
              // 保留原有：点击“显示”仍可进入大图查看
              () async {
                try {
                  final List<String> galleryPaths =
                      (orderedEvidencePaths.isNotEmpty)
                      ? orderedEvidencePaths
                      : <String>[path];
                  final List<String> paths = <String>{...galleryPaths}.toList();
                  if (!paths.contains(path)) paths.insert(0, path);
                  final int initialIndex = paths.indexOf(path);
                  try {
                    await FlutterLogger.info(
                      'UI.Chat-ImageTap：跳转查看器（显示）数量=' + paths.length.toString(),
                    );
                  } catch (_) {}
                  final nav =
                      NavigationService.instance.navigatorKey.currentState;
                  nav?.pushNamed(
                    '/screenshot_viewer',
                    arguments: {
                      'paths': paths,
                      'initialIndex': initialIndex < 0 ? 0 : initialIndex,
                      'appName': 'Unknown',
                      'appInfo': AppInfo(
                        packageName: 'unknown',
                        appName: 'Unknown',
                        icon: null,
                        version: '',
                        isSystemApp: false,
                      ),
                      'multiApp': true,
                      'singleMode': true,
                    },
                  );
                } catch (_) {}
              }();
            },
            onTap: () {
              // 保留原有：点击缩略图进入大图
              () async {
                try {
                  final List<String> galleryPaths =
                      (orderedEvidencePaths.isNotEmpty)
                      ? orderedEvidencePaths
                      : <String>[path];
                  final List<String> paths = <String>{...galleryPaths}.toList();
                  if (!paths.contains(path)) paths.insert(0, path);
                  final int initialIndex = paths.indexOf(path);
                  try {
                    await FlutterLogger.info(
                      'UI.Chat-ImageTap：跳转查看器（点击）数量=' + paths.length.toString(),
                    );
                  } catch (_) {}
                  final nav =
                      NavigationService.instance.navigatorKey.currentState;
                  nav?.pushNamed(
                    '/screenshot_viewer',
                    arguments: {
                      'paths': paths,
                      'initialIndex': initialIndex < 0 ? 0 : initialIndex,
                      'appName': 'Unknown',
                      'appInfo': AppInfo(
                        packageName: 'unknown',
                        appName: 'Unknown',
                        icon: null,
                        version: '',
                        isSystemApp: false,
                      ),
                      'multiApp': true,
                      'singleMode': true,
                    },
                  );
                } catch (_) {}
              }();
            },
          );
          final Widget thumbImage = (perfLogger == null)
              ? thumbCore
              : _PerfImageProbe(
                  perfLogger: perfLogger!,
                  tag: 'evidence:$name',
                  imageProvider: imageProvider,
                  child: thumbCore,
                );
          return wrapDebug(
            Container(
              constraints: const BoxConstraints.tightFor(
                width: 96,
                height: 168,
              ),
              decoration: BoxDecoration(
                border: Border.all(
                  color: Theme.of(
                    context,
                  ).colorScheme.outline.withValues(alpha: 0.12),
                  width: 1,
                ),
                borderRadius: br,
              ),
              // 已在 ScreenshotImageWidget 内显示时间线按钮，这里不再叠加，避免错位与重复
              child: thumbImage,
            ),
          );
        },
      ),
    );
  }
}

class _GeneratedImageLookup {
  const _GeneratedImageLookup({required this.filename, this.path});

  final String filename;
  final String? path;

  bool get available => (path ?? '').trim().isNotEmpty;
}

class _GeneratedImagePreview extends StatefulWidget {
  const _GeneratedImagePreview({required this.filename, this.perfLogger});

  final String filename;
  final UiPerfLogger? perfLogger;

  @override
  State<_GeneratedImagePreview> createState() => _GeneratedImagePreviewState();
}

class _GeneratedImagePreviewState extends State<_GeneratedImagePreview> {
  static final Map<String, _GeneratedImageLookup> _lookupCache =
      <String, _GeneratedImageLookup>{};

  late Future<_GeneratedImageLookup> _future;

  @override
  void initState() {
    super.initState();
    unawaited(
      FlutterLogger.nativeInfo(
        'AI_IMAGE',
        'preview.init filename=${widget.filename}',
      ),
    );
    _future = _resolve();
  }

  @override
  void didUpdateWidget(covariant _GeneratedImagePreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.filename != widget.filename) {
      unawaited(
        FlutterLogger.nativeInfo(
          'AI_IMAGE',
          'preview.update old=${oldWidget.filename} new=${widget.filename}',
        ),
      );
      _future = _resolve();
    }
  }

  Future<_GeneratedImageLookup> _resolve() async {
    final String name = widget.filename.trim();
    if (name.isEmpty || name.contains('/') || name.contains('\\')) {
      unawaited(
        FlutterLogger.nativeWarn(
          'AI_IMAGE',
          'preview.resolve.invalid filename=${widget.filename}',
        ),
      );
      return _GeneratedImageLookup(filename: name);
    }
    final _GeneratedImageLookup? cached = _lookupCache[name];
    if (cached != null && cached.available) {
      widget.perfLogger?.log('generatedImage.cacheHit', detail: name);
      _logMarkdownPerf(
        'GeneratedImage.resolve.cacheHit',
        detail: 'filename=$name path=${cached.path}',
      );
      unawaited(
        FlutterLogger.nativeInfo(
          'AI_IMAGE',
          'preview.resolve.cache_hit filename=$name path=${cached.path}',
        ),
      );
      return cached;
    }
    final Stopwatch sw = Stopwatch()..start();
    try {
      _logMarkdownPerf(
        'GeneratedImage.resolve.start',
        detail: 'filename=$name',
      );
      unawaited(
        FlutterLogger.nativeInfo(
          'AI_IMAGE',
          'preview.resolve.begin filename=$name',
        ),
      );
      final Map<String, String> map = await ScreenshotDatabase.instance
          .findAiGeneratedImagePathsByFilenames(<String>{name})
          .timeout(const Duration(seconds: 4));
      _logMarkdownPerf(
        'GeneratedImage.resolve.db.done',
        stopwatch: sw,
        detail: 'filename=$name found=${map.containsKey(name)}',
      );
      final String path = (map[name] ?? '').trim();
      if (path.isEmpty) {
        widget.perfLogger?.log('generatedImage.unavailable', detail: name);
        unawaited(
          FlutterLogger.nativeWarn(
            'AI_IMAGE',
            'preview.resolve.no_db_path filename=$name keys=${map.keys.join("|")}',
          ),
        );
        return _GeneratedImageLookup(filename: name);
      }
      final bool exists = await File(path).exists();
      _logMarkdownPerf(
        'GeneratedImage.resolve.exists.done',
        stopwatch: sw,
        detail: 'filename=$name exists=$exists',
      );
      if (!exists) {
        widget.perfLogger?.log('generatedImage.missingFile', detail: name);
        unawaited(
          FlutterLogger.nativeWarn(
            'AI_IMAGE',
            'preview.resolve.missing_file filename=$name path=$path',
          ),
        );
        return _GeneratedImageLookup(filename: name);
      }
      final int bytes = await File(path).length();
      widget.perfLogger?.log('generatedImage.resolved', detail: name);
      final _GeneratedImageLookup lookup = _GeneratedImageLookup(
        filename: name,
        path: path,
      );
      _lookupCache[name] = lookup;
      _logMarkdownPerf(
        'GeneratedImage.resolve.success',
        stopwatch: sw,
        detail: 'filename=$name bytes=$bytes',
      );
      unawaited(
        FlutterLogger.nativeInfo(
          'AI_IMAGE',
          'preview.resolve.success filename=$name path=$path bytes=$bytes ms=${sw.elapsedMilliseconds}',
        ),
      );
      return lookup;
    } catch (e) {
      _logMarkdownPerf(
        'GeneratedImage.resolve.error',
        stopwatch: sw,
        detail: 'filename=$name err=$e',
      );
      unawaited(
        FlutterLogger.nativeError(
          'AI_IMAGE',
          'preview.resolve.error filename=$name err=$e',
        ),
      );
      return _GeneratedImageLookup(filename: name);
    } finally {
      // Avoid keeping a loading skeleton forever if a platform/database call
      // hangs in a constrained test or startup environment.
      if (sw.elapsedMilliseconds > 4000) {
        widget.perfLogger?.log(
          'generatedImage.resolve.slow',
          detail: '$name ${sw.elapsedMilliseconds}ms',
        );
      }
    }
  }

  void _openViewer(String path) {
    final String p = path.trim();
    if (p.isEmpty) return;
    final nav = NavigationService.instance.navigatorKey.currentState;
    if (nav == null) return;
    final String title = AppLocalizations.of(
      nav.context,
    ).aiGeneratedDefaultTitle;
    nav.pushNamed(
      '/screenshot_viewer',
      arguments: {
        'paths': <String>[p],
        'initialIndex': 0,
        'appName': title,
        'appInfo': AppInfo(
          packageName: 'generated.image',
          appName: title,
          icon: null,
          version: '',
          isSystemApp: false,
        ),
        'multiApp': false,
        'singleMode': true,
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<_GeneratedImageLookup>(
      future: _future,
      builder: (context, snapshot) {
        final bool loading = snapshot.connectionState != ConnectionState.done;
        if (loading) {
          unawaited(
            FlutterLogger.nativeInfo(
              'AI_IMAGE',
              'preview.build.loading filename=${widget.filename} state=${snapshot.connectionState.name}',
            ),
          );
          return _buildLoading(context);
        }
        final _GeneratedImageLookup lookup =
            snapshot.data ?? _GeneratedImageLookup(filename: widget.filename);
        if (!lookup.available) {
          unawaited(
            FlutterLogger.nativeWarn(
              'AI_IMAGE',
              'preview.build.unavailable filename=${widget.filename}',
            ),
          );
          return _buildUnavailable(context);
        }
        unawaited(
          FlutterLogger.nativeInfo(
            'AI_IMAGE',
            'preview.build.image filename=${widget.filename} path=${lookup.path}',
          ),
        );
        return _buildImage(context, lookup.path!);
      },
    );
  }

  Widget _buildLoading(BuildContext context) {
    return _buildGeneratedImageLoading(context);
  }

  Widget _buildUnavailable(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return _buildGeneratedImagePlaceholder(
      context,
      Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.broken_image_outlined,
              size: 32,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 8),
            Text(
              'Image unavailable',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w600,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildImage(BuildContext context, String path) {
    final File file = File(path);
    final ImageProvider provider = FileImage(file);
    final Widget image = Image(
      image: provider,
      fit: BoxFit.fitWidth,
      width: double.infinity,
      filterQuality: FilterQuality.medium,
      gaplessPlayback: true,
      errorBuilder: (context, error, stackTrace) {
        unawaited(
          FlutterLogger.nativeError(
            'AI_IMAGE',
            'preview.image.error filename=${widget.filename} path=$path err=$error',
          ),
        );
        return _buildUnavailable(context);
      },
    );
    final Widget probedImage = widget.perfLogger == null
        ? image
        : _PerfImageProbe(
            perfLogger: widget.perfLogger!,
            tag: 'generated-image:${widget.filename}',
            imageProvider: provider,
            child: image,
          );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => _openViewer(path),
        child: probedImage,
      ),
    );
  }
}

class _GeneratedImageBuilder extends MarkdownElementBuilder {
  _GeneratedImageBuilder({required this.perfLogger});

  final UiPerfLogger? perfLogger;

  @override
  Widget? visitElementAfterWithContext(
    BuildContext context,
    md.Element element,
    TextStyle? preferredStyle,
    TextStyle? parentStyle,
  ) {
    final String name =
        (element.attributes[_kGeneratedImageFilenameAttribute] ??
                element.textContent)
            .trim();
    if (name.isEmpty) return null;
    unawaited(
      FlutterLogger.nativeInfo(
        'AI_IMAGE',
        'md.builder.generated_image filename=$name tag=${element.tag}',
      ),
    );
    return _GeneratedImagePreview(filename: name, perfLogger: perfLogger);
  }
}

class _GeneratedImageBlockBuilder extends _GeneratedImageBuilder {
  _GeneratedImageBlockBuilder({required super.perfLogger});

  @override
  bool isBlockElement() => true;
}

Widget _buildGeneratedImagePlaceholder(BuildContext context, Widget child) {
  final ThemeData theme = Theme.of(context);
  final BorderRadius borderRadius = BorderRadius.circular(AppTheme.radiusLg);
  return Padding(
    padding: const EdgeInsets.symmetric(vertical: 6),
    child: LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final bool hasRowWidth =
            constraints.hasBoundedWidth &&
            constraints.maxWidth.isFinite &&
            constraints.maxWidth > 0;
        final double width = hasRowWidth ? constraints.maxWidth : 220;

        return SizedBox(
          width: width,
          height: 220,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest.withValues(
                alpha: 0.5,
              ),
              borderRadius: borderRadius,
              border: Border.all(
                color: theme.colorScheme.outline.withValues(alpha: 0.18),
                width: 1,
              ),
            ),
            child: ClipRRect(borderRadius: borderRadius, child: child),
          ),
        );
      },
    ),
  );
}

Widget _buildGeneratedImageLoading(BuildContext context) {
  final Color base = Theme.of(
    context,
  ).colorScheme.surfaceContainerHighest.withValues(alpha: 0.65);
  return _buildGeneratedImagePlaceholder(
    context,
    Shimmer.fromColors(
      baseColor: base,
      highlightColor: _kThinkingShimmerHighlightColor,
      period: const Duration(milliseconds: 2200),
      child: Container(color: base),
    ),
  );
}

class _GeneratedImageLoadingBuilder extends MarkdownElementBuilder {
  @override
  Widget? visitElementAfterWithContext(
    BuildContext context,
    md.Element element,
    TextStyle? preferredStyle,
    TextStyle? parentStyle,
  ) {
    final String id =
        (element.attributes[_kGeneratedImageLoadingIdAttribute] ??
                element.textContent)
            .trim();
    unawaited(
      FlutterLogger.nativeInfo(
        'AI_IMAGE',
        'md.builder.loading id=$id tag=${element.tag}',
      ),
    );
    return _buildGeneratedImageLoading(context);
  }
}

class _GeneratedImageLoadingBlockBuilder extends _GeneratedImageLoadingBuilder {
  @override
  bool isBlockElement() => true;
}

class _PerfImageProbe extends StatefulWidget {
  const _PerfImageProbe({
    required this.perfLogger,
    required this.tag,
    required this.imageProvider,
    required this.child,
  });

  final UiPerfLogger perfLogger;
  final String tag;
  final ImageProvider imageProvider;
  final Widget child;

  @override
  State<_PerfImageProbe> createState() => _PerfImageProbeState();
}

class _PerfImageProbeState extends State<_PerfImageProbe> {
  ImageStream? _stream;
  ImageStreamListener? _listener;
  final Stopwatch _sw = Stopwatch();
  bool _done = false;

  @override
  void initState() {
    super.initState();
    _sw
      ..reset()
      ..start();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _attach();
  }

  @override
  void didUpdateWidget(covariant _PerfImageProbe oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.imageProvider != widget.imageProvider) {
      _done = false;
      _sw
        ..reset()
        ..start();
      _detach();
      _attach();
    }
  }

  void _attach() {
    final ImageStream newStream = widget.imageProvider.resolve(
      createLocalImageConfiguration(context),
    );
    _detach();
    _stream = newStream;
    _listener = ImageStreamListener(
      (ImageInfo info, bool sync) {
        if (_done) return;
        _done = true;
        widget.perfLogger.log(
          'image.decoded',
          detail: 'ms=${_sw.elapsedMilliseconds} sync=$sync ${widget.tag}',
        );
      },
      onError: (Object error, StackTrace? stackTrace) {
        if (_done) return;
        _done = true;
        widget.perfLogger.log(
          'image.error',
          detail: 'ms=${_sw.elapsedMilliseconds} ${widget.tag} err=$error',
        );
      },
    );
    _stream!.addListener(_listener!);
  }

  void _detach() {
    if (_stream != null && _listener != null) {
      _stream!.removeListener(_listener!);
    }
    _stream = null;
    _listener = null;
  }

  @override
  void dispose() {
    _detach();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// 提供给页面使用的统一配置对象。
class MarkdownMathConfig {
  MarkdownMathConfig({
    this.inlineTextStyle,
    this.blockTextStyle,
    Map<String, Uint8List?>? appIconByPackage,
    Map<String, Uint8List?>? appIconByNameLower,
    Map<String, String>? appNameByPackage,
    Map<String, String>? evidenceNameToPath,
    List<String>? orderedEvidencePaths,
    Map<String, ScreenshotRecord?>? screenshotByPath,
    this.evidenceLoading = false,
    this.perfLogger,
  }) : _appIconByPackage = appIconByPackage ?? const <String, Uint8List?>{},
       _appIconByNameLower = appIconByNameLower ?? const <String, Uint8List?>{},
       _appNameByPackage = appNameByPackage ?? const <String, String>{},
       _evidenceNameToPath = evidenceNameToPath ?? const <String, String>{},
       _orderedEvidencePaths = orderedEvidencePaths ?? const <String>[],
       _screenshotByPath =
           screenshotByPath ?? const <String, ScreenshotRecord?>{};

  final TextStyle? inlineTextStyle;
  final TextStyle? blockTextStyle;
  final bool evidenceLoading;
  final UiPerfLogger? perfLogger;
  final Map<String, Uint8List?> _appIconByPackage;
  final Map<String, Uint8List?> _appIconByNameLower;
  final Map<String, String> _appNameByPackage;
  final Map<String, String> _evidenceNameToPath;
  final List<String> _orderedEvidencePaths;
  final Map<String, ScreenshotRecord?> _screenshotByPath;

  Map<String, MarkdownElementBuilder> get builders => {
    'math-inline': _MathBuilder(inlineTextStyle: inlineTextStyle),
    'math-block': _MathBuilder(blockTextStyle: blockTextStyle),
    'a': _LinkChipBuilder(),
    kChartBlockTag: _ChartBlockBuilder(),
    'app-ref': _AppRefBuilder(
      appIconByPackage: _appIconByPackage,
      appIconByNameLower: _appIconByNameLower,
      appNameByPackage: _appNameByPackage,
    ),
    'evidence': _EvidenceBuilder(
      evidenceNameToPath: _evidenceNameToPath,
      orderedEvidencePaths: _orderedEvidencePaths,
      showLoadingPlaceholder: evidenceLoading,
      screenshotByPath: _screenshotByPath,
      perfLogger: perfLogger,
    ),
    'generated-image': _GeneratedImageBuilder(perfLogger: perfLogger),
    'generated-image-loading': _GeneratedImageLoadingBuilder(),
    _kGeneratedImageBlockTag: _GeneratedImageBlockBuilder(
      perfLogger: perfLogger,
    ),
    _kGeneratedImageLoadingBlockTag: _GeneratedImageLoadingBlockBuilder(),
  };

  List<md.InlineSyntax> get inlineSyntaxes => <md.InlineSyntax>[
    AppInlineSyntax(),
    EvidenceInlineSyntax(),
    GeneratedImageLoadingInlineSyntax(),
    GeneratedImageInlineSyntax(),
  ];

  List<md.BlockSyntax> get blockSyntaxes => <md.BlockSyntax>[
    const GeneratedImageLoadingBlockSyntax(),
    const GeneratedImageBlockSyntax(),
    const ChartBlockSyntax(),
  ];
}

class _Seg {
  final bool isCode;
  final String text;
  _Seg(this.isCode, this.text);
}
