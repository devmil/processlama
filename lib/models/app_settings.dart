import 'process_tree.dart';

enum AppAppearanceMode {
  system,
  light,
  dark;

  static AppAppearanceMode fromJson(String? value) {
    return switch (value) {
      'light' => AppAppearanceMode.light,
      'dark' => AppAppearanceMode.dark,
      _ => AppAppearanceMode.system,
    };
  }
}

/// How tall rows in the process tree and other lists are.
enum AppRowDensity {
  compact,
  regular,
  comfortable;

  static AppRowDensity fromJson(String? value) {
    for (final density in AppRowDensity.values) {
      if (density.name == value) {
        return density;
      }
    }
    return AppSettings.defaultRowDensity;
  }
}

enum AppReleaseChannel {
  stable,
  beta;

  static AppReleaseChannel fromJson(String? value) {
    return switch (value) {
      'beta' => AppReleaseChannel.beta,
      _ => AppReleaseChannel.stable,
    };
  }
}

ProcessSortColumn _processSortColumnFromJson(String? value) {
  for (final column in ProcessSortColumn.values) {
    if (column.name == value) {
      return column;
    }
  }
  return AppSettings.defaultProcessSortColumn;
}

ProcessSortDirection _processSortDirectionFromJson(String? value) {
  return switch (value) {
    'ascending' => ProcessSortDirection.ascending,
    'descending' => ProcessSortDirection.descending,
    _ => AppSettings.defaultProcessSortDirection,
  };
}

class AppSettings {
  const AppSettings({
    this.pollingIntervalMs = 1000,
    this.rememberTreeExpansion = true,
    this.savedFilters = const <String>[],
    this.visibleColumns = defaultVisibleColumns,
    this.columnWidths = const <String, double>{},
    this.inspectorWidth = defaultInspectorWidth,
    this.processSortColumn = defaultProcessSortColumn,
    this.processSortDirection = defaultProcessSortDirection,
    this.appearanceMode = AppAppearanceMode.system,
    this.rowHeatmap = true,
    this.rowDensity = defaultRowDensity,
    this.languageCode = defaultLanguageCode,
    this.releaseChannel = defaultReleaseChannel,
  });

  factory AppSettings.fromJson(Map<String, Object?> json) {
    return AppSettings(
      pollingIntervalMs:
          (json['polling_interval_ms'] as num?)?.toInt() ??
          defaultPollingIntervalMs,
      rememberTreeExpansion:
          json['remember_tree_expansion'] as bool? ??
          defaultRememberTreeExpansion,
      savedFilters:
          (json['saved_filters'] as List<Object?>?)
              ?.whereType<String>()
              .toList() ??
          const <String>[],
      visibleColumns:
          (json['visible_columns'] as List<Object?>?)
              ?.whereType<String>()
              .toList() ??
          defaultVisibleColumns,
      columnWidths: _columnWidthsFromJson(json['column_widths']),
      inspectorWidth:
          (json['inspector_width'] as num?)?.toDouble() ??
          AppSettings.defaultInspectorWidth,
      processSortColumn: _processSortColumnFromJson(
        json['process_sort_column'] as String?,
      ),
      processSortDirection: _processSortDirectionFromJson(
        json['process_sort_direction'] as String?,
      ),
      appearanceMode: AppAppearanceMode.fromJson(
        json['appearance_mode'] as String?,
      ),
      rowHeatmap: json['row_heatmap'] as bool? ?? defaultRowHeatmap,
      rowDensity: AppRowDensity.fromJson(json['row_density'] as String?),
      languageCode: json['language_code'] as String? ?? defaultLanguageCode,
      releaseChannel: AppReleaseChannel.fromJson(
        json['release_channel'] as String?,
      ),
    );
  }

  static const int defaultPollingIntervalMs = 1000;
  static const bool defaultRememberTreeExpansion = true;
  static const bool defaultRowHeatmap = true;
  static const AppRowDensity defaultRowDensity = AppRowDensity.compact;
  static const String defaultLanguageCode = 'en';
  static const AppReleaseChannel defaultReleaseChannel =
      AppReleaseChannel.stable;
  static const List<String> supportedLanguageCodes = <String>['en', 'de'];
  static const ProcessSortColumn defaultProcessSortColumn =
      ProcessSortColumn.treeCpu;
  static const ProcessSortDirection defaultProcessSortDirection =
      ProcessSortDirection.descending;
  static const double defaultInspectorWidth = 360;
  static const List<String> defaultVisibleColumns = <String>[
    'name',
    'pid',
    'cpu',
    'treeCpu',
    'gpu',
    'treeGpu',
    'memory',
    'treeMemory',
    'networkIn',
    'networkOut',
    'treeNetworkIn',
    'treeNetworkOut',
    'storageRead',
    'storageWrite',
    'treeStorageRead',
    'treeStorageWrite',
    'startTime',
    'status',
    'uid',
    'ports',
  ];

  static const List<String> availableColumns = <String>[
    'name',
    'pid',
    'cpu',
    'treeCpu',
    'gpu',
    'treeGpu',
    'memory',
    'treeMemory',
    'networkIn',
    'networkOut',
    'treeNetworkIn',
    'treeNetworkOut',
    'storageRead',
    'storageWrite',
    'treeStorageRead',
    'treeStorageWrite',
    'startTime',
    'status',
    'uid',
    'ports',
  ];

  final int pollingIntervalMs;
  final bool rememberTreeExpansion;
  final List<String> savedFilters;
  final List<String> visibleColumns;
  final Map<String, double> columnWidths;
  final double inspectorWidth;
  final ProcessSortColumn processSortColumn;
  final ProcessSortDirection processSortDirection;
  final AppAppearanceMode appearanceMode;
  final bool rowHeatmap;
  final AppRowDensity rowDensity;
  final String languageCode;
  final AppReleaseChannel releaseChannel;

  AppSettings copyWith({
    int? pollingIntervalMs,
    bool? rememberTreeExpansion,
    List<String>? savedFilters,
    List<String>? visibleColumns,
    Map<String, double>? columnWidths,
    double? inspectorWidth,
    ProcessSortColumn? processSortColumn,
    ProcessSortDirection? processSortDirection,
    AppAppearanceMode? appearanceMode,
    bool? rowHeatmap,
    AppRowDensity? rowDensity,
    String? languageCode,
    AppReleaseChannel? releaseChannel,
  }) {
    return AppSettings(
      pollingIntervalMs: pollingIntervalMs ?? this.pollingIntervalMs,
      rememberTreeExpansion:
          rememberTreeExpansion ?? this.rememberTreeExpansion,
      savedFilters: savedFilters ?? this.savedFilters,
      visibleColumns: visibleColumns ?? this.visibleColumns,
      columnWidths: columnWidths ?? this.columnWidths,
      inspectorWidth: inspectorWidth ?? this.inspectorWidth,
      processSortColumn: processSortColumn ?? this.processSortColumn,
      processSortDirection: processSortDirection ?? this.processSortDirection,
      appearanceMode: appearanceMode ?? this.appearanceMode,
      rowHeatmap: rowHeatmap ?? this.rowHeatmap,
      rowDensity: rowDensity ?? this.rowDensity,
      languageCode: languageCode ?? this.languageCode,
      releaseChannel: releaseChannel ?? this.releaseChannel,
    );
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'polling_interval_ms': pollingIntervalMs,
      'remember_tree_expansion': rememberTreeExpansion,
      'saved_filters': savedFilters,
      'visible_columns': visibleColumns,
      'column_widths': columnWidths,
      'inspector_width': inspectorWidth,
      'process_sort_column': processSortColumn.name,
      'process_sort_direction': processSortDirection.name,
      'appearance_mode': appearanceMode.name,
      'row_heatmap': rowHeatmap,
      'row_density': rowDensity.name,
      'language_code': languageCode,
      'release_channel': releaseChannel.name,
    };
  }
}

Map<String, double> _columnWidthsFromJson(Object? value) {
  if (value is! Map) {
    return const <String, double>{};
  }
  return <String, double>{
    for (final entry in value.entries)
      if (entry.key is String &&
          AppSettings.availableColumns.contains(entry.key) &&
          entry.value is num)
        entry.key as String: (entry.value as num).toDouble(),
  };
}
