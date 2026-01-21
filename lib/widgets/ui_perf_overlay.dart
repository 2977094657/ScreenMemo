import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/ui_perf_logger.dart';

class UiPerfOverlay extends StatelessWidget {
  const UiPerfOverlay({
    super.key,
    required this.logger,
    this.maxLines = 16,
    this.onClose,
    this.onClear,
  });

  final UiPerfLogger logger;
  final int maxLines;
  final VoidCallback? onClose;
  final VoidCallback? onClear;

  @override
  Widget build(BuildContext context) {
    final Color bg = Theme.of(
      context,
    ).colorScheme.surface.withValues(alpha: 0.92);
    final Color fg = Theme.of(context).colorScheme.onSurface;

    String buildCopyText() {
      final List<UiPerfEvent> events = logger.events.value;
      final String header = logger.scope.isEmpty
          ? 'Perf'
          : 'Perf · ${logger.scope}';
      if (events.isEmpty) return header;
      return '$header\n${events.map((e) => e.formatLine()).join('\n')}';
    }

    return Material(
      type: MaterialType.transparency,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 380, maxHeight: 260),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: Theme.of(
              context,
            ).colorScheme.outline.withValues(alpha: 0.25),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: DefaultTextStyle(
            style: Theme.of(context).textTheme.labelSmall!.copyWith(
              color: fg.withValues(alpha: 0.9),
              height: 1.25,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        logger.scope.isEmpty
                            ? 'Perf'
                            : 'Perf · ${logger.scope}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: fg.withValues(alpha: 0.95),
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Copy',
                      onPressed: () async {
                        final messenger = ScaffoldMessenger.maybeOf(context);
                        try {
                          await Clipboard.setData(
                            ClipboardData(text: buildCopyText()),
                          );
                          messenger?.clearSnackBars();
                          messenger?.showSnackBar(
                            const SnackBar(
                              content: Text('已复制'),
                              duration: Duration(milliseconds: 900),
                            ),
                          );
                        } catch (_) {}
                      },
                      visualDensity: VisualDensity.compact,
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints.tightFor(
                        width: 28,
                        height: 28,
                      ),
                      iconSize: 16,
                      icon: const Icon(Icons.copy_outlined),
                    ),
                    IconButton(
                      tooltip: 'Clear',
                      onPressed: onClear,
                      visualDensity: VisualDensity.compact,
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints.tightFor(
                        width: 28,
                        height: 28,
                      ),
                      iconSize: 16,
                      icon: const Icon(Icons.delete_outline),
                    ),
                    IconButton(
                      tooltip: 'Close',
                      onPressed: onClose,
                      visualDensity: VisualDensity.compact,
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints.tightFor(
                        width: 28,
                        height: 28,
                      ),
                      iconSize: 16,
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Flexible(
                  child: ValueListenableBuilder<List<UiPerfEvent>>(
                    valueListenable: logger.events,
                    builder: (context, events, _) {
                      final int start = events.length > maxLines
                          ? events.length - maxLines
                          : 0;
                      final Iterable<UiPerfEvent> slice = events.skip(start);
                      final String text = slice
                          .map((e) => e.formatLine())
                          .join('\n');
                      return SingleChildScrollView(
                        child: SelectableText(
                          text.isEmpty ? '(no events)' : text,
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
