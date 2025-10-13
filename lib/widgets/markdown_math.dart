import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_math_fork/flutter_math.dart' as fm;

/// 说明：
/// - 仅在 AI 对话页面使用，用于渲染 Markdown 中的 LaTeX 数学公式与 <think> 思考块。
/// - 复刻 rikkahub 的预处理：
///   * 将行内公式 \( ... \) 转为 <math-inline>...</math-inline>
///   * 将块级公式 \[ ... \] 转为 <math-block>...</math-block>
///   * 将 <think>...</think> 转为 Markdown 引用块（每行前置 > ）
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
      // 对非代码块内容：先做 <think> 转引用，再做 LaTeX 转标签，并跳过行内代码片段
      final s1 = _replaceThinkToBlockQuote(seg.text);
      buf.write(_replaceLatexToTagsSkippingInlineCode(s1));
    }
  }
  return buf.toString();
}

/// 将 <think>...</think> 的内容转为引用块（每行以 "> " 开头）。支持缺失闭合标签。
String _replaceThinkToBlockQuote(String text) {
  final thinkRegex = RegExp(r'<think>([\s\S]*?)(?:</think>|$)', multiLine: true);
  return text.replaceAllMapped(thinkRegex, (match) {
    final inner = (match.group(1) ?? '').replaceAll('\r\n', '\n');
    final lines = inner.split('\n').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
    if (lines.isEmpty) return '';
    return lines.map((l) => '> $l').join('\n');
  });
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

/// 提供给页面使用的统一配置对象。
class MarkdownMathConfig {
  MarkdownMathConfig({
    this.inlineTextStyle,
    this.blockTextStyle,
  });

  final TextStyle? inlineTextStyle;
  final TextStyle? blockTextStyle;

  Map<String, MarkdownElementBuilder> get builders => {
        'math-inline': _MathBuilder(inlineTextStyle: inlineTextStyle),
        'math-block': _MathBuilder(blockTextStyle: blockTextStyle),
      };
}

class _Seg {
  final bool isCode;
  final String text;
  _Seg(this.isCode, this.text);
}