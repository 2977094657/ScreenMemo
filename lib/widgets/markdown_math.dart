import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_math_fork/flutter_math.dart' as fm;
import 'package:markdown/markdown.dart' as md;
import 'dart:io';
import '../widgets/screenshot_image_widget.dart';
import '../widgets/timeline_jump_overlay.dart';
import '../services/screenshot_database.dart';
import '../services/navigation_service.dart';
import '../services/timeline_jump_service.dart';
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
      final s3 = _removeTrailingPunctuationAfterEvidence(s2);
      final s4 = _ensureEvidenceBlocksOnOwnLine(s3);
      buf.write(s4);
    }
  }
  return buf.toString();
}

/// 从可见正文中移除 <think>...</think>（支持缺失闭合标签）。
String _removeThinkBlocks(String text) {
  final thinkRegex = RegExp(r'<think>([\s\S]*?)(?:</think>|$)', multiLine: true);
  return text.replaceAll(thinkRegex, '');
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
    if (isEv && (prev != null) && prev.trim().isNotEmpty && !prevIsEv) sb.writeln('');
    sb.writeln(cur);
    if (isEv && (next != null) && next.trim().isNotEmpty && !nextIsEv) sb.writeln('');
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
  _EvidenceBuilder({required this.evidenceNameToPath, required this.orderedEvidencePaths});

  final Map<String, String> evidenceNameToPath;
  final List<String> orderedEvidencePaths;

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
      // 未匹配到文件名时，回退为可选的明文占位，避免渲染空白
      return Text('[evidence: ' + name + ']', style: preferredStyle);
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Builder(
        builder: (context) {
          final BorderRadius br = BorderRadius.circular(AppTheme.radiusLg);
          final String path = resolvedPath!;
          final Widget thumbImage = ScreenshotImageWidget(
            file: File(path),
            privacyMode: true,
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
                  final List<String> galleryPaths = (orderedEvidencePaths.isNotEmpty)
                      ? orderedEvidencePaths
                      : <String>[path];
                  final List<String> paths = <String>{...galleryPaths}.toList();
                  if (!paths.contains(path)) paths.insert(0, path);
                  final int initialIndex = paths.indexOf(path);
                  try { await FlutterLogger.info('UI.Chat-ImageTap: navigate viewer (reveal) count='+paths.length.toString()); } catch (_) {}
                  final nav = NavigationService.instance.navigatorKey.currentState;
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
                  final List<String> galleryPaths = (orderedEvidencePaths.isNotEmpty)
                      ? orderedEvidencePaths
                      : <String>[path];
                  final List<String> paths = <String>{...galleryPaths}.toList();
                  if (!paths.contains(path)) paths.insert(0, path);
                  final int initialIndex = paths.indexOf(path);
                  try { await FlutterLogger.info('UI.Chat-ImageTap: navigate viewer (tap) count='+paths.length.toString()); } catch (_) {}
                  final nav = NavigationService.instance.navigatorKey.currentState;
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
          return Container(
            decoration: BoxDecoration(
              border: Border.all(
                color: Theme.of(context).colorScheme.outline.withOpacity(0.12),
                width: 1,
              ),
              borderRadius: br,
            ),
            child: Stack(
              children: [
                thumbImage,
                TimelineJumpOverlay(filePath: path),
              ],
            ),
          );
        },
      ),
    );
  }
}

/// 提供给页面使用的统一配置对象。
class MarkdownMathConfig {
  MarkdownMathConfig({
    this.inlineTextStyle,
    this.blockTextStyle,
    Map<String, String>? evidenceNameToPath,
    List<String>? orderedEvidencePaths,
  }) : _evidenceNameToPath = evidenceNameToPath ?? const <String, String>{},
       _orderedEvidencePaths = orderedEvidencePaths ?? const <String>[];

  final TextStyle? inlineTextStyle;
  final TextStyle? blockTextStyle;
  final Map<String, String> _evidenceNameToPath;
  final List<String> _orderedEvidencePaths;

  Map<String, MarkdownElementBuilder> get builders => {
        'math-inline': _MathBuilder(inlineTextStyle: inlineTextStyle),
        'math-block': _MathBuilder(blockTextStyle: blockTextStyle),
        'evidence': _EvidenceBuilder(
          evidenceNameToPath: _evidenceNameToPath,
          orderedEvidencePaths: _orderedEvidencePaths,
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