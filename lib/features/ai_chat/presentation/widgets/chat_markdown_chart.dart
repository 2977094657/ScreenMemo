import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:graphic/graphic.dart';
import 'package:markdown/markdown.dart' as md;

const String kChartV1FenceLanguage = 'chart-v1';
const String kChartBlockTag = 'chart-block';
const bool _kChartDebugUi = false;
const double _kPieCoordPadding = 10;
const double _kPieDimFill = 0.92;

String buildChartV1FenceMarkdown(String rawJson) {
  final String normalized = rawJson.replaceAll('\r\n', '\n').trimRight();
  return '```$kChartV1FenceLanguage\n$normalized\n```';
}

String? extractChartV1FencePayload(String text) {
  final String normalized = text.replaceAll('\r\n', '\n').trim();
  final Match? match = RegExp(
    '^```$kChartV1FenceLanguage[ \\t]*\\n([\\s\\S]*?)\\n```[ \\t]*\$',
  ).firstMatch(normalized);
  return match == null ? null : (match.group(1) ?? '').trim();
}

String encodeChartBlockPayload(String rawJson) {
  return base64UrlEncode(utf8.encode(rawJson));
}

String? decodeChartBlockPayload(String encoded) {
  try {
    return utf8.decode(base64Url.decode(encoded.trim()));
  } catch (_) {
    return null;
  }
}

class ChartBlockSyntax extends md.BlockSyntax {
  const ChartBlockSyntax();

  static final RegExp _openingPattern = RegExp(
    r'^[ ]{0,3}(```+|~~~+)[ \t]*chart-v1(?:[ \t].*)?$',
    caseSensitive: false,
  );
  static final RegExp _closingPattern = RegExp(r'^[ ]{0,3}(```+|~~~+)[ \t]*$');

  @override
  RegExp get pattern => _openingPattern;

  @override
  bool canParse(md.BlockParser parser) {
    final Match? opening = _openingPattern.firstMatch(parser.current.content);
    if (opening == null) return false;
    final String marker = opening.group(1)!;
    for (int i = 1; ; i++) {
      final md.Line? next = parser.peek(i);
      if (next == null) return false;
      final Match? closing = _closingPattern.firstMatch(next.content);
      if (closing == null) continue;
      final String closingMarker = closing.group(1)!;
      if (closingMarker[0] == marker[0] &&
          closingMarker.length >= marker.length) {
        return true;
      }
    }
  }

  @override
  md.Node parse(md.BlockParser parser) {
    final Match opening = _openingPattern.firstMatch(parser.current.content)!;
    final String marker = opening.group(1)!;
    parser.advance();

    final List<String> lines = <String>[];
    while (!parser.isDone) {
      final Match? closing = _closingPattern.firstMatch(parser.current.content);
      if (closing != null) {
        final String closingMarker = closing.group(1)!;
        if (closingMarker[0] == marker[0] &&
            closingMarker.length >= marker.length) {
          parser.advance();
          break;
        }
      }
      lines.add(parser.current.content);
      parser.advance();
    }

    return md.Element.text(
      kChartBlockTag,
      encodeChartBlockPayload(lines.join('\n').trim()),
    );
  }
}

enum ChatChartType { line, bar, area, pie, scatter }

ChatChartType? _parseChartType(String raw) {
  switch (raw.trim().toLowerCase()) {
    case 'line':
      return ChatChartType.line;
    case 'bar':
      return ChatChartType.bar;
    case 'area':
      return ChatChartType.area;
    case 'pie':
      return ChatChartType.pie;
    case 'scatter':
      return ChatChartType.scatter;
    default:
      return null;
  }
}

class ChatChartSeriesV1 {
  const ChatChartSeriesV1({required this.data, this.name});

  final String? name;
  final List<double> data;
}

class ChatChartAxisV1 {
  const ChatChartAxisV1({this.label});

  final String? label;
}

class ChatChartSpecV1 {
  const ChatChartSpecV1({
    required this.type,
    required this.series,
    this.title,
    this.x,
    this.y,
    this.colors,
    this.note,
  });

  final ChatChartType type;
  final String? title;
  final List<String>? x;
  final List<ChatChartSeriesV1> series;
  final ChatChartAxisV1? y;
  final List<String>? colors;
  final String? note;

  bool get isPie => type == ChatChartType.pie;

  static ChatChartSpecV1? tryParseJson(String rawJson) {
    final Object? decoded;
    try {
      decoded = jsonDecode(rawJson);
    } catch (_) {
      return null;
    }
    if (decoded is! Map) return null;
    final Map<String, dynamic> map = Map<String, dynamic>.from(decoded);

    final ChatChartType? type = _parseChartType((map['type'] as String?) ?? '');
    if (type == null) return null;

    final dynamic rawSeries = map['series'];
    if (rawSeries is! List || rawSeries.isEmpty) return null;

    final List<ChatChartSeriesV1> series = <ChatChartSeriesV1>[];
    for (final dynamic item in rawSeries) {
      if (item is! Map) return null;
      final Map<String, dynamic> seriesMap = Map<String, dynamic>.from(item);
      final dynamic rawData = seriesMap['data'];
      if (rawData is! List || rawData.isEmpty) return null;
      final List<double> values = <double>[];
      for (final dynamic value in rawData) {
        if (value is num) {
          values.add(value.toDouble());
          continue;
        }
        if (value is String) {
          final double? parsed = double.tryParse(value.trim());
          if (parsed == null) return null;
          values.add(parsed);
          continue;
        }
        return null;
      }
      final String? name = (seriesMap['name'] as String?)?.trim();
      series.add(
        ChatChartSeriesV1(
          name: (name == null || name.isEmpty) ? null : name,
          data: values,
        ),
      );
    }

    List<String>? x;
    if (map.containsKey('x')) {
      final dynamic rawX = map['x'];
      if (rawX is! List || rawX.isEmpty) return null;
      final List<String> labels = rawX
          .map((dynamic item) => item?.toString().trim() ?? '')
          .where((String item) => item.isNotEmpty)
          .toList(growable: false);
      if (labels.length != rawX.length) return null;
      x = labels;
    }

    ChatChartAxisV1? y;
    if (map['y'] is Map) {
      final Map<String, dynamic> yMap = Map<String, dynamic>.from(
        map['y'] as Map,
      );
      final String? label = (yMap['label'] as String?)?.trim();
      y = ChatChartAxisV1(
        label: (label == null || label.isEmpty) ? null : label,
      );
    }

    List<String>? colors;
    if (map['colors'] is List) {
      final List<dynamic> rawColors = List<dynamic>.from(map['colors'] as List);
      final List<String> parsed = rawColors
          .map((dynamic item) => item?.toString().trim() ?? '')
          .where((String item) => item.isNotEmpty)
          .toList(growable: false);
      if (parsed.isNotEmpty) colors = parsed;
    }

    final ChatChartSpecV1 spec = ChatChartSpecV1(
      type: type,
      title: (map['title'] as String?)?.trim(),
      x: x,
      series: series,
      y: y,
      colors: colors,
      note: (map['note'] as String?)?.trim(),
    );
    return spec._isValid() ? spec : null;
  }

  bool _isValid() {
    if (series.isEmpty) return false;
    if (isPie) {
      if (series.length != 1) return false;
      if (x == null || x!.isEmpty) return false;
      return x!.length == series.first.data.length;
    }

    if (x == null || x!.isEmpty) return false;
    for (final ChatChartSeriesV1 item in series) {
      if (item.data.length != x!.length) return false;
    }
    return true;
  }
}

class ChatMarkdownChartBlock extends StatelessWidget {
  const ChatMarkdownChartBlock({
    super.key,
    required this.rawJson,
    required this.spec,
  });

  final String rawJson;
  final ChatChartSpecV1? spec;

  @override
  Widget build(BuildContext context) {
    if (spec == null) {
      return _ChartCodeFallback(rawJson: rawJson);
    }
    return _ChartCard(spec: spec!, rawJson: rawJson);
  }
}

class _ChartCard extends StatelessWidget {
  const _ChartCard({required this.spec, required this.rawJson});

  final ChatChartSpecV1 spec;
  final String rawJson;

  static const double _kPlotHeight = 220;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme colorScheme = theme.colorScheme;
    final List<Color> palette = _resolvePalette(theme, spec);
    final String? title = _clean(spec.title);
    final String? note = _clean(spec.note);
    final String? yLabel = _clean(spec.y?.label);

    return Semantics(
      container: true,
      label: title == null ? 'chart' : 'chart: $title',
      child: Container(
        width: double.infinity,
        margin: const EdgeInsets.symmetric(vertical: 6),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: colorScheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: colorScheme.outlineVariant.withValues(alpha: 0.7),
            width: 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (title != null || yLabel != null)
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (title != null)
                    Expanded(
                      child: Text(
                        title,
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: colorScheme.onSurface,
                        ),
                      ),
                    ),
                  if (yLabel != null)
                    Container(
                      margin: const EdgeInsets.only(left: 8),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: colorScheme.secondaryContainer,
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        yLabel,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: colorScheme.onSecondaryContainer,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                ],
              ),
            if (title != null || yLabel != null) const SizedBox(height: 10),
            _ChartRuntimeProbe(
              plotHeight: _kPlotHeight,
              spec: spec,
              rawJson: rawJson,
              palette: palette,
              buildChart: (BuildContext context, GlobalKey chartKey) =>
                  _buildChart(context, palette, chartKey: chartKey),
            ),
            if (spec.series.length > 1) ...[
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: List<Widget>.generate(spec.series.length, (
                  int index,
                ) {
                  final String label = _seriesName(spec, index);
                  return _LegendChip(
                    color: palette[index % palette.length],
                    label: label,
                  );
                }),
              ),
            ],
            if (note != null) ...[
              const SizedBox(height: 10),
              Text(
                note,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                  height: 1.35,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildChart(
    BuildContext context,
    List<Color> palette, {
    required GlobalKey chartKey,
  }) {
    switch (spec.type) {
      case ChatChartType.line:
        return _buildRectChart(
          context,
          palette,
          chartKey: chartKey,
          lineOnly: true,
          areaOnly: false,
          pointOnly: false,
          barOnly: false,
        );
      case ChatChartType.bar:
        return _buildRectChart(
          context,
          palette,
          chartKey: chartKey,
          lineOnly: false,
          areaOnly: false,
          pointOnly: false,
          barOnly: true,
        );
      case ChatChartType.area:
        return _buildRectChart(
          context,
          palette,
          chartKey: chartKey,
          lineOnly: false,
          areaOnly: true,
          pointOnly: false,
          barOnly: false,
        );
      case ChatChartType.scatter:
        return _buildRectChart(
          context,
          palette,
          chartKey: chartKey,
          lineOnly: false,
          areaOnly: false,
          pointOnly: true,
          barOnly: false,
        );
      case ChatChartType.pie:
        return _buildPieChart(palette, chartKey: chartKey);
    }
  }

  Widget _buildRectChart(
    BuildContext context,
    List<Color> palette, {
    required GlobalKey chartKey,
    required bool lineOnly,
    required bool areaOnly,
    required bool pointOnly,
    required bool barOnly,
  }) {
    final List<Map<String, Object>> data = <Map<String, Object>>[];
    final List<String> x = spec.x ?? const <String>[];
    for (int seriesIndex = 0; seriesIndex < spec.series.length; seriesIndex++) {
      final ChatChartSeriesV1 series = spec.series[seriesIndex];
      final String name = _seriesName(spec, seriesIndex);
      for (int i = 0; i < x.length; i++) {
        data.add(<String, Object>{
          'x': x[i],
          'series': name,
          'value': series.data[i],
        });
      }
    }

    final double minValue = data
        .map((Map<String, Object> item) => (item['value'] as double))
        .reduce(math.min);
    final double minScale = barOnly ? math.min(0, minValue) : minValue;
    final int tickCount = math.min(math.max(x.length, 2), 6);
    final bool multiSeries = spec.series.length > 1;

    final List<Mark> marks = <Mark>[];
    if (barOnly) {
      marks.add(
        IntervalMark(
          position: Varset('x') * Varset('value') / Varset('series'),
          color: multiSeries
              ? ColorEncode(
                  variable: 'series',
                  values: palette,
                  updaters: _tapColorUpdaters(),
                )
              : ColorEncode(
                  value: palette.first,
                  updaters: _tapColorUpdaters(),
                ),
          modifiers: multiSeries ? <Modifier>[DodgeModifier()] : null,
          size: SizeEncode(value: 14, updaters: _tapSizeUpdaters(1.08)),
        ),
      );
    } else if (pointOnly) {
      marks.add(
        PointMark(
          position: Varset('x') * Varset('value') / Varset('series'),
          color: multiSeries
              ? ColorEncode(
                  variable: 'series',
                  values: palette,
                  updaters: _tapColorUpdaters(),
                )
              : ColorEncode(
                  value: palette.first,
                  updaters: _tapColorUpdaters(),
                ),
          shape: ShapeEncode(value: CircleShape()),
          size: SizeEncode(value: 6, updaters: _tapSizeUpdaters(1.35)),
        ),
      );
    } else if (areaOnly) {
      marks.add(
        AreaMark(
          position: Varset('x') * Varset('value') / Varset('series'),
          shape: ShapeEncode(value: BasicAreaShape(smooth: true)),
          color: multiSeries
              ? ColorEncode(
                  variable: 'series',
                  values: palette
                      .map((Color color) => color.withValues(alpha: 0.22))
                      .toList(growable: false),
                  updaters: _tapColorUpdaters(unselectedAlpha: 0.10),
                )
              : ColorEncode(
                  value: palette.first.withValues(alpha: 0.24),
                  updaters: _tapColorUpdaters(unselectedAlpha: 0.10),
                ),
        ),
      );
      marks.add(
        LineMark(
          position: Varset('x') * Varset('value') / Varset('series'),
          shape: ShapeEncode(value: BasicLineShape(smooth: true)),
          color: multiSeries
              ? ColorEncode(
                  variable: 'series',
                  values: palette,
                  updaters: _tapColorUpdaters(),
                )
              : ColorEncode(
                  value: palette.first,
                  updaters: _tapColorUpdaters(),
                ),
          size: SizeEncode(value: 2, updaters: _tapSizeUpdaters(1.35)),
        ),
      );
    } else if (lineOnly) {
      marks.add(
        LineMark(
          position: Varset('x') * Varset('value') / Varset('series'),
          shape: ShapeEncode(value: BasicLineShape(smooth: true)),
          color: multiSeries
              ? ColorEncode(
                  variable: 'series',
                  values: palette,
                  updaters: _tapColorUpdaters(),
                )
              : ColorEncode(
                  value: palette.first,
                  updaters: _tapColorUpdaters(),
                ),
          size: SizeEncode(value: 2, updaters: _tapSizeUpdaters(1.35)),
        ),
      );
    }

    return Chart<Map<String, Object>>(
      key: chartKey,
      data: data,
      variables: <String, Variable<Map<String, Object>, dynamic>>{
        'x': Variable<Map<String, Object>, String>(
          accessor: (Map<String, Object> map) => map['x']! as String,
          scale: OrdinalScale(tickCount: tickCount, inflate: !barOnly),
        ),
        'series': Variable<Map<String, Object>, String>(
          accessor: (Map<String, Object> map) => map['series']! as String,
        ),
        'value': Variable<Map<String, Object>, num>(
          accessor: (Map<String, Object> map) => map['value']! as num,
          scale: LinearScale(min: minScale, marginMax: 0.12, tickCount: 4),
        ),
      },
      marks: marks,
      axes: <AxisGuide>[Defaults.horizontalAxis, Defaults.verticalAxis],
      selections: <String, Selection>{'tap': PointSelection(dim: Dim.x)},
      tooltip: TooltipGuide(
        selections: const <String>{'tap'},
        followPointer: const <bool>[false, true],
        align: Alignment.topLeft,
        variables: multiSeries
            ? const <String>['series', 'value']
            : const <String>['value'],
        multiTuples: multiSeries,
      ),
      rebuild: true,
      changeData: true,
    );
  }

  Widget _buildPieChart(List<Color> palette, {required GlobalKey chartKey}) {
    return _InteractivePieChart(
      chartKey: chartKey,
      spec: spec,
      palette: palette,
    );
  }
}

class _InteractivePieChart extends StatefulWidget {
  const _InteractivePieChart({
    required this.chartKey,
    required this.spec,
    required this.palette,
  });

  final GlobalKey chartKey;
  final ChatChartSpecV1 spec;
  final List<Color> palette;

  @override
  State<_InteractivePieChart> createState() => _InteractivePieChartState();
}

class _InteractivePieChartState extends State<_InteractivePieChart> {
  int? _selectedIndex;
  Offset? _lastTapPosition;

  @override
  void dispose() => super.dispose();

  List<Map<String, Object>> get _data {
    final ChatChartSeriesV1 series = widget.spec.series.first;
    final List<String> labels = widget.spec.x ?? const <String>[];
    return List<Map<String, Object>>.generate(labels.length, (int index) {
      return <String, Object>{
        'index': index,
        'slice': labels[index],
        'value': series.data[index],
      };
    }, growable: false);
  }

  void _selectIndex(int? index, {Offset? tapPosition}) {
    _selectedIndex = index;
    _lastTapPosition = tapPosition;
    if (mounted) {
      setState(() {});
    }
  }

  int? _hitTestSlice(Offset localPosition, Size size) {
    final _PieGeometry geometry = _PieGeometry.fromSize(size);
    final Offset delta = localPosition - geometry.center;
    final double radius = delta.distance;
    if (radius > geometry.outerRadius) return null;

    double angle = math.atan2(delta.dy, delta.dx) - geometry.startAngle;
    final double full = math.pi * 2;
    while (angle < 0) {
      angle += full;
    }
    while (angle >= full) {
      angle -= full;
    }

    final List<double> values = widget.spec.series.first.data;
    final double total = values.fold<double>(0, (double a, double b) => a + b);
    if (total <= 0) return null;

    double acc = 0;
    for (int index = 0; index < values.length; index++) {
      final double sweep = (values[index] / total) * full;
      final double next = acc + sweep;
      if (angle >= acc && (angle < next || index == values.length - 1)) {
        return index;
      }
      acc = next;
    }
    return null;
  }

  Offset _tooltipAnchor(Size size, int index) {
    if (_lastTapPosition != null) {
      return Offset(
        _lastTapPosition!.dx.clamp(12, math.max(12, size.width - 12)),
        _lastTapPosition!.dy.clamp(12, math.max(12, size.height - 12)),
      );
    }
    final _PieGeometry geometry = _PieGeometry.fromSize(size);
    final List<double> values = widget.spec.series.first.data;
    final double total = values.fold<double>(0, (double a, double b) => a + b);
    if (total <= 0) return geometry.center;

    double acc = 0;
    for (int i = 0; i < index; i++) {
      acc += values[i];
    }
    final double sweep = values[index] / total * math.pi * 2;
    final double midAngle =
        geometry.startAngle + (acc / total * math.pi * 2) + sweep / 2;
    return Offset(
      geometry.center.dx + math.cos(midAngle) * geometry.outerRadius * 0.58,
      geometry.center.dy + math.sin(midAngle) * geometry.outerRadius * 0.58,
    );
  }

  Widget _buildTooltip(BuildContext context, Size size, int index) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme colorScheme = theme.colorScheme;
    final String label = widget.spec.x?[index] ?? 'Slice ${index + 1}';
    final double value = widget.spec.series.first.data[index];
    final Offset anchor = _tooltipAnchor(size, index);
    final double bubbleWidth = 132;
    final double bubbleHeight = 52;
    final double left = (anchor.dx - bubbleWidth / 2).clamp(
      8,
      math.max(8, size.width - bubbleWidth - 8),
    );
    final double top = (anchor.dy - bubbleHeight - 20).clamp(
      8,
      math.max(8, size.height - bubbleHeight - 8),
    );

    return Positioned(
      left: left,
      top: top,
      child: IgnorePointer(
        child: Material(
          color: Colors.transparent,
          child: Container(
            width: bubbleWidth,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: colorScheme.inverseSurface.withValues(alpha: 0.96),
              borderRadius: BorderRadius.circular(10),
              boxShadow: const <BoxShadow>[
                BoxShadow(
                  color: Color(0x22000000),
                  blurRadius: 12,
                  offset: Offset(0, 4),
                ),
              ],
            ),
            child: DefaultTextStyle(
              style: theme.textTheme.bodySmall!.copyWith(
                color: colorScheme.onInverseSurface,
                height: 1.25,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: colorScheme.onInverseSurface,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(_formatPercent(value)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final Size size = Size(
          constraints.maxWidth.isFinite ? constraints.maxWidth : 0,
          constraints.maxHeight.isFinite ? constraints.maxHeight : 0,
        );
        return Listener(
          behavior: HitTestBehavior.opaque,
          onPointerDown: (PointerDownEvent event) {
            final Offset localPosition = event.localPosition;
            final int? hit = _hitTestSlice(localPosition, size);
            _selectIndex(hit, tapPosition: localPosition);
          },
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned.fill(
                child: Chart<Map<String, Object>>(
                  key: widget.chartKey,
                  data: _data,
                  variables: <String, Variable<Map<String, Object>, dynamic>>{
                    'index': Variable<Map<String, Object>, num>(
                      accessor: (Map<String, Object> map) =>
                          map['index']! as num,
                    ),
                    'slice': Variable<Map<String, Object>, String>(
                      accessor: (Map<String, Object> map) =>
                          map['slice']! as String,
                    ),
                    'value': Variable<Map<String, Object>, num>(
                      accessor: (Map<String, Object> map) =>
                          map['value']! as num,
                    ),
                  },
                  transforms: <VariableTransform>[
                    Proportion(variable: 'value', as: 'percent'),
                  ],
                  marks: <Mark>[
                    IntervalMark(
                      position: Varset('percent') / Varset('slice'),
                      color: ColorEncode(
                        encoder: (Tuple tuple) {
                          final int index = (tuple['index']! as num).toInt();
                          final Color baseColor =
                              widget.palette[index % widget.palette.length];
                          final bool isSelected =
                              _selectedIndex == null || _selectedIndex == index;
                          if (isSelected) return baseColor;
                          return Color.alphaBlend(
                            Colors.grey.withValues(alpha: 0.72),
                            baseColor.withValues(alpha: 0.42),
                          );
                        },
                      ),
                      modifiers: <Modifier>[StackModifier()],
                      elevation: ElevationEncode(
                        encoder: (Tuple tuple) {
                          final int index = (tuple['index']! as num).toInt();
                          return (_selectedIndex == index) ? 6.0 : 0.0;
                        },
                      ),
                    ),
                  ],
                  coord: PolarCoord(
                    transposed: true,
                    dimCount: 1,
                    dimFill: _kPieDimFill,
                  ),
                  rebuild: true,
                  changeData: true,
                ),
              ),
              if (_selectedIndex != null)
                _buildTooltip(context, size, _selectedIndex!),
            ],
          ),
        );
      },
    );
  }
}

class _PieGeometry {
  const _PieGeometry({
    required this.center,
    required this.outerRadius,
    required this.startAngle,
  });

  final Offset center;
  final double outerRadius;
  final double startAngle;

  factory _PieGeometry.fromSize(Size size) {
    final double regionWidth = math.max(0, size.width - _kPieCoordPadding * 2);
    final double regionHeight = math.max(
      0,
      size.height - _kPieCoordPadding * 2,
    );
    final double regionRadius = math.min(regionWidth, regionHeight) / 2;
    return _PieGeometry(
      center: Offset(size.width / 2, size.height / 2),
      outerRadius: regionRadius * _kPieDimFill,
      startAngle: -math.pi / 2,
    );
  }
}

typedef _ChartWidgetBuilder =
    Widget Function(BuildContext context, GlobalKey chartKey);

class _ChartRuntimeProbe extends StatefulWidget {
  const _ChartRuntimeProbe({
    required this.plotHeight,
    required this.spec,
    required this.rawJson,
    required this.palette,
    required this.buildChart,
  });

  final double plotHeight;
  final ChatChartSpecV1 spec;
  final String rawJson;
  final List<Color> palette;
  final _ChartWidgetBuilder buildChart;

  @override
  State<_ChartRuntimeProbe> createState() => _ChartRuntimeProbeState();
}

class _ChartRuntimeProbeState extends State<_ChartRuntimeProbe> {
  final GlobalKey _chartKey = GlobalKey();
  final GlobalKey _plotBoxKey = GlobalKey();

  BoxConstraints? _lastConstraints;
  String _debugText = 'chart-debug: pending first frame';
  bool _snapshotScheduled = false;

  @override
  void initState() {
    super.initState();
    _scheduleSnapshot();
  }

  @override
  void didUpdateWidget(covariant _ChartRuntimeProbe oldWidget) {
    super.didUpdateWidget(oldWidget);
    _scheduleSnapshot();
  }

  void _scheduleSnapshot() {
    if (_snapshotScheduled) return;
    _snapshotScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _snapshotScheduled = false;
      _captureSnapshot();
    });
  }

  void _captureSnapshot() {
    if (!mounted) return;
    final RenderBox? plotBox =
        _plotBoxKey.currentContext?.findRenderObject() as RenderBox?;
    final Size? plotSize = (plotBox != null && plotBox.hasSize)
        ? plotBox.size
        : null;
    final RenderBox? chartBox =
        _chartKey.currentContext?.findRenderObject() as RenderBox?;
    final Size? chartSize = (chartBox != null && chartBox.hasSize)
        ? chartBox.size
        : null;
    final bool chartMounted = _chartKey.currentContext != null;

    final List<String> lines = <String>[
      'chart-debug type=${widget.spec.type.name} impl=${_chartImpl(widget.spec.type)}',
      'spec x=${widget.spec.x?.length ?? 0} series=${widget.spec.series.length} points=${_pointCount(widget.spec)} palette=${widget.palette.length} raw=${utf8.encode(widget.rawJson).length}B',
      'values sum=${_formatDouble(_sumValues(widget.spec))} min=${_formatDouble(_minValue(widget.spec))} max=${_formatDouble(_maxValue(widget.spec))}',
      'layout constraints=${_formatConstraints(_lastConstraints)} plot=${_formatSize(plotSize)} chart=${_formatSize(chartSize)} mounted=${chartMounted ? "yes" : "no"}',
      if (widget.spec.isPie)
        'pie labels=${_previewPairs(widget.spec, maxPairs: 4)}',
    ];
    final String next = lines.join('\n');
    if (next != _debugText) {
      setState(() {
        _debugText = next;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    _scheduleSnapshot();
    final ThemeData theme = Theme.of(context);
    final ColorScheme colorScheme = theme.colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        LayoutBuilder(
          builder: (BuildContext context, BoxConstraints constraints) {
            _lastConstraints = constraints;
            _scheduleSnapshot();
            return SizedBox(
              key: _plotBoxKey,
              height: widget.plotHeight,
              width: double.infinity,
              child: RepaintBoundary(
                child: widget.buildChart(context, _chartKey),
              ),
            );
          },
        ),
        if (_kChartDebugUi) ...[
          const SizedBox(height: 8),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerHighest.withValues(
                alpha: 0.75,
              ),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: colorScheme.outlineVariant.withValues(alpha: 0.7),
                width: 1,
              ),
            ),
            child: Text(
              _debugText,
              style: theme.textTheme.bodySmall?.copyWith(
                fontFamily: 'monospace',
                fontSize: 11,
                height: 1.35,
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _LegendChip extends StatelessWidget {
  const _LegendChip({required this.color, required this.label});

  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme colorScheme = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style: theme.textTheme.labelSmall?.copyWith(
              color: colorScheme.onSurface,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _ChartCodeFallback extends StatelessWidget {
  const _ChartCodeFallback({required this.rawJson});

  final String rawJson;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme colorScheme = theme.colorScheme;
    final TextStyle style =
        theme.textTheme.bodySmall?.copyWith(
          fontFamily: 'monospace',
          color: colorScheme.onSurface,
          height: 1.4,
        ) ??
        TextStyle(
          fontFamily: 'monospace',
          color: colorScheme.onSurface,
          fontSize: 12,
          height: 1.4,
        );
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.symmetric(vertical: 6),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.65),
          width: 1,
        ),
      ),
      child: SelectableText(buildChartV1FenceMarkdown(rawJson), style: style),
    );
  }
}

List<Color> _resolvePalette(ThemeData theme, ChatChartSpecV1 spec) {
  final List<Color> fallback = <Color>[
    theme.colorScheme.primary,
    theme.colorScheme.tertiary,
    theme.colorScheme.secondary,
    Colors.orange,
    Colors.teal,
    Colors.pink,
    Colors.indigo,
    Colors.green,
  ];
  final List<Color> parsed = (spec.colors ?? const <String>[])
      .map(_tryParseColor)
      .whereType<Color>()
      .toList(growable: false);
  if (parsed.isNotEmpty) return parsed;
  return fallback;
}

Color? _tryParseColor(String raw) {
  final String hex = raw.trim().replaceFirst('#', '');
  if (hex.length != 6 && hex.length != 8) return null;
  final int? value = int.tryParse(hex, radix: 16);
  if (value == null) return null;
  return Color(hex.length == 6 ? (0xFF000000 | value) : value);
}

String _seriesName(ChatChartSpecV1 spec, int index) {
  final String? raw = spec.series[index].name?.trim();
  if (raw != null && raw.isNotEmpty) return raw;
  return 'Series ${index + 1}';
}

Map<String, Map<bool, SelectionUpdater<Color>>> _tapColorUpdaters({
  double unselectedAlpha = 0.22,
}) {
  return <String, Map<bool, SelectionUpdater<Color>>>{
    'tap': <bool, SelectionUpdater<Color>>{
      true: (Color color) => color,
      false: (Color color) => color.withValues(alpha: unselectedAlpha),
    },
  };
}

Map<String, Map<bool, SelectionUpdater<double>>> _tapSizeUpdaters(
  double factor,
) {
  return <String, Map<bool, SelectionUpdater<double>>>{
    'tap': <bool, SelectionUpdater<double>>{
      true: (double value) => value * factor,
    },
  };
}

String _chartImpl(ChatChartType type) {
  switch (type) {
    case ChatChartType.line:
      return 'line-mark';
    case ChatChartType.bar:
      return 'interval-mark';
    case ChatChartType.area:
      return 'area+line-mark';
    case ChatChartType.pie:
      return 'interval+proportion+polar';
    case ChatChartType.scatter:
      return 'point-mark';
  }
}

int _pointCount(ChatChartSpecV1 spec) {
  int total = 0;
  for (final ChatChartSeriesV1 series in spec.series) {
    total += series.data.length;
  }
  return total;
}

double _sumValues(ChatChartSpecV1 spec) {
  double sum = 0;
  for (final ChatChartSeriesV1 series in spec.series) {
    for (final double value in series.data) {
      sum += value;
    }
  }
  return sum;
}

double _minValue(ChatChartSpecV1 spec) {
  double? minValue;
  for (final ChatChartSeriesV1 series in spec.series) {
    for (final double value in series.data) {
      minValue = (minValue == null) ? value : math.min(minValue, value);
    }
  }
  return minValue ?? 0;
}

double _maxValue(ChatChartSpecV1 spec) {
  double? maxValue;
  for (final ChatChartSeriesV1 series in spec.series) {
    for (final double value in series.data) {
      maxValue = (maxValue == null) ? value : math.max(maxValue, value);
    }
  }
  return maxValue ?? 0;
}

String _formatDouble(double value) {
  if (!value.isFinite) return value.toString();
  return value.toStringAsFixed(value.truncateToDouble() == value ? 0 : 2);
}

String _formatPercent(double value) => '${_formatDouble(value)}%';

String _formatSize(Size? size) {
  if (size == null) return 'null';
  return '${size.width.toStringAsFixed(1)}x${size.height.toStringAsFixed(1)}';
}

String _formatConstraints(BoxConstraints? constraints) {
  if (constraints == null) return 'null';
  String fmt(double value) => value.isFinite ? value.toStringAsFixed(1) : 'inf';
  return 'w=${fmt(constraints.minWidth)}..${fmt(constraints.maxWidth)} h=${fmt(constraints.minHeight)}..${fmt(constraints.maxHeight)}';
}

String _previewPairs(ChatChartSpecV1 spec, {int maxPairs = 4}) {
  if (!spec.isPie) return '-';
  final List<String> labels = spec.x ?? const <String>[];
  final List<double> values = spec.series.first.data;
  final int count = math.min(labels.length, values.length);
  if (count == 0) return '-';
  final List<String> pairs = <String>[];
  for (int index = 0; index < math.min(count, maxPairs); index++) {
    pairs.add('${labels[index]}:${_formatDouble(values[index])}');
  }
  if (count > maxPairs) pairs.add('...');
  return pairs.join(' | ');
}

String? _clean(String? value) {
  final String trimmed = (value ?? '').trim();
  return trimmed.isEmpty ? null : trimmed;
}
