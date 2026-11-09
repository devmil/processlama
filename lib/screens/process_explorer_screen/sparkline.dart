part of '../process_explorer_screen.dart';

/// A row's recent CPU as a line with its latest sample marked.
class _Sparkline extends StatelessWidget {
  const _Sparkline({required this.samples, this.maxValue, this.color});

  static const Size size = Size(52, 14);
  static const double _endpointRadius = 1.6;

  final List<double> samples;
  final double? maxValue;

  /// Overrides the line and endpoint colour (on an `accent` selection).
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final app = ProcessLamaTheme.of(context);
    return CustomPaint(
      size: size,
      painter: _SparklinePainter(
        samples: samples,
        maxValue: maxValue,
        color: color ?? app.chartLine,
        endpointColor: color ?? context.meridian.colors.accent,
        endpointRadius: _endpointRadius,
      ),
    );
  }
}

class _SparklinePainter extends CustomPainter {
  const _SparklinePainter({
    required this.samples,
    required this.color,
    required this.endpointColor,
    required this.endpointRadius,
    this.maxValue,
  });

  final List<double> samples;
  final double? maxValue;
  final Color color;
  final Color endpointColor;
  final double endpointRadius;

  @override
  void paint(Canvas canvas, Size size) {
    if (samples.length < 2) {
      return;
    }

    final effectiveMax = (maxValue ?? _finiteMax(samples)).clamp(
      0.1,
      double.infinity,
    );
    final path = Path();
    final stepX = size.width / (samples.length - 1);

    // A gap (NaN) lifts the pen: the line never crosses an outage.
    var penDown = false;
    for (var index = 0; index < samples.length; index++) {
      final sample = samples[index];
      if (!sample.isFinite) {
        penDown = false;
        continue;
      }
      final x = index * stepX;
      final y = size.height * (1 - sample / effectiveMax);
      if (penDown) {
        path.lineTo(x, y);
      } else {
        path.moveTo(x, y);
        penDown = true;
      }
    }

    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..strokeCap = StrokeCap.round
        ..strokeWidth = 1
        ..style = PaintingStyle.stroke,
    );

    final last = samples.last;
    if (!last.isFinite) {
      return;
    }
    canvas.drawCircle(
      Offset(size.width, size.height * (1 - last / effectiveMax)),
      endpointRadius,
      Paint()..color = endpointColor,
    );
  }

  @override
  bool shouldRepaint(covariant _SparklinePainter oldDelegate) =>
      samples != oldDelegate.samples ||
      maxValue != oldDelegate.maxValue ||
      color != oldDelegate.color ||
      endpointColor != oldDelegate.endpointColor ||
      endpointRadius != oldDelegate.endpointRadius;
}

/// A history chart on a `pane-alt` inset: the metric's name and current
/// value over the chart, its scale on the left.
class _ChartCard extends StatelessWidget {
  const _ChartCard({
    required this.header,
    required this.scaleLabels,
    required this.chartHeight,
    required this.chart,
    super.key,
  });

  static const double _scaleWidth = 64;

  final Widget header;
  final List<String> scaleLabels;
  final double chartHeight;
  final Widget chart;

  @override
  Widget build(BuildContext context) {
    final meridian = context.meridian;
    final colors = meridian.colors;
    return Padding(
      padding: const EdgeInsets.only(bottom: MeridianSpace.space3),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: colors.paneAlt,
          borderRadius: BorderRadius.circular(meridian.radius.md),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: MeridianSpace.space5,
            vertical: MeridianSpace.space4,
          ),
          child: Column(
            children: [
              header,
              const SizedBox(height: MeridianSpace.space3),
              SizedBox(
                height: chartHeight,
                child: Row(
                  children: [
                    SizedBox(
                      width: _scaleWidth,
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          for (final label in scaleLabels)
                            FittedBox(
                              fit: BoxFit.scaleDown,
                              alignment: AlignmentDirectional.centerEnd,
                              child: Text(
                                label,
                                maxLines: 1,
                                style: MeridianTextStyles.numeric(
                                  meridian.text.codeSm.copyWith(
                                    color: colors.inkMuted,
                                    height: 1,
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(width: MeridianSpace.space3),
                    Expanded(child: SizedBox.expand(child: chart)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The name and current value(s) of a chart.
class _ChartHeader extends StatelessWidget {
  const _ChartHeader({required this.label, required this.value, this.detail});

  final String label;
  final String value;

  /// A second line (the direction legend of a diverging chart).
  final String? detail;

  @override
  Widget build(BuildContext context) {
    final meridian = context.meridian;
    final colors = meridian.colors;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: meridian.text.label,
              ),
              if (detail case final text?)
                Text(
                  text,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: meridian.text.caption.copyWith(color: colors.inkMuted),
                ),
            ],
          ),
        ),
        const SizedBox(width: MeridianSpace.space4),
        Text(
          value,
          maxLines: 1,
          style: MeridianTextStyles.numeric(
            meridian.text.code.copyWith(fontWeight: FontWeight.w600),
          ),
        ),
      ],
    );
  }
}

class _MetricGraphRow extends StatelessWidget {
  const _MetricGraphRow({
    required this.label,
    required this.value,
    required this.samples,
    required this.scaleMaxValue,
    required this.formatScaleValue,
  });

  static const double _chartHeight = 44;

  final String label;
  final String value;
  final List<double> samples;
  final double scaleMaxValue;
  final String Function(double value) formatScaleValue;

  @override
  Widget build(BuildContext context) {
    final app = ProcessLamaTheme.of(context);
    return _ChartCard(
      key: ValueKey('inspector-history-$label'),
      header: _ChartHeader(label: label, value: value),
      scaleLabels: _buildScaleLegendLabels(scaleMaxValue, formatScaleValue),
      chartHeight: _chartHeight,
      chart: _HoverableHistoryChart(
        sampleCount: samples.length,
        valueAt: (index) => samples[index].isFinite
            ? formatScaleValue(samples[index])
            : _gapLabel,
        painter: (hovered) => _MetricHistoryChartPainter(
          samples: samples,
          maxValue: scaleMaxValue,
          hoveredIndex: hovered,
          color: app.chartLine.withValues(
            alpha: ProcessLamaTheme.chartHistoryOpacity,
          ),
          latestColor: context.meridian.colors.accent,
        ),
      ),
    );
  }
}

class _MetricHistoryChartPainter extends CustomPainter {
  const _MetricHistoryChartPainter({
    required this.samples,
    required this.maxValue,
    required this.color,
    required this.latestColor,
    this.hoveredIndex,
  });

  static const int _slotCount = _historySlotCount;

  /// The sample under the pointer; it takes the highlight from the latest.
  final int? hoveredIndex;

  final List<double> samples;
  final double maxValue;
  final Color color;
  final Color latestColor;

  @override
  void paint(Canvas canvas, Size size) {
    if (samples.isEmpty || size.isEmpty) {
      return;
    }

    final effectiveMax = maxValue.clamp(0.1, double.infinity);
    final leadingOffset = math.max(0, _slotCount - samples.length);
    final slotWidth = size.width / _slotCount;
    final barWidth = math.max(1.0, slotWidth * 0.7);
    final basePaint = Paint()..color = color;
    final latestPaint = Paint()..color = latestColor;

    for (var index = 0; index < samples.length; index++) {
      final sample = samples[index];
      if (!sample.isFinite) {
        continue;
      }
      final normalized = (sample / effectiveMax).clamp(0.0, 1.0);
      final barHeight = size.height * normalized;
      if (barHeight <= 0) {
        continue;
      }

      final slotIndex = leadingOffset + index;
      final x = slotIndex * slotWidth + (slotWidth - barWidth) / 2;
      final y = size.height - barHeight;
      canvas.drawRect(
        Rect.fromLTWH(x, y, barWidth, barHeight),
        index == (hoveredIndex ?? samples.length - 1) ? latestPaint : basePaint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _MetricHistoryChartPainter oldDelegate) =>
      samples != oldDelegate.samples ||
      maxValue != oldDelegate.maxValue ||
      hoveredIndex != oldDelegate.hoveredIndex ||
      color != oldDelegate.color ||
      latestColor != oldDelegate.latestColor;
}

class _NetworkThroughputGraphRow extends StatelessWidget {
  const _NetworkThroughputGraphRow({
    required this.label,
    required this.directionLabel,
    required this.upperValue,
    required this.lowerValue,
    required this.upperSamples,
    required this.lowerSamples,
  });

  static const double _chartHeight = 56;

  final String label;
  final String directionLabel;
  final double upperValue;
  final double lowerValue;
  final List<double> upperSamples;
  final List<double> lowerSamples;

  @override
  Widget build(BuildContext context) {
    final app = ProcessLamaTheme.of(context);
    final scaleMaxValue = _sampleMax([
      ...upperSamples,
      ...lowerSamples,
    ], math.max(upperValue, lowerValue));
    return _ChartCard(
      key: ValueKey('inspector-history-$label'),
      header: _ChartHeader(
        label: label,
        detail: directionLabel,
        value: '${_formatRate(upperValue)} / ${_formatRate(lowerValue)}',
      ),
      scaleLabels: _buildDivergingScaleLegendLabels(scaleMaxValue),
      chartHeight: _chartHeight,
      chart: _HoverableHistoryChart(
        sampleCount: math.max(upperSamples.length, lowerSamples.length),
        valueAt: (index) {
          double at(List<double> samples) =>
              index < samples.length ? samples[index] : 0;
          final upper = at(upperSamples);
          final lower = at(lowerSamples);
          if (!upper.isFinite && !lower.isFinite) {
            return _gapLabel;
          }
          String rate(double value) =>
              value.isFinite ? _formatRate(value) : _gapLabel;
          return '${rate(upper)} / ${rate(lower)}';
        },
        painter: (hovered) => _NetworkThroughputChartPainter(
          upperSamples: upperSamples,
          lowerSamples: lowerSamples,
          maxValue: scaleMaxValue,
          hoveredIndex: hovered,
          upperColor: app.chartUpper,
          lowerColor: app.chartLower,
          axisColor: context.meridian.colors.lineStrong,
        ),
      ),
    );
  }
}

class _NetworkThroughputChartPainter extends CustomPainter {
  const _NetworkThroughputChartPainter({
    required this.upperSamples,
    required this.lowerSamples,
    required this.maxValue,
    required this.upperColor,
    required this.lowerColor,
    required this.axisColor,
    this.hoveredIndex,
  });

  static const int _slotCount = _historySlotCount;

  /// The sample under the pointer; it takes the highlight from the latest.
  final int? hoveredIndex;

  final List<double> upperSamples;
  final List<double> lowerSamples;
  final double maxValue;
  final Color upperColor;
  final Color lowerColor;
  final Color axisColor;

  @override
  void paint(Canvas canvas, Size size) {
    if ((upperSamples.isEmpty && lowerSamples.isEmpty) || size.isEmpty) {
      return;
    }

    final effectiveMax = maxValue.clamp(0.1, double.infinity);
    final zeroY = size.height / 2;
    final slotWidth = size.width / _slotCount;
    final barWidth = math.max(1.0, slotWidth * 0.7);
    final sampleCount = math.max(upperSamples.length, lowerSamples.length);
    final leadingOffset = math.max(0, _slotCount - sampleCount);
    final upperPaint = Paint()
      ..color = upperColor.withValues(
        alpha: ProcessLamaTheme.chartHistoryOpacity,
      );
    final lowerPaint = Paint()
      ..color = lowerColor.withValues(
        alpha: ProcessLamaTheme.chartHistoryOpacity,
      );
    final upperLatestPaint = Paint()..color = upperColor;
    final lowerLatestPaint = Paint()..color = lowerColor;

    canvas.drawLine(
      Offset(0, zeroY),
      Offset(size.width, zeroY),
      Paint()
        ..color = axisColor
        ..strokeWidth = 1,
    );

    for (var index = 0; index < sampleCount; index++) {
      final slotIndex = leadingOffset + index;
      final x = slotIndex * slotWidth + (slotWidth - barWidth) / 2;
      final upperSample = index < upperSamples.length
          ? upperSamples[index]
          : 0.0;
      final lowerSample = index < lowerSamples.length
          ? lowerSamples[index]
          : 0.0;
      final isLatest = index == (hoveredIndex ?? sampleCount - 1);

      _drawNetworkBar(
        canvas: canvas,
        x: x,
        width: barWidth,
        zeroY: zeroY,
        halfHeight: zeroY,
        sample: upperSample,
        effectiveMax: effectiveMax,
        direction: -1,
        paint: isLatest ? upperLatestPaint : upperPaint,
      );
      _drawNetworkBar(
        canvas: canvas,
        x: x,
        width: barWidth,
        zeroY: zeroY,
        halfHeight: zeroY,
        sample: lowerSample,
        effectiveMax: effectiveMax,
        direction: 1,
        paint: isLatest ? lowerLatestPaint : lowerPaint,
      );
    }
  }

  void _drawNetworkBar({
    required Canvas canvas,
    required double x,
    required double width,
    required double zeroY,
    required double halfHeight,
    required double sample,
    required double effectiveMax,
    required int direction,
    required Paint paint,
  }) {
    if (!sample.isFinite) {
      return;
    }
    final normalized = (sample / effectiveMax).clamp(0.0, 1.0);
    final barHeight = halfHeight * normalized;
    if (barHeight <= 0) {
      return;
    }
    final y = direction < 0 ? zeroY - barHeight : zeroY;
    canvas.drawRect(Rect.fromLTWH(x, y, width, barHeight), paint);
  }

  @override
  bool shouldRepaint(covariant _NetworkThroughputChartPainter oldDelegate) =>
      upperSamples != oldDelegate.upperSamples ||
      lowerSamples != oldDelegate.lowerSamples ||
      maxValue != oldDelegate.maxValue ||
      hoveredIndex != oldDelegate.hoveredIndex ||
      upperColor != oldDelegate.upperColor ||
      lowerColor != oldDelegate.lowerColor ||
      axisColor != oldDelegate.axisColor;
}

List<String> _buildScaleLegendLabels(
  double scaleMaxValue,
  String Function(double value) formatScaleValue,
) {
  const tickFractions = <double>[1, 1 / 2, 0];
  return [
    for (final fraction in tickFractions)
      formatScaleValue(scaleMaxValue * fraction),
  ];
}

List<String> _buildDivergingScaleLegendLabels(double scaleMaxValue) {
  return [_formatRate(scaleMaxValue), '0', _formatRate(scaleMaxValue)];
}

/// The hover value of a gap, where no sample arrived during an outage.
const String _gapLabel = '–';

/// The largest sample, skipping gaps.
double _finiteMax(Iterable<double> samples) => samples.fold(
  0.0,
  (largest, sample) => sample.isFinite && sample > largest ? sample : largest,
);

/// History charts show the last [_historySlotCount] samples, one bar each,
/// right-aligned.
const int _historySlotCount = 60;

/// A history chart that highlights the bar under the pointer and shows its
/// value in a small label above it.
class _HoverableHistoryChart extends StatefulWidget {
  const _HoverableHistoryChart({
    required this.sampleCount,
    required this.valueAt,
    required this.painter,
  });

  final int sampleCount;
  final String Function(int index) valueAt;
  final CustomPainter Function(int? hoveredIndex) painter;

  @override
  State<_HoverableHistoryChart> createState() => _HoverableHistoryChartState();
}

class _HoverableHistoryChartState extends State<_HoverableHistoryChart> {
  int? _hovered;

  void _hover(Offset position, double width) {
    final slotWidth = width / _historySlotCount;
    final slot = (position.dx / slotWidth).floor();
    final index =
        slot - math.max<int>(0, _historySlotCount - widget.sampleCount);
    final next = index >= 0 && index < widget.sampleCount ? index : null;
    if (next != _hovered) {
      setState(() => _hovered = next);
    }
  }

  @override
  Widget build(BuildContext context) {
    final meridian = context.meridian;
    final hovered = _hovered != null && _hovered! < widget.sampleCount
        ? _hovered
        : null;
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final slotWidth = width / _historySlotCount;
        final leading = math.max<int>(
          0,
          _historySlotCount - widget.sampleCount,
        );
        return MouseRegion(
          onHover: (event) => _hover(event.localPosition, width),
          onExit: (_) => setState(() => _hovered = null),
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned.fill(
                child: CustomPaint(painter: widget.painter(hovered)),
              ),
              if (hovered != null)
                Positioned.fill(
                  child: IgnorePointer(
                    // Align keeps the label inside the chart at both ends.
                    child: Align(
                      alignment: Alignment(
                        ((leading + hovered + 0.5) * slotWidth / width) * 2 - 1,
                        -1,
                      ),
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: meridian.colors.raised,
                          borderRadius: BorderRadius.circular(
                            meridian.radius.xs,
                          ),
                          boxShadow: meridian.shadows.shadowFloat,
                        ),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: MeridianSpace.space2,
                            vertical: MeridianSpace.space1,
                          ),
                          child: Text(
                            widget.valueAt(hovered),
                            maxLines: 1,
                            style: MeridianTextStyles.numeric(
                              meridian.text.codeSm,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}
