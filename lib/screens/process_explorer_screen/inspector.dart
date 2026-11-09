part of '../process_explorer_screen.dart';

/// The inspector island: the selected process, its tabs and their content.
class _Inspector extends StatefulWidget {
  const _Inspector({
    required this.tree,
    required this.inspector,
    required this.settings,
    required this.networkUnavailable,
    required this.onInstallNetworkTelemetry,
    required this.onShowPort,
    required this.onSelectProcess,
    this.networkHint,
  });

  final ProcessTreeView tree;
  final ProcessInspectorView inspector;
  final AppSettings settings;
  final bool networkUnavailable;
  final VoidCallback onInstallNetworkTelemetry;

  /// Filters the tree to the processes using a port.
  final ValueChanged<int> onShowPort;
  final ValueChanged<ProcessIdentity> onSelectProcess;

  /// What the network banner says and offers; the local service when null.
  final _NetworkHint? networkHint;

  @override
  State<_Inspector> createState() => _InspectorState();
}

class _InspectorState extends State<_Inspector> {
  int _tab = 0;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final inspector = widget.inspector;
    final tree = widget.tree;
    final inspectorId = inspector.identity;
    final selectedRow = inspectorId == null
        ? null
        : tree.visibleRows.where((r) => r.identity == inspectorId).firstOrNull;

    final Widget content;
    if (inspector.process == null) {
      content = MeridianEmptyState(
        icon: MeridianIcons.activity,
        title: l10n.noProcessSelected,
        message: l10n.selectProcessToInspect,
      );
    } else {
      content = switch (_tab) {
        0 => _OverviewTab(
          inspector: inspector,
          settings: widget.settings,
          selectedRow: selectedRow,
          networkUnavailable: widget.networkUnavailable,
          onInstallNetworkTelemetry: widget.onInstallNetworkTelemetry,
          onShowPort: widget.onShowPort,
        ),
        1 => _DetailsTab(
          inspector: inspector,
          networkUnavailable: widget.networkUnavailable,
        ),
        2 => _NetworkTab(
          inspector: inspector,
          selectedRow: selectedRow,
          networkUnavailable: widget.networkUnavailable,
          onInstallNetworkTelemetry: widget.onInstallNetworkTelemetry,
          networkHint: widget.networkHint,
        ),
        3 => _ThreadsTab(inspector: inspector),
        _ => _FilesAndSocketsTab(
          inspector: inspector,
          onShowPort: widget.onShowPort,
          onSelectProcess: widget.onSelectProcess,
        ),
      };
    }

    return MeridianIsland(
      expandChild: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _InspectorHeader(tree: tree, inspector: inspector),
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: MeridianSpace.space5,
            ),
            child: MeridianTabs(
              index: _tab,
              onChanged: (index) => setState(() => _tab = index),
              tabs: [
                MeridianTab(label: l10n.tabOverview),
                MeridianTab(label: l10n.tabDetails),
                MeridianTab(label: l10n.tabNetwork),
                MeridianTab(label: l10n.tabThreads),
                MeridianTab(label: l10n.tabFilesAndSockets),
              ],
            ),
          ),
          const MeridianHairline(),
          if (tree.snapshot.error case final error?)
            Padding(
              padding: const EdgeInsets.fromLTRB(
                MeridianSpace.space5,
                MeridianSpace.space5,
                MeridianSpace.space5,
                0,
              ),
              child: MeridianBanner(
                tone: MeridianBannerTone.warning,
                message: l10n.bootstrapModeMessage(error),
              ),
            ),
          Expanded(child: content),
        ],
      ),
    );
  }
}

class _InspectorHeader extends StatelessWidget {
  const _InspectorHeader({required this.tree, required this.inspector});

  final ProcessTreeView tree;
  final ProcessInspectorView inspector;

  @override
  Widget build(BuildContext context) {
    final meridian = context.meridian;
    final process = inspector.process;
    final title = process?.displayName ?? context.l10n.inspector;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        MeridianSpace.space6,
        MeridianSpace.space6,
        MeridianSpace.space6,
        MeridianSpace.space4,
      ),
      child: Row(
        children: [
          _ProcessIcon(
            name: title,
            iconPath: inspector.iconPath,
            iconUpdates: inspector.iconUpdates,
            size: MeridianLayout.avatarLarge,
          ),
          const SizedBox(width: MeridianSpace.space5),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: meridian.text.heading,
                ),
                Text(
                  process == null
                      ? context.l10n.noProcessSelected
                      : context.l10n.pidPlatform(
                          '${process.pid}',
                          tree.snapshot.platform,
                        ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: MeridianTextStyles.numeric(
                    meridian.text.codeSm.copyWith(
                      color: meridian.colors.inkMuted,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The scrolling body of an inspector tab.
class _InspectorPage extends StatelessWidget {
  const _InspectorPage({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(MeridianSpace.space6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: children,
      ),
    );
  }
}

/// An `overline` heading between groups of an inspector tab.
class _InspectorSection extends StatelessWidget {
  const _InspectorSection(this.title);

  final String title;

  @override
  Widget build(BuildContext context) {
    final meridian = context.meridian;
    return Padding(
      padding: const EdgeInsets.only(
        top: MeridianSpace.space7,
        bottom: MeridianSpace.space4,
      ),
      child: Text(
        title.toUpperCase(),
        style: meridian.text.overline.copyWith(color: meridian.colors.inkMuted),
      ),
    );
  }
}

/// A process's ports as chips: listening ports first, then the other local
/// ports. Selecting a chip filters the tree to the processes using the port.
class _PortChips extends StatelessWidget {
  const _PortChips({super.key, required this.ports, required this.onShowPort});

  final ProcessPorts? ports;
  final ValueChanged<int> onShowPort;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final meridian = context.meridian;
    final ports = this.ports;
    if (ports == null || ports.isEmpty) {
      return Text(
        ports == null ? l10n.portsNotReported : l10n.noOccupiedPorts,
        style: meridian.text.caption.copyWith(color: meridian.colors.inkMuted),
      );
    }

    Widget group(String label, List<int> values, MeridianChipTone tone) =>
        Padding(
          padding: const EdgeInsets.only(bottom: MeridianSpace.space4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: meridian.text.caption.copyWith(
                  color: meridian.colors.inkMuted,
                ),
              ),
              const SizedBox(height: MeridianSpace.space2),
              Wrap(
                spacing: MeridianSpace.space2,
                runSpacing: MeridianSpace.space2,
                children: [
                  for (final port in values)
                    Semantics(
                      key: ValueKey(('port-chip', port)),
                      label: l10n.showPortProcesses(port),
                      button: true,
                      excludeSemantics: true,
                      child: MeridianChip(
                        label: '$port',
                        tone: tone,
                        onPressed: () => onShowPort(port),
                      ),
                    ),
                ],
              ),
            ],
          ),
        );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (ports.listening.isNotEmpty)
          group(l10n.listeningPorts, ports.listening, MeridianChipTone.accent),
        if (ports.other.isNotEmpty)
          group(l10n.otherLocalPorts, ports.other, MeridianChipTone.neutral),
      ],
    );
  }
}

class _NetworkTab extends StatelessWidget {
  const _NetworkTab({
    required this.inspector,
    required this.selectedRow,
    required this.networkUnavailable,
    required this.onInstallNetworkTelemetry,
    this.networkHint,
  });

  final ProcessInspectorView inspector;
  final ProcessTreeRow? selectedRow;
  final bool networkUnavailable;
  final VoidCallback onInstallNetworkTelemetry;
  final _NetworkHint? networkHint;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final process = inspector.process;
    if (process == null) {
      return MeridianEmptyState(
        icon: MeridianIcons.activity,
        title: l10n.noProcessSelected,
        message: l10n.selectProcessToInspectNetwork,
      );
    }
    final row = selectedRow;
    final hint =
        networkHint ??
        _NetworkHint(
          title: l10n.networkTelemetryUnavailable,
          message: l10n.networkTelemetryUnavailableDescription,
          actionLabel: l10n.installNetworkTelemetry,
          onAction: onInstallNetworkTelemetry,
        );
    return _InspectorPage(
      children: [
        if (networkUnavailable) ...[
          MeridianBanner(
            key: const ValueKey('network-hint'),
            tone: MeridianBannerTone.attention,
            icon: MeridianIcons.shieldAlert,
            title: hint.title,
            message: hint.message,
            actions: [
              if (hint.onAction case final onAction?)
                MeridianButton(
                  label: hint.actionLabel,
                  size: MeridianControlSize.small,
                  onPressed: onAction,
                ),
              if (hint.onGuide case final onGuide?)
                MeridianButton(
                  label: l10n.remoteHostSetupGuide,
                  size: MeridianControlSize.small,
                  variant: MeridianButtonVariant.quiet,
                  onPressed: onGuide,
                ),
            ],
          ),
          const SizedBox(height: MeridianSpace.space5),
        ],
        MeridianPropertyList(
          properties: [
            MeridianProperty(
              label: l10n.networkIn,
              value: networkUnavailable
                  ? l10n.metricUnavailable
                  : _formatRate(process.networkInBytesPerSecond),
              monospace: true,
            ),
            MeridianProperty(
              label: l10n.networkOut,
              value: networkUnavailable
                  ? l10n.metricUnavailable
                  : _formatRate(process.networkOutBytesPerSecond),
              monospace: true,
            ),
            MeridianProperty(
              label: l10n.totalIn,
              value: networkUnavailable
                  ? l10n.metricUnavailable
                  : _formatBytes(process.totalNetworkInBytes),
              monospace: true,
            ),
            MeridianProperty(
              label: l10n.totalOut,
              value: networkUnavailable
                  ? l10n.metricUnavailable
                  : _formatBytes(process.totalNetworkOutBytes),
              monospace: true,
            ),
          ],
        ),
        if (row != null && !networkUnavailable) ...[
          const SizedBox(height: MeridianSpace.space7),
          _NetworkThroughputGraphRow(
            label: l10n.networkHistory,
            directionLabel: l10n.networkOutIn,
            upperValue: row.treeNetworkOutBytesPerSecond,
            lowerValue: row.treeNetworkInBytesPerSecond,
            upperSamples: row.networkOutHistory,
            lowerSamples: row.networkInHistory,
          ),
        ],
      ],
    );
  }
}

enum _MetricScope { tree, process }

class _OverviewTab extends StatefulWidget {
  const _OverviewTab({
    required this.inspector,
    required this.settings,
    required this.selectedRow,
    required this.networkUnavailable,
    required this.onInstallNetworkTelemetry,
    required this.onShowPort,
  });

  final ProcessInspectorView inspector;
  final AppSettings settings;
  final ProcessTreeRow? selectedRow;
  final bool networkUnavailable;
  final VoidCallback onInstallNetworkTelemetry;
  final ValueChanged<int> onShowPort;

  @override
  State<_OverviewTab> createState() => _OverviewTabState();
}

class _OverviewTabState extends State<_OverviewTab> {
  static const double _cpuWarningPercent = 50;

  _MetricScope _scope = _MetricScope.tree;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final process = widget.inspector.process!;
    final row = widget.selectedRow;
    final useTree = _scope == _MetricScope.tree && row != null;
    final ports = useTree ? widget.inspector.treePorts : widget.inspector.ports;
    final cpuValue = useTree ? row.treeCpuUsage : process.cpuUsage;
    final gpuValue = useTree ? row.treeGpuUsage : process.gpuUsage;
    final rssValue = useTree ? row.treeRssBytes : process.rssBytes;
    final networkInValue = useTree
        ? row.treeNetworkInBytesPerSecond
        : process.networkInBytesPerSecond;
    final networkOutValue = useTree
        ? row.treeNetworkOutBytesPerSecond
        : process.networkOutBytesPerSecond;
    final storageReadValue = useTree
        ? row.treeStorageReadBytesPerSecond
        : process.storageReadBytesPerSecond;
    final storageWriteValue = useTree
        ? row.treeStorageWriteBytesPerSecond
        : process.storageWriteBytesPerSecond;
    final storageIoAvailable = useTree
        ? row.treeStorageIoAvailable
        : process.storageIoAvailable;
    final cpuHistory = useTree ? row.cpuHistory : row?.processCpuHistory;
    final gpuHistory = useTree ? row.gpuHistory : row?.processGpuHistory;
    final rssHistory = useTree ? row.rssHistory : row?.processRssHistory;
    final networkInHistory = useTree
        ? row.networkInHistory
        : row?.processNetworkInHistory;
    final networkOutHistory = useTree
        ? row.networkOutHistory
        : row?.processNetworkOutHistory;
    final storageReadHistory = useTree
        ? row.storageReadHistory
        : row?.processStorageReadHistory;
    final storageWriteHistory = useTree
        ? row.storageWriteHistory
        : row?.processStorageWriteHistory;

    return _InspectorPage(
      children: [
        if (row != null) ...[
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: MeridianSegmented<_MetricScope>(
              label: l10n.tree,
              size: MeridianControlSize.small,
              value: _scope,
              onChanged: (value) => setState(() => _scope = value),
              segments: [
                MeridianSegment(value: _MetricScope.tree, label: l10n.tree),
                MeridianSegment(
                  value: _MetricScope.process,
                  label: l10n.processScope,
                ),
              ],
            ),
          ),
          const SizedBox(height: MeridianSpace.space5),
        ],
        _MetricTileGrid(
          key: const ValueKey('inspector-summary-grid'),
          tiles: [
            _MetricTile(
              label: l10n.columnCpu,
              value: _formatPercent(cpuValue),
              warning: cpuValue >= _cpuWarningPercent,
            ),
            _MetricTile(
              label: l10n.overviewMemory,
              value: _formatBytes(rssValue),
            ),
            _MetricTile(label: l10n.columnGpu, value: _formatPercent(gpuValue)),
            _MetricTile(
              label: l10n.tabNetwork,
              value: widget.networkUnavailable
                  ? l10n.metricUnavailable
                  : _formatRate(networkInValue + networkOutValue),
              onPressed: widget.networkUnavailable
                  ? widget.onInstallNetworkTelemetry
                  : null,
            ),
            _MetricTile(
              label: l10n.overviewStorage,
              value: storageIoAvailable
                  ? _formatRate(storageReadValue + storageWriteValue)
                  : l10n.metricUnavailable,
            ),
            if (useTree)
              _MetricTile(
                label: l10n.descendants,
                value: '${row.descendantCount}',
              ),
          ],
        ),
        const SizedBox(height: MeridianSpace.space5),
        MeridianDisclosure(
          key: ValueKey(('overview-ports', widget.inspector.identity)),
          title: l10n.occupiedPorts,
          trailing: MeridianCount(
            key: const ValueKey('overview-port-count'),
            label: ports == null ? '—' : '${ports.count}',
            semanticLabel: ports == null
                ? l10n.portsNotReported
                : '${l10n.occupiedPorts}: ${ports.count}',
          ),
          child: Padding(
            padding: const EdgeInsets.only(top: MeridianSpace.space3),
            child: _PortChips(
              key: const ValueKey('overview-ports'),
              ports: ports,
              onShowPort: widget.onShowPort,
            ),
          ),
        ),
        if (row != null) ...[
          const SizedBox(height: MeridianSpace.space5),
          _MetricGraphRow(
            label: l10n.columnCpu,
            value: _formatPercent(cpuValue),
            samples: cpuHistory ?? const <double>[],
            scaleMaxValue: _sampleMax(cpuHistory ?? const <double>[], cpuValue),
            formatScaleValue: _formatPercent,
          ),
          _MetricGraphRow(
            label: l10n.columnRss,
            value: _formatBytes(rssValue),
            samples: rssHistory ?? const <double>[],
            scaleMaxValue: _sampleMax(
              rssHistory ?? const <double>[],
              rssValue.toDouble(),
            ),
            formatScaleValue: (value) => _formatBytes(value.round()),
          ),
          _MetricGraphRow(
            label: l10n.columnGpu,
            value: _formatPercent(gpuValue),
            samples: gpuHistory ?? const <double>[],
            scaleMaxValue: _sampleMax(gpuHistory ?? const <double>[], gpuValue),
            formatScaleValue: _formatPercent,
          ),
          if (!widget.networkUnavailable)
            _NetworkThroughputGraphRow(
              label: l10n.networkHistory,
              directionLabel: l10n.networkOutIn,
              upperValue: networkOutValue,
              lowerValue: networkInValue,
              upperSamples: networkOutHistory ?? const <double>[],
              lowerSamples: networkInHistory ?? const <double>[],
            ),
          if (storageIoAvailable)
            _NetworkThroughputGraphRow(
              label: l10n.storageHistory,
              directionLabel: l10n.storageReadWrite,
              upperValue: storageReadValue,
              lowerValue: storageWriteValue,
              upperSamples: storageReadHistory ?? const <double>[],
              lowerSamples: storageWriteHistory ?? const <double>[],
            ),
        ],
      ],
    );
  }
}

class _DetailsTab extends StatelessWidget {
  const _DetailsTab({
    required this.inspector,
    required this.networkUnavailable,
  });

  final ProcessInspectorView inspector;
  final bool networkUnavailable;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final process = inspector.process!;
    final files = inspector.detail?.files;
    final openFileCount =
        files is ProcessDetailAvailable<List<FileDescriptorInfo>>
        ? files.value.length
        : process.openFileCount;
    String storage(String Function() format) =>
        process.storageIoAvailable ? format() : l10n.metricUnavailable;
    String orUnknown(String value) => value.isEmpty ? l10n.unknown : value;

    return _InspectorPage(
      children: [
        MeridianPropertyList(
          properties: [
            MeridianProperty(
              label: l10n.parentPid,
              value: '${process.ppid}',
              monospace: true,
            ),
            MeridianProperty(
              label: l10n.userId,
              value: process.user.isEmpty
                  ? '${process.uid}'
                  : '${process.user} (${process.uid})',
            ),
            MeridianProperty(label: l10n.status, value: process.status.name),
            MeridianProperty(
              label: l10n.listeningPortsLabel,
              value: _portList(context, inspector.ports?.listening),
              monospace: true,
            ),
            MeridianProperty(
              label: l10n.otherLocalPorts,
              value: _portList(context, inspector.ports?.other),
              monospace: true,
            ),
            MeridianProperty(
              label: l10n.threads,
              value: '${process.threadCount}',
              monospace: true,
            ),
            MeridianProperty(
              label: l10n.openFiles,
              value: '$openFileCount',
              monospace: true,
            ),
            MeridianProperty(
              label: l10n.virtualMemory,
              value: _formatBytes(process.virtualMemoryBytes),
              monospace: true,
            ),
            MeridianProperty(
              label: l10n.nice,
              value: '${process.nice}',
              monospace: true,
            ),
            MeridianProperty(
              label: l10n.priority,
              value: '${process.priority}',
              monospace: true,
            ),
            MeridianProperty(
              label: l10n.gpu,
              value: _formatPercent(process.gpuUsage),
              monospace: true,
            ),
            MeridianProperty(
              label: l10n.netIn,
              value: networkUnavailable
                  ? l10n.metricUnavailable
                  : _formatRate(process.networkInBytesPerSecond),
              monospace: true,
            ),
            MeridianProperty(
              label: l10n.netOut,
              value: networkUnavailable
                  ? l10n.metricUnavailable
                  : _formatRate(process.networkOutBytesPerSecond),
              monospace: true,
            ),
            MeridianProperty(
              label: l10n.storageRead,
              value: storage(
                () => _formatRate(process.storageReadBytesPerSecond),
              ),
              monospace: true,
            ),
            MeridianProperty(
              label: l10n.storageWrite,
              value: storage(
                () => _formatRate(process.storageWriteBytesPerSecond),
              ),
              monospace: true,
            ),
            MeridianProperty(
              label: l10n.totalStorageRead,
              value: storage(() => _formatBytes(process.totalStorageReadBytes)),
              monospace: true,
            ),
            MeridianProperty(
              label: l10n.totalStorageWrite,
              value: storage(
                () => _formatBytes(process.totalStorageWriteBytes),
              ),
              monospace: true,
            ),
            MeridianProperty(
              label: l10n.identity,
              value: '${process.pid}@${process.startTimeUnixMs}',
              monospace: true,
            ),
            MeridianProperty(
              label: l10n.executable,
              value: orUnknown(process.executablePath),
              monospace: true,
            ),
            MeridianProperty(
              label: l10n.applicationBundle,
              value: orUnknown(process.appBundlePath),
              monospace: true,
            ),
            MeridianProperty(
              label: l10n.commandLine,
              value: orUnknown(process.commandLine),
              monospace: true,
            ),
          ],
        ),
        _InspectorSection(l10n.tabSecurity),
        _detailSection<SecurityDetailInfo>(
          context: context,
          section: inspector.detail?.security,
          fallback: inspector.security,
          emptyMessage: l10n.noSecurityMetadataReported,
          properties: (security) => _securityProperties(context, security),
        ),
      ],
    );
  }
}

String _endpoint(String address, int port, bool approximate) {
  final prefix = approximate ? '~' : '';
  if (port <= 0) {
    return '$prefix$address';
  }
  return '$prefix$address:$port';
}

String _dashIfEmpty(String value) {
  return value.trim().isEmpty ? '-' : value;
}

String _formatBool(BuildContext context, bool value) {
  return value ? context.l10n.yes : context.l10n.no;
}

class _FilesAndSocketsTab extends StatelessWidget {
  const _FilesAndSocketsTab({
    required this.inspector,
    required this.onShowPort,
    required this.onSelectProcess,
  });

  static const int _openFilesLimit = 500;

  final ProcessInspectorView inspector;
  final ValueChanged<int> onShowPort;
  final ValueChanged<ProcessIdentity> onSelectProcess;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return _InspectorPage(
      children: [
        _detailSection<List<FileDescriptorInfo>>(
          context: context,
          section: inspector.detail?.files,
          fallback: inspector.openFiles,
          emptyMessage: l10n.noOpenFilesReported,
          properties: (files) => [
            for (final file in files)
              MeridianProperty(
                label: '${file.fd} · ${file.kind}',
                value: file.path.isEmpty ? l10n.noPathAvailable : file.path,
                monospace: true,
              ),
          ],
          footer: (files) => files.length >= _openFilesLimit
              ? _StateBanner(
                  state: InspectorSectionState(
                    availability: InspectorAvailability.available,
                    message: l10n.openFilesTruncated,
                  ),
                )
              : null,
        ),
        _InspectorSection(l10n.occupiedPorts),
        _PortChips(ports: inspector.ports, onShowPort: onShowPort),
        Text(l10n.localPortsExplanation, style: context.meridian.text.caption),
        _InspectorSection(l10n.tabSockets),
        _detailSection<List<NetworkEndpointInfo>>(
          context: context,
          section: inspector.detail?.sockets,
          fallback: inspector.sockets,
          emptyMessage: l10n.noSocketsReported,
          properties: (endpoints) => [
            for (final endpoint in endpoints)
              MeridianProperty(
                label: endpoint.protocol,
                value:
                    '${_endpoint(endpoint.localAddress, endpoint.localPort, endpoint.localAddressApproximate)} -> '
                    '${_endpoint(endpoint.remoteAddress, endpoint.remotePort, endpoint.remoteAddressApproximate)}'
                    ' · ${endpoint.state}',
                monospace: true,
              ),
          ],
          footer: (_) => inspector.listenerOwnersByPort.isEmpty
              ? null
              : _SocketPeers(
                  ownersByPort: inspector.listenerOwnersByPort,
                  onSelectProcess: onSelectProcess,
                ),
        ),
      ],
    );
  }
}

/// Links from the selected process's loopback sockets to the local
/// processes listening on their remote ports.
class _SocketPeers extends StatelessWidget {
  const _SocketPeers({
    required this.ownersByPort,
    required this.onSelectProcess,
  });

  final Map<int, List<ProcessPortOwner>> ownersByPort;
  final ValueChanged<ProcessIdentity> onSelectProcess;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final meridian = context.meridian;
    final ports = ownersByPort.keys.toList()..sort();
    return Column(
      key: const ValueKey('socket-peers'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l10n.socketPeers,
          style: meridian.text.caption.copyWith(
            color: meridian.colors.inkMuted,
          ),
        ),
        const SizedBox(height: MeridianSpace.space2),
        Wrap(
          spacing: MeridianSpace.space2,
          runSpacing: MeridianSpace.space2,
          children: [
            for (final port in ports)
              for (final owner in ownersByPort[port]!)
                Semantics(
                  label: l10n.goToPortOwnerLabel(owner.name, owner.pid, port),
                  button: true,
                  excludeSemantics: true,
                  child: MeridianButton(
                    label:
                        ':$port · ${l10n.goToPortOwner(owner.name, owner.pid)}',
                    variant: MeridianButtonVariant.quiet,
                    size: MeridianControlSize.small,
                    icon: MeridianIcons.arrowRight,
                    onPressed: () => onSelectProcess(owner.identity),
                  ),
                ),
          ],
        ),
      ],
    );
  }
}

class _ThreadsTab extends StatelessWidget {
  const _ThreadsTab({required this.inspector});

  final ProcessInspectorView inspector;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return _InspectorPage(
      children: [
        _detailSection<ThreadInspectionInfo>(
          context: context,
          section: inspector.detail?.threads,
          fallback: inspector.threads,
          emptyMessage: l10n.noThreadsReported,
          properties: (inspection) => [
            if (inspection.summary case final summary?)
              MeridianProperty(
                label: l10n.summary,
                value:
                    '~${summary.threadCount} threads · ~${summary.machSyscallCount} mach syscalls',
              ),
            for (final thread in inspection.threads)
              MeridianProperty(
                label: 'tid ${thread.threadId}',
                value:
                    '${thread.cpuPercentApproximate ? '~' : ''}${_formatPercent(thread.cpuPercent)} · ${thread.state}',
                monospace: true,
              ),
          ],
        ),
      ],
    );
  }
}

List<MeridianProperty> _securityProperties(
  BuildContext context,
  SecurityDetailInfo security,
) {
  final l10n = context.l10n;
  return [
    MeridianProperty(label: l10n.signing, value: security.signingStatus),
    MeridianProperty(
      label: l10n.authority,
      value: _dashIfEmpty(security.signingAuthority),
    ),
    MeridianProperty(
      label: l10n.teamId,
      value: _dashIfEmpty(security.teamId),
      monospace: true,
    ),
    MeridianProperty(
      label: l10n.bundleId,
      value: _dashIfEmpty(security.bundleId),
      monospace: true,
    ),
    MeridianProperty(
      label: l10n.entitlements,
      value: _dashIfEmpty(security.entitlementsSummary),
    ),
    MeridianProperty(
      label: l10n.origin,
      value: _dashIfEmpty(security.gatekeeperOrigin),
    ),
    MeridianProperty(
      label: l10n.sandbox,
      value: _formatBool(context, security.sandbox),
    ),
    MeridianProperty(
      label: l10n.hardenedRuntime,
      value: _formatBool(context, security.hardenedRuntime),
    ),
    MeridianProperty(label: l10n.architecture, value: security.architecture),
    if (security.rosettaTranslated)
      MeridianProperty(label: l10n.rosetta, value: l10n.yes),
  ];
}

/// A detail section's properties, or the banner that says why there are
/// none.
Widget _detailSection<T>({
  required BuildContext context,
  required ProcessDetailSection<T>? section,
  required InspectorSectionState fallback,
  required String emptyMessage,
  required List<MeridianProperty> Function(T value) properties,
  Widget? Function(T value)? footer,
}) {
  if (section == null) {
    return _StateBanner(state: fallback);
  }

  return switch (section) {
    ProcessDetailAvailable<T>(:final value) => switch (properties(value)) {
      final rows when rows.isEmpty => _StateBanner(
        state: InspectorSectionState(
          availability: InspectorAvailability.available,
          message: emptyMessage,
        ),
      ),
      final rows => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          MeridianPropertyList(properties: rows),
          if (footer?.call(value) case final widget?) ...[
            const SizedBox(height: MeridianSpace.space5),
            widget,
          ],
        ],
      ),
    },
    ProcessDetailRestricted<T>(:final reason) => _StateBanner(
      state: InspectorSectionState(
        availability: InspectorAvailability.requiresPermission,
        message: context.l10n.restrictedByMacos(reason),
      ),
    ),
    ProcessDetailUnsupported<T>(:final reason) => _StateBanner(
      state: InspectorSectionState(
        availability: InspectorAvailability.unsupportedPlatform,
        message: reason,
      ),
    ),
    ProcessDetailNotFound<T>(:final reason) => _StateBanner(
      state: InspectorSectionState(
        availability: InspectorAvailability.unavailable,
        message: reason,
      ),
    ),
  };
}

double _sampleMax(List<double> samples, double currentValue) {
  final historyMax = _finiteMax(samples);
  return math.max(historyMax, currentValue).clamp(0.1, double.infinity);
}

/// The summary tiles at the top of the overview, two per row.
class _MetricTileGrid extends StatelessWidget {
  const _MetricTileGrid({required this.tiles, super.key});

  final List<Widget> tiles;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = (constraints.maxWidth - MeridianSpace.space3) / 2;
        return Wrap(
          spacing: MeridianSpace.space3,
          runSpacing: MeridianSpace.space3,
          children: [
            for (final tile in tiles) SizedBox(width: width, child: tile),
          ],
        );
      },
    );
  }
}

/// A headline metric: an `overline` name over the value in the brand's
/// mono face, on a `pane-alt` inset.
class _MetricTile extends StatelessWidget {
  const _MetricTile({
    required this.label,
    required this.value,
    this.warning = false,
    this.onPressed,
  });

  final String label;
  final String value;

  /// The value crossed its warning threshold.
  final bool warning;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final meridian = context.meridian;
    final colors = meridian.colors;
    final tile = DecoratedBox(
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
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    label.toUpperCase(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: meridian.text.overline.copyWith(
                      color: colors.inkMuted,
                    ),
                  ),
                ),
                if (onPressed != null)
                  MeridianIcon(
                    MeridianIcons.arrowRight,
                    size: MeridianIconSize.small,
                    color: colors.accentInk,
                  ),
              ],
            ),
            const SizedBox(height: MeridianSpace.space2),
            Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: MeridianTextStyles.numeric(
                meridian.text.code.copyWith(
                  fontSize: meridian.text.heading.fontSize,
                  height: meridian.text.heading.height,
                  fontWeight: FontWeight.w600,
                  color: warning ? colors.warning : colors.ink,
                ),
              ),
            ),
          ],
        ),
      ),
    );
    if (onPressed == null) return tile;
    return Semantics(
      button: true,
      label:
          '${context.l10n.networkTelemetryUnavailable}. '
          '${context.l10n.installNetworkTelemetry}',
      child: GestureDetector(onTap: onPressed, child: tile),
    );
  }
}

/// Why a section has nothing to show: restricted by the system, not
/// supported on this platform, or simply empty.
class _StateBanner extends StatelessWidget {
  const _StateBanner({required this.state});

  final InspectorSectionState state;

  @override
  Widget build(BuildContext context) {
    final (tone, icon) = switch (state.availability) {
      InspectorAvailability.available => (
        MeridianBannerTone.info,
        MeridianIcons.info,
      ),
      InspectorAvailability.requiresPermission => (
        MeridianBannerTone.attention,
        MeridianIcons.shieldAlert,
      ),
      InspectorAvailability.unsupportedPlatform => (
        MeridianBannerTone.info,
        MeridianIcons.ban,
      ),
      InspectorAvailability.notImplementedYet => (
        MeridianBannerTone.info,
        MeridianIcons.clock,
      ),
      InspectorAvailability.unavailable => (
        MeridianBannerTone.info,
        MeridianIcons.info,
      ),
    };
    return MeridianBanner(tone: tone, icon: icon, message: state.message);
  }
}

/// What the network banner says and offers: installing the local service,
/// or the install command and guide for a remote host's service.
class _NetworkHint {
  const _NetworkHint({
    required this.title,
    required this.message,
    required this.actionLabel,
    this.onAction,
    this.onGuide,
  });

  final String title;
  final String message;
  final String actionLabel;
  final VoidCallback? onAction;
  final VoidCallback? onGuide;
}

String _portList(BuildContext context, List<int>? ports) {
  if (ports == null) return context.l10n.portsNotReported;
  return ports.isEmpty ? '—' : ports.join(', ');
}
