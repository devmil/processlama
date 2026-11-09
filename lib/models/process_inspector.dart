import 'package:flutter/foundation.dart';

import 'process_identity.dart';
import 'process_detail.dart';
import 'process_ports.dart';
import 'process_record.dart';
import 'process_tree.dart';

enum InspectorAvailability {
  available,
  requiresPermission,
  unsupportedPlatform,
  notImplementedYet,
  unavailable,
}

class InspectorSectionState {
  const InspectorSectionState({
    required this.availability,
    required this.message,
  });

  final InspectorAvailability availability;
  final String message;
}

class ProcessInspectorView {
  const ProcessInspectorView({
    required this.process,
    required this.identity,
    required this.changeMarker,
    required this.iconPath,
    this.iconUpdates,
    this.ports,
    this.treePorts,
    this.listenerOwnersByPort = const {},
    required this.platform,
    required this.detail,
    required this.overview,
    required this.openFiles,
    required this.sockets,
    required this.network,
    required this.threads,
    required this.security,
  });

  factory ProcessInspectorView.empty() {
    const state = InspectorSectionState(
      availability: InspectorAvailability.unavailable,
      message: 'Select a process to inspect it.',
    );
    return const ProcessInspectorView(
      process: null,
      identity: null,
      changeMarker: ProcessChangeMarker.none,
      iconPath: null,
      platform: 'unknown',
      detail: null,
      overview: state,
      openFiles: state,
      sockets: state,
      network: state,
      threads: state,
      security: state,
    );
  }

  /// Ports of the selected process; null when ownership is not reported.
  final ProcessPorts? ports;

  /// Ports of the selected process and all its descendants. Null when no
  /// process in the subtree has reported port ownership.
  final ProcessPorts? treePorts;

  /// Other processes listening on the remote ports of the selected
  /// process's loopback sockets, so a socket can link to its peer.
  final Map<int, List<ProcessPortOwner>> listenerOwnersByPort;

  final ProcessRecord? process;
  final ProcessIdentity? identity;
  final ProcessChangeMarker changeMarker;
  final String? iconPath;

  /// Follows a remote icon that arrives after publication.
  final ValueListenable<String?>? iconUpdates;
  final String platform;
  final ProcessDetail? detail;
  final InspectorSectionState overview;
  final InspectorSectionState openFiles;
  final InspectorSectionState sockets;
  final InspectorSectionState network;
  final InspectorSectionState threads;
  final InspectorSectionState security;
}
