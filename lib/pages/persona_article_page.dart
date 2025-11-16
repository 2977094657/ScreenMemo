import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';

import '../l10n/app_localizations.dart';
import '../services/persona_article_service.dart';
import '../services/ai_chat_service.dart';
import '../theme/app_theme.dart';

class PersonaArticlePage extends StatefulWidget {
  final PersonaArticleStyle style;

  const PersonaArticlePage({
    super.key,
    this.style = PersonaArticleStyle.narrative,
  });

  @override
  State<PersonaArticlePage> createState() => _PersonaArticlePageState();
}

class _PersonaArticlePageState extends State<PersonaArticlePage> {
  final PersonaArticleService _service = PersonaArticleService.instance;

  StreamSubscription<AIStreamEvent>? _subscription;
  String _article = '';
  bool _generating = false;
  String? _lastError;

  @override
  void initState() {
    super.initState();
    _loadCachedArticle();
    _startGeneration(clearExisting: false);
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  Future<void> _loadCachedArticle() async {
    final PersonaArticleCache? cache =
        await _service.loadCachedArticle(style: widget.style);
    if (!mounted || cache == null) return;
    if (cache.article.trim().isEmpty) return;
    setState(() {
      _article = cache.article;
    });
  }

  Future<void> _startGeneration({bool clearExisting = true}) async {
    await _subscription?.cancel();
    setState(() {
      if (clearExisting) {
        _article = '';
      }
      _generating = true;
      _lastError = null;
    });
    try {
      final Stream<AIStreamEvent> stream = _service.streamArticle(
        style: widget.style,
      );
      _subscription = stream.listen(
        (AIStreamEvent event) {
          if (!mounted) return;
          if (event.kind == 'content' && event.data.isNotEmpty) {
            setState(() {
              _article += event.data;
            });
          }
        },
        onError: (Object error) {
          if (!mounted) return;
          setState(() {
            _generating = false;
            _lastError = error.toString();
          });
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(AppLocalizations.of(context).articleGenerateFailed),
            ),
          );
        },
        onDone: () {
          if (!mounted) return;
          setState(() => _generating = false);
          final String finalArticle = _article.trim();
          if (finalArticle.isNotEmpty) {
            unawaited(
              _service.persistArticle(
                style: widget.style,
                article: finalArticle,
                localeOverride: Localizations.maybeLocaleOf(context),
              ),
            );
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  AppLocalizations.of(context).articleGenerateSuccess,
                ),
              ),
            );
          }
        },
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _generating = false;
        _lastError = e.toString();
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AppLocalizations.of(context).articleGenerateFailed),
        ),
      );
    }
  }

  Future<void> _copyArticle() async {
    final String text = _article.trim();
    if (text.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(AppLocalizations.of(context).articleCopySuccess)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations t = AppLocalizations.of(context);
    final ThemeData theme = Theme.of(context);
    final String normalizedArticle = _fixMarkdownLayout(_article);

    return Scaffold(
      appBar: AppBar(
        centerTitle: true,
        title: Text(t.articlePreviewTitle),
        toolbarHeight: 36,
        actions: [
          IconButton(
            tooltip: t.actionCopy,
            icon: const Icon(Icons.copy_all_outlined),
            onPressed: normalizedArticle.trim().isEmpty ? null : _copyArticle,
          ),
          IconButton(
            tooltip: _generating ? t.articleGenerating : t.actionRegenerate,
            icon: _generating
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.refresh_outlined),
            onPressed: _generating ? null : () => _startGeneration(),
          ),
        ],
      ),
      body: _buildBody(theme, normalizedArticle, t),
    );
  }

  Widget _buildBody(ThemeData theme, String markdown, AppLocalizations t) {
    if (_generating && markdown.isEmpty) {
      return const Center(child: CircularProgressIndicator(strokeWidth: 2));
    }

    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final double minHeight = constraints.maxHeight.isFinite
            ? constraints.maxHeight
            : 0;
        return SingleChildScrollView(
          padding: EdgeInsets.zero,
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: minHeight),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppTheme.spacing4,
                vertical: AppTheme.spacing3,
              ),
              child: markdown.trim().isEmpty
                  ? _buildPlaceholder(theme, t)
                  : _buildMarkdown(theme, markdown),
            ),
          ),
        );
      },
    );
  }

  Widget _buildMarkdown(ThemeData theme, String markdown) {
    final double baseSize = theme.textTheme.bodyMedium?.fontSize ?? 15;
    final TextStyle paragraph =
        (theme.textTheme.bodyLarge ??
                theme.textTheme.bodyMedium ??
                const TextStyle())
            .copyWith(fontSize: baseSize + 1, height: 1.75);
    final TextStyle heading =
        (theme.textTheme.titleMedium ?? theme.textTheme.bodyLarge ?? paragraph)
            .copyWith(
              fontSize: baseSize + 4,
              height: 1.45,
              fontWeight: FontWeight.w700,
            );

    String body = markdown.trimLeft();
    String? heroHeading;
    if (body.startsWith('### ')) {
      final int lineEnd = body.indexOf('\n');
      final String line = lineEnd == -1 ? body : body.substring(0, lineEnd);
      heroHeading = line.replaceFirst(RegExp(r'^###\s+'), '').trim();
      body = lineEnd == -1 ? '' : body.substring(lineEnd + 1).trimLeft();
    }

    final MarkdownStyleSheet sheet = MarkdownStyleSheet.fromTheme(theme)
        .copyWith(
          p: paragraph,
          h2: heading,
          h3: heading.copyWith(fontSize: heading.fontSize! - 1),
          h4: heading.copyWith(fontSize: heading.fontSize! - 2),
          blockSpacing: AppTheme.spacing2.toDouble(),
          listIndent: AppTheme.spacing3.toDouble(),
        );

    final List<Widget> children = <Widget>[];
    if (heroHeading != null && heroHeading.isNotEmpty) {
      children.add(
        Padding(
          padding: const EdgeInsets.only(bottom: AppTheme.spacing2),
          child: Text(
            heroHeading.replaceAll(RegExp(r'^\*+|\*+$'), ''),
            textAlign: TextAlign.center,
            style: heading.copyWith(fontSize: heading.fontSize! + 1),
          ),
        ),
      );
    }
    if (body.isNotEmpty) {
      children.add(MarkdownBody(data: body, styleSheet: sheet));
    }
    if (children.isEmpty) {
      return const SizedBox.shrink();
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: children,
    );
  }

  Widget _buildPlaceholder(ThemeData theme, AppLocalizations t) {
    final String hint = _lastError == null
        ? t.generatePersonaArticle
        : t.articleGenerateFailed;
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(
          Icons.article_outlined,
          size: 56,
          color: theme.colorScheme.onSurfaceVariant.withOpacity(0.6),
        ),
        const SizedBox(height: AppTheme.spacing2),
        Text(
          hint,
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyMedium,
        ),
        if (_lastError != null) ...[
          const SizedBox(height: AppTheme.spacing1),
          Text(
            _lastError!,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.error,
            ),
            textAlign: TextAlign.center,
          ),
        ],
        const SizedBox(height: AppTheme.spacing3),
        FilledButton.icon(
          onPressed: _generating ? null : () => _startGeneration(),
          icon: const Icon(Icons.refresh_outlined),
          label: Text(t.generatePersonaArticle),
        ),
      ],
    );
  }

  String _fixMarkdownLayout(String input) {
    if (input.trim().isEmpty) return input;
    final String pre = input
        .replaceAll('\\r\\n', '\n')
        .replaceAll('\\r', '\n')
        .replaceAll('\\n', '\n')
        .replaceAll('\r\n', '\n')
        .replaceAll('\r', '\n')
        .replaceAll('\\"', '"');

    final List<String> lines = pre.split('\n');
    final List<String> out = <String>[];
    bool lastWasBlank = true;
    final RegExp headingRe = RegExp(r'^\s{0,3}#{1,6}\s');
    final RegExp boldSubtitleRe = RegExp(r'^\s*\*\*[^*\n]+\*\*[:：]');
    final RegExp listStartRe = RegExp(r'^\s*[-*+]\s+');

    for (int i = 0; i < lines.length; i++) {
      final String line = lines[i];
      final String trimmed = line.trimRight();
      final bool isHeading = headingRe.hasMatch(trimmed);
      final bool isBoldSubtitle = boldSubtitleRe.hasMatch(trimmed);
      final bool isListStart = listStartRe.hasMatch(trimmed);

      if ((isHeading || isBoldSubtitle || isListStart) &&
          !lastWasBlank &&
          out.isNotEmpty &&
          out.last.trim().isNotEmpty) {
        out.add('');
        lastWasBlank = true;
      }

      out.add(line);

      if (isHeading) {
        final String? next = (i + 1 < lines.length) ? lines[i + 1] : null;
        if (next != null && next.trim().isNotEmpty) {
          out.add('');
          lastWasBlank = true;
          continue;
        }
      }

      lastWasBlank = line.trim().isEmpty;
    }

    final List<String> normalized = <String>[];
    for (final String line in out) {
      if (line.trim().isEmpty) {
        if (normalized.isEmpty || normalized.last.trim().isEmpty) {
          if (normalized.isEmpty) normalized.add('');
        } else {
          normalized.add('');
        }
      } else {
        normalized.add(line);
      }
    }
    return normalized.join('\n');
  }
}
