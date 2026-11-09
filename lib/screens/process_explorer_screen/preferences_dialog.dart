part of '../process_explorer_screen.dart';

/// The pages of the preferences, in the order the dialog lists them.
enum _PreferencesPage {
  appearance,
  processTree,
  columns,
  remoteHosts,
  updates,
  diagnostics,
}

class _PreferencesDialog extends StatelessWidget {
  const _PreferencesDialog({
    required this.service,
    this.initialPage = _PreferencesPage.appearance,
  });

  static const int _minPollingMs = 250;
  static const int _maxPollingMs = 10000;
  static const int _pollingStepMs = 250;

  final SettingsService service;
  final _PreferencesPage initialPage;

  @override
  Widget build(BuildContext context) => MeridianSettingsDialog(
    title: context.l10n.preferences,
    initialPage: initialPage.index,
    pages: [for (final page in _PreferencesPage.values) _page(context, page)],
  );

  MeridianSettingsPage _page(BuildContext context, _PreferencesPage page) {
    final l10n = context.l10n;
    return switch (page) {
      _PreferencesPage.diagnostics => MeridianSettingsPage(
        label: l10n.diagnosticsTitle,
        icon: MeridianIcons.activity,
        description: l10n.diagnosticsDescription,
        builder: (_) => const DiagnosticSettings(),
      ),
      _PreferencesPage.appearance => MeridianSettingsPage(
        label: l10n.appearance,
        icon: MeridianIcons.palette,
        description: l10n.preferencesPageAppearanceDetail,
        builder: (context) => _settingsPage(
          (settings) => [
            MeridianSettingsRow(
              label: l10n.preferencesTheme,
              children: [
                MeridianSegmented<AppAppearanceMode>(
                  label: l10n.preferencesTheme,
                  value: settings.appearanceMode,
                  onChanged: service.updateAppearanceMode,
                  segments: [
                    MeridianSegment(
                      value: AppAppearanceMode.system,
                      label: l10n.system,
                    ),
                    MeridianSegment(
                      value: AppAppearanceMode.light,
                      label: l10n.light,
                    ),
                    MeridianSegment(
                      value: AppAppearanceMode.dark,
                      label: l10n.dark,
                    ),
                  ],
                ),
              ],
            ),
            MeridianSettingsRow(
              label: l10n.rowDensity,
              children: [
                MeridianSegmented<AppRowDensity>(
                  label: l10n.rowDensity,
                  value: settings.rowDensity,
                  onChanged: service.updateRowDensity,
                  segments: [
                    MeridianSegment(
                      value: AppRowDensity.compact,
                      label: l10n.rowDensityCompact,
                    ),
                    MeridianSegment(
                      value: AppRowDensity.regular,
                      label: l10n.rowDensityRegular,
                    ),
                    MeridianSegment(
                      value: AppRowDensity.comfortable,
                      label: l10n.rowDensityComfortable,
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
      _PreferencesPage.processTree => MeridianSettingsPage(
        label: l10n.preferencesPageProcessTree,
        icon: MeridianIcons.listTree,
        description: l10n.preferencesPageProcessTreeDetail,
        builder: (context) => _settingsPage(
          (settings) => [
            MeridianSettingsRow(
              label: l10n.pollingInterval,
              children: [
                MeridianSlider(
                  label: l10n.pollingInterval,
                  value: settings.pollingIntervalMs
                      .clamp(_minPollingMs, _maxPollingMs)
                      .toDouble(),
                  min: _minPollingMs.toDouble(),
                  max: _maxPollingMs.toDouble(),
                  step: _pollingStepMs.toDouble(),
                  valueLabel: (value) => '${value.round()} ms',
                  onChanged: (value) =>
                      service.updatePollingIntervalMs(value.round()),
                ),
              ],
            ),
            MeridianSettingsRow(
              label: l10n.tree,
              children: [
                MeridianSwitch(
                  label: l10n.rememberTreeExpansion,
                  value: settings.rememberTreeExpansion,
                  onChanged: service.updateRememberTreeExpansion,
                ),
                MeridianSwitch(
                  label: l10n.rowHeatmap,
                  value: settings.rowHeatmap,
                  onChanged: service.updateRowHeatmap,
                ),
              ],
            ),
          ],
        ),
      ),
      _PreferencesPage.columns => MeridianSettingsPage(
        label: l10n.columns,
        icon: MeridianIcons.columns2,
        description: l10n.preferencesPageColumnsDetail,
        builder: (context) => _settingsWatch(
          (settings) => _ColumnPreferences(
            settings: settings,
            onChanged: service.updateVisibleColumns,
          ),
        ),
      ),
      _PreferencesPage.remoteHosts => MeridianSettingsPage(
        label: l10n.preferencesPageRemoteHosts,
        icon: MeridianIcons.server,
        description: l10n.preferencesPageRemoteHostsDetail,
        builder: (context) => const RemoteHostsSettingsSection(),
      ),
      _PreferencesPage.updates => MeridianSettingsPage(
        label: l10n.preferencesPageUpdates,
        icon: MeridianIcons.download,
        description: l10n.preferencesPageUpdatesDetail,
        builder: (context) => _settingsPage(
          (settings) => [
            MeridianSettingsRow(
              label: l10n.releaseChannel,
              children: [
                MeridianSegmented<AppReleaseChannel>(
                  label: l10n.releaseChannel,
                  value: settings.releaseChannel,
                  onChanged: service.updateReleaseChannel,
                  segments: [
                    MeridianSegment(
                      value: AppReleaseChannel.stable,
                      label: l10n.releaseChannelStable,
                    ),
                    MeridianSegment(
                      value: AppReleaseChannel.beta,
                      label: l10n.releaseChannelBeta,
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    };
  }

  /// A page of settings rows that follows the stored settings.
  Widget _settingsPage(List<Widget> Function(AppSettings settings) rows) =>
      _settingsWatch(
        (settings) => MeridianSettingsGroup(children: rows(settings)),
      );

  Widget _settingsWatch(Widget Function(AppSettings settings) builder) =>
      ValueListenableBuilder<AppSettings>(
        valueListenable: service.settings,
        builder: (context, settings, _) => builder(settings),
      );
}

/// Which columns the tree shows, and in which order.
class _ColumnPreferences extends StatelessWidget {
  const _ColumnPreferences({required this.settings, required this.onChanged});

  final AppSettings settings;
  final ValueChanged<List<String>> onChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final visible = _normalizedVisibleColumnIds(settings.visibleColumns);
    // Visible columns first, in their order; hidden ones after them.
    final ordered = [
      ...visible,
      ...AppSettings.availableColumns.where((id) => !visible.contains(id)),
    ];
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final id in ordered)
          // The control height, grown only when large text needs it.
          ConstrainedBox(
            constraints: BoxConstraints(
              minHeight: context.meridian.density.controlExtent,
            ),
            child: Row(
              children: [
                Expanded(
                  child: Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: MeridianCheckbox(
                      label: _columnLabel(context, id),
                      value: visible.contains(id),
                      onChanged: id == 'name'
                          ? null
                          : (value) =>
                                onChanged(_setColumn(visible, id, value)),
                    ),
                  ),
                ),
                MeridianIconButton(
                  label: l10n.moveColumnEarlier,
                  icon: MeridianIcons.arrowUp,
                  size: MeridianControlSize.small,
                  onPressed: visible.indexOf(id) > 0
                      ? () => onChanged(
                          _moveColumn(visible, visible.indexOf(id), -1),
                        )
                      : null,
                ),
                MeridianIconButton(
                  label: l10n.moveColumnLater,
                  icon: MeridianIcons.arrowDown,
                  size: MeridianControlSize.small,
                  onPressed:
                      visible.contains(id) &&
                          visible.indexOf(id) < visible.length - 1
                      ? () => onChanged(
                          _moveColumn(visible, visible.indexOf(id), 1),
                        )
                      : null,
                ),
              ],
            ),
          ),
      ],
    );
  }
}

List<String> _setColumn(List<String> visible, String id, bool? show) {
  final next = [...visible];
  if (show ?? false) {
    if (!next.contains(id)) {
      next.add(id);
    }
  } else {
    next.remove(id);
  }
  return next;
}

List<String> _moveColumn(List<String> columns, int index, int delta) {
  final next = [...columns];
  final item = next.removeAt(index);
  next.insert(index + delta, item);
  return next;
}

List<String> _moveColumnBefore(
  List<String> columns,
  String fromColumnId,
  String toColumnId,
) {
  if (fromColumnId == toColumnId) {
    return _normalizedVisibleColumnIds(columns);
  }
  final next = _normalizedVisibleColumnIds(columns);
  final fromIndex = next.indexOf(fromColumnId);
  final toIndex = next.indexOf(toColumnId);
  if (fromIndex == -1 || toIndex == -1) {
    return next;
  }
  final item = next.removeAt(fromIndex);
  final adjustedToIndex = fromIndex < toIndex ? toIndex - 1 : toIndex;
  next.insert(adjustedToIndex, item);
  return next;
}
