import 'package:flutter/foundation.dart';

/// Where per-process network rates come from on a host.
enum NetworkRateSource { ebpf, nettop, helper, none }

/// Why network rates are unavailable, when [NetworkRateSource.none].
enum NetworkUnavailableReason { serviceNotInstalled, unsupported, restricted }

/// Operating systems a process source can describe.
enum HostOperatingSystem { macos, linux, windows, unknown }

/// What a process source can show. Remote tabs take these from the helper's
/// `hello`; the local tab derives them from the running platform. Features
/// are never decided from the client's own platform for a remote host.
@immutable
class HostCapabilities {
  const HostCapabilities({
    required this.operatingSystem,
    this.gpu = false,
    this.storageIo = false,
    this.networkSource = NetworkRateSource.none,
    this.networkUnavailableReason,
    this.signals = false,
    this.inspectorFiles = false,
    this.inspectorSockets = false,
    this.inspectorThreads = false,
    this.inspectorSecurity = false,
    this.icons = false,
    this.hidepid = false,
  });

  /// Nothing is known yet, for example before a remote helper said hello.
  static const unknown = HostCapabilities(
    operatingSystem: HostOperatingSystem.unknown,
  );

  /// The capabilities of this computer's own telemetry core.
  factory HostCapabilities.local(TargetPlatform platform) {
    return switch (platform) {
      TargetPlatform.macOS => const HostCapabilities(
        operatingSystem: HostOperatingSystem.macos,
        gpu: true,
        storageIo: true,
        networkSource: NetworkRateSource.nettop,
        signals: true,
        inspectorFiles: true,
        inspectorSockets: true,
        inspectorThreads: true,
        inspectorSecurity: true,
        icons: true,
      ),
      TargetPlatform.linux => const HostCapabilities(
        operatingSystem: HostOperatingSystem.linux,
        gpu: true,
        storageIo: true,
        networkSource: NetworkRateSource.ebpf,
        signals: true,
        inspectorFiles: true,
        inspectorSockets: true,
        inspectorThreads: true,
        icons: true,
      ),
      TargetPlatform.windows => const HostCapabilities(
        operatingSystem: HostOperatingSystem.windows,
        inspectorSockets: true,
        gpu: true,
        storageIo: true,
        networkSource: NetworkRateSource.helper,
        signals: true,
        inspectorThreads: true,
        icons: true,
      ),
      _ => unknown,
    };
  }

  final HostOperatingSystem operatingSystem;
  final bool gpu;
  final bool storageIo;
  final NetworkRateSource networkSource;
  final NetworkUnavailableReason? networkUnavailableReason;
  final bool signals;
  final bool inspectorFiles;
  final bool inspectorSockets;
  final bool inspectorThreads;
  final bool inspectorSecurity;
  final bool icons;

  /// Linux `hidepid`: only the connecting account's processes are visible.
  final bool hidepid;

  @override
  bool operator ==(Object other) =>
      other is HostCapabilities &&
      other.operatingSystem == operatingSystem &&
      other.gpu == gpu &&
      other.storageIo == storageIo &&
      other.networkSource == networkSource &&
      other.networkUnavailableReason == networkUnavailableReason &&
      other.signals == signals &&
      other.inspectorFiles == inspectorFiles &&
      other.inspectorSockets == inspectorSockets &&
      other.inspectorThreads == inspectorThreads &&
      other.inspectorSecurity == inspectorSecurity &&
      other.icons == icons &&
      other.hidepid == hidepid;

  @override
  int get hashCode => Object.hash(
    operatingSystem,
    gpu,
    storageIo,
    networkSource,
    networkUnavailableReason,
    signals,
    inspectorFiles,
    inspectorSockets,
    inspectorThreads,
    inspectorSecurity,
    icons,
    hidepid,
  );
}
