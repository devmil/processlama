import 'package:flutter/material.dart';
import 'package:meridian_ui/meridian_ui.dart';

import '../models/models.dart';

/// ProcessLama's app-only tokens on top of Meridian: the CPU heat tint of
/// process rows and the tree search highlights.
///
/// Everything else (surfaces, ink, status colours, type, spacing, motion)
/// comes from `context.meridian` and the ProcessLama brand.
@immutable
class ProcessLamaTheme extends ThemeExtension<ProcessLamaTheme> {
  const ProcessLamaTheme({
    required this.rowHeat,
    required this.searchMatchRow,
    required this.searchHighlight,
    required this.chartLine,
    required this.chartUpper,
    required this.chartLower,
  });

  /// Derives the app tokens from the active Meridian colours.
  factory ProcessLamaTheme.resolve(MeridianColors colors) => ProcessLamaTheme(
    rowHeat: colors.accent,
    searchMatchRow: colors.warningBg,
    searchHighlight: colors.warning.withValues(alpha: searchHighlightOpacity),
    chartLine: colors.series1,
    chartUpper: colors.series1,
    chartLower: colors.series2,
  );

  // Brand composition sizes; the shared signature itself uses MeridianSize.icon.
  static const double aboutTileSize = 96;
  static const double emptyLamaHeight = 48;

  /// Opacity of [rowHeat] on a row whose subtree uses 100% CPU.
  static const double maxRowHeatOpacity = 0.12;

  /// Opacity of the tree search highlight behind matched text.
  static const double searchHighlightOpacity = 0.28;

  /// Opacity of history bars before the latest sample.
  static const double chartHistoryOpacity = 0.55;

  /// Tints process rows by their subtree's CPU when the heatmap is on.
  final Color rowHeat;

  /// Fill of rows that match the tree search.
  final Color searchMatchRow;

  /// Background behind the matched text of a tree search.
  final Color searchHighlight;

  /// Sparklines and single-series history charts.
  final Color chartLine;

  /// The upper (outgoing, read) half of a diverging throughput chart.
  final Color chartUpper;

  /// The lower (incoming, write) half of a diverging throughput chart.
  final Color chartLower;

  static ProcessLamaTheme of(BuildContext context) =>
      Theme.of(context).extension<ProcessLamaTheme>() ??
      ProcessLamaTheme.resolve(context.meridian.colors);

  @override
  ProcessLamaTheme copyWith({
    Color? rowHeat,
    Color? searchMatchRow,
    Color? searchHighlight,
    Color? chartLine,
    Color? chartUpper,
    Color? chartLower,
  }) => ProcessLamaTheme(
    rowHeat: rowHeat ?? this.rowHeat,
    searchMatchRow: searchMatchRow ?? this.searchMatchRow,
    searchHighlight: searchHighlight ?? this.searchHighlight,
    chartLine: chartLine ?? this.chartLine,
    chartUpper: chartUpper ?? this.chartUpper,
    chartLower: chartLower ?? this.chartLower,
  );

  @override
  ProcessLamaTheme lerp(ThemeExtension<ProcessLamaTheme>? other, double t) {
    if (other is! ProcessLamaTheme) {
      return this;
    }
    return ProcessLamaTheme(
      rowHeat: Color.lerp(rowHeat, other.rowHeat, t)!,
      searchMatchRow: Color.lerp(searchMatchRow, other.searchMatchRow, t)!,
      searchHighlight: Color.lerp(searchHighlight, other.searchHighlight, t)!,
      chartLine: Color.lerp(chartLine, other.chartLine, t)!,
      chartUpper: Color.lerp(chartUpper, other.chartUpper, t)!,
      chartLower: Color.lerp(chartLower, other.chartLower, t)!,
    );
  }
}

/// The ProcessLama theme: Meridian with the ProcessLama brand (signal blue,
/// Geist and Geist Mono) at the chosen row [density] plus [ProcessLamaTheme].
ThemeData buildProcessLamaTheme({
  Brightness brightness = Brightness.light,
  AppRowDensity density = AppSettings.defaultRowDensity,
}) {
  final colors = MeridianTheme.resolve(
    brand: MeridianBrands.mimameidr,
    brightness: brightness,
  ).colors;
  return buildMeridianTheme(
    brand: MeridianBrands.mimameidr,
    brightness: brightness,
    density: switch (density) {
      AppRowDensity.compact => MeridianDensity.compact,
      AppRowDensity.regular => MeridianDensity.regular,
      AppRowDensity.comfortable => MeridianDensity.comfortable,
    },
    extensions: [ProcessLamaTheme.resolve(colors)],
  );
}
