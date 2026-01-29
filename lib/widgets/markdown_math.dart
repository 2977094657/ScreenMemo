import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_math_fork/flutter_math.dart' as fm;
import 'package:markdown/markdown.dart' as md;
import 'package:shimmer/shimmer.dart';
import 'dart:io';
import '../widgets/screenshot_image_widget.dart';
import '../widgets/timeline_jump_overlay.dart';
import '../services/screenshot_database.dart';
import '../services/nsfw_preference_service.dart';
import '../services/navigation_service.dart';
import '../services/timeline_jump_service.dart';
import '../services/ui_perf_logger.dart';
import '../models/screenshot_record.dart';
import '../models/app_info.dart';
import '../theme/app_theme.dart';
import '../services/flutter_logger.dart';

/// 说明：
/// - 仅在 AI 对话页面使用，用于渲染 Markdown 中的 LaTeX 数学公式；<think> 思考块在此阶段被移除。
/// - 复刻 rikkahub 的预处理：
///   * 将行内公式 \( ... \) 转为 <math-inline>...</math-inline>
///   * 将块级公式 \[ ... \] 转为 <math-block>...</math-block>
///   * 移除 <think>...</think>（不在可见正文中显示；思考在 UI 的 Reasoning 卡片展示）
///   * 跳过代码块 (```...```) 与行内代码 (`...`)
/// - 使用 flutter_markdown 的 builders 将 <math-inline>/<math-block> 渲染为 TeX。
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
///      styleSheet: ...,
///    )
///
/// 2) 需要在 pubspec.yaml 添加：
///    dependencies:
///      flutter_math_fork: ^0.7.2
///
/// 注意：本文件不引入 markdown 的自定义 Block/Inline 语法，纯靠预处理 + builders，
/// 以避免不同 markdown 版本 API 差异导致的编译问题。

// Keep the evidence loading shimmer consistent with the "thinking" shimmer.
const Color _kThinkingShimmerHighlightColor = Color(0xFFFFFBEB);
// TEMP (debug-only): show evidence resolve state under each image/placeholder.
// Remove once the restore/render issue is confirmed fixed.
const bool _kChatEvidenceDebugUi = kDebugMode;

String _shortenDebugText(String s, {int max = 72}) {
  final String t = s.trim();
  if (t.length <= max) return t;
  return '…' + t.substring(t.length - max);
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
      buf.write(s5);
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
    RegExp(r'(\[evidence:\s*[^\]\s]+\s*\])[。\.](?!\S)'),
    (m) => m.group(1) ?? '',
  );
  // 情况2：后面有若干空格再句号，例如: [evidence: a.png]   .
  input = input.replaceAllMapped(
    RegExp(r'(\[evidence:\s*[^\]\s]+\s*\])\s*[。\.]'),
    (m) => m.group(1) ?? '',
  );
  return input;
}

/// 将含有 [evidence: ...] 的行进行重排：
/// - 若一行同时包含文字与 evidence，则将 evidence 序列（仅由空白分隔的一组 evidence）单独放到一行；
/// - 若一行仅包含若干 evidence 与空白，则保持在同一行（可并排显示多张图片）。
/// - 仅处理普通文本行；代码块在上层已被剥离，不在此函数内处理。
String _ensureEvidenceBlocksOnOwnLine(String input) {
  final lines = input.replaceAll('\r\n', '\n').split('\n');
  final ev = RegExp(r'\[evidence:\s*[^\]\s]+\s*\]');
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
    if (isEv && (prev != null) && prev.trim().isNotEmpty && !prevIsEv)
      sb.writeln('');
    sb.writeln(cur);
    if (isEv && (next != null) && next.trim().isNotEmpty && !nextIsEv)
      sb.writeln('');
  }
  var s = sb.toString();
  if (s.endsWith('\n')) s = s.substring(0, s.length - 1);
  return s;
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
  EvidenceInlineSyntax() : super(r'\[evidence:\s*([^\]\s]+)\s*\]');

  @override
  bool onMatch(md.InlineParser parser, Match match) {
    final name = (match.group(1) ?? '').trim();
    if (name.isEmpty) return false;
    final el = md.Element.text('evidence', name);
    parser.addNode(el);
    return true;
  }
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
      final bool looksAbsolute =
          name.startsWith('/') || RegExp(r'^[A-Za-z]:[\\/]').hasMatch(name);
      if (looksAbsolute) {
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
      return Text('[evidence: ' + name + ']', style: preferredStyle);
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
              NsfwPreferenceService.instance.isSegmentNsfwCached(filePath: path);
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
    Map<String, String>? evidenceNameToPath,
    List<String>? orderedEvidencePaths,
    Map<String, ScreenshotRecord?>? screenshotByPath,
    this.evidenceLoading = false,
    this.perfLogger,
  }) : _evidenceNameToPath = evidenceNameToPath ?? const <String, String>{},
       _orderedEvidencePaths = orderedEvidencePaths ?? const <String>[],
       _screenshotByPath = screenshotByPath ?? const <String, ScreenshotRecord?>{};

  final TextStyle? inlineTextStyle;
  final TextStyle? blockTextStyle;
  final bool evidenceLoading;
  final UiPerfLogger? perfLogger;
  final Map<String, String> _evidenceNameToPath;
  final List<String> _orderedEvidencePaths;
  final Map<String, ScreenshotRecord?> _screenshotByPath;

  Map<String, MarkdownElementBuilder> get builders => {
    'math-inline': _MathBuilder(inlineTextStyle: inlineTextStyle),
    'math-block': _MathBuilder(blockTextStyle: blockTextStyle),
    'evidence': _EvidenceBuilder(
      evidenceNameToPath: _evidenceNameToPath,
      orderedEvidencePaths: _orderedEvidencePaths,
      showLoadingPlaceholder: evidenceLoading,
      screenshotByPath: _screenshotByPath,
      perfLogger: perfLogger,
    ),
  };

  List<md.InlineSyntax> get inlineSyntaxes => <md.InlineSyntax>[
    EvidenceInlineSyntax(),
  ];
}

class _Seg {
  final bool isCode;
  final String text;
  _Seg(this.isCode, this.text);
}
