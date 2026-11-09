import 'package:devmil_logging/devmil_logging.dart';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart';
import 'package:logging/logging.dart';
import 'package:path_provider/path_provider.dart';

import '../../models/models.dart';
import '../../rust/api.dart' as rust_api;
import '../../rust/frb_generated.dart';
import '../process_repository.dart';

class RustProcessRepository implements ProcessRepository {
  static final _log = Logger('RustProcessRepository');

  static Future<void>? _bridgeInitialization;
  static bool _bridgeReady = false;
  final RustProcessSnapshotMapper _snapshotMapper = RustProcessSnapshotMapper();
  var _reportedFirstSnapshot = false;

  @override
  Future<ProcessSnapshot> fetchSnapshot({
    required int pollingIntervalMs,
  }) async {
    try {
      await _ensureBridgeInitialized();
      final snapshot = _snapshotMapper.map(
        await rust_api.collectProcessSnapshot(
          pollingIntervalMs: BigInt.from(pollingIntervalMs),
          knownTopologyVersion: _snapshotMapper.knownTopologyVersion,
        ),
      );
      if (kDebugMode && !_reportedFirstSnapshot) {
        // Cold-launch smoke checks read this line; it carries only a count.
        _reportedFirstSnapshot = true;
        _log.info(
          'first_native_snapshot processes=${snapshot.processes.length}',
        );
      }
      return snapshot;
    } on Object catch (error, stackTrace) {
      _log.fine(
        'Rust core unavailable; using bootstrap snapshot.',
        error,
        stackTrace,
      );
      return _bootstrapSnapshot(error.toString());
    }
  }

  @override
  Future<ProcessDetail> fetchProcessDetail(ProcessIdentity identity) async {
    await _ensureBridgeInitialized();
    return _mapProcessDetail(
      await rust_api.inspectProcessDetail(
        pid: identity.pid,
        startTimeUnixMs: BigInt.from(identity.startTimeUnixMs),
      ),
    );
  }

  @override
  Future<void> sendSignal(
    ProcessIdentity identity,
    ProcessSignal signal,
  ) async {
    await _ensureBridgeInitialized();
    await rust_api.sendProcessSignal(
      pid: identity.pid,
      startTimeUnixMs: BigInt.from(identity.startTimeUnixMs),
      signal: switch (signal) {
        ProcessSignal.terminate => rust_api.ProcessSignalDto.terminate,
        ProcessSignal.kill => rust_api.ProcessSignalDto.kill,
        ProcessSignal.suspend => rust_api.ProcessSignalDto.suspend,
        ProcessSignal.resume => rust_api.ProcessSignalDto.resume,
      },
    );
  }

  Future<void> _ensureBridgeInitialized() async {
    if (_bridgeReady) {
      return;
    }

    final initialization = _bridgeInitialization ??= _initializeBridge();
    try {
      await initialization;
      _bridgeReady = true;
    } on Object {
      _bridgeInitialization = null;
      rethrow;
    }
  }

  Future<void> _initializeBridge() async {
    final candidates = _libraryCandidates();
    final libraryPath = candidates
        .where((file) => file.existsSync())
        .firstOrNull
        ?.path;
    if (libraryPath == null) {
      throw StateError(
        'Could not find processlama_core dynamic library. Tried: '
        '${candidates.map((file) => file.path).join(', ')}',
      );
    }

    await RustLib.init(externalLibrary: ExternalLibrary.open(libraryPath));
    _nativeDiagnostics ??= NativeDiagnosticBridge(
      detach: rust_api.detachNativeDiagnostics,
      drain: rust_api.drainNativeDiagnostics,
      configure: (detailed, clear) =>
          rust_api.configureNativeDiagnostics(detailed: detailed, clear: clear),
    )..start(rust_api.watchNativeDiagnostics());
    await _configureIconCache();
  }

  Future<void> _configureIconCache() async {
    try {
      final cacheDir = await getTemporaryDirectory();
      await rust_api.configureProcessIconCache(
        cacheDir: '${cacheDir.path}/process-icons',
      );
    } on Object catch (error, stackTrace) {
      _log.fine(
        'Failed to configure process icon cache; falling back to Rust default.',
        error,
        stackTrace,
      );
    }
  }

  List<File> _libraryCandidates() {
    return rustCoreLibraryCandidates(
      operatingSystem: Platform.operatingSystem,
      resolvedExecutable: Platform.resolvedExecutable,
    );
  }

  ProcessDetail _mapProcessDetail(rust_api.ProcessDetailDto dto) {
    return ProcessDetail(
      identity: ProcessIdentity(
        pid: dto.identity.pid,
        startTimeUnixMs: dto.identity.startTimeUnixMs.toInt(),
      ),
      files: _mapFileSection(dto.files),
      sockets: _mapSocketSection(dto.sockets),
      threads: _mapThreadSection(dto.threads),
      security: _mapSecuritySection(dto.security),
    );
  }

  ProcessDetailSection<List<FileDescriptorInfo>> _mapFileSection(
    rust_api.FileDetailSectionDto section,
  ) {
    return switch (section) {
      rust_api.FileDetailSectionDto_Available(:final value) =>
        ProcessDetailAvailable(
          value
              .map(
                (file) => FileDescriptorInfo(
                  fd: file.fd,
                  kind: file.kind,
                  path: file.path,
                ),
              )
              .toList(),
        ),
      rust_api.FileDetailSectionDto_Restricted(:final reason) =>
        ProcessDetailRestricted(reason),
      rust_api.FileDetailSectionDto_Unsupported(:final reason) =>
        ProcessDetailUnsupported(reason),
      rust_api.FileDetailSectionDto_NotFound(:final reason) =>
        ProcessDetailNotFound(reason),
    };
  }

  ProcessDetailSection<List<NetworkEndpointInfo>> _mapSocketSection(
    rust_api.SocketDetailSectionDto section,
  ) {
    return switch (section) {
      rust_api.SocketDetailSectionDto_Available(:final value) =>
        ProcessDetailAvailable(
          value
              .map(
                (endpoint) => NetworkEndpointInfo(
                  protocol: endpoint.protocol,
                  localAddress: endpoint.localAddress,
                  localPort: endpoint.localPort,
                  localAddressApproximate: endpoint.localAddressApproximate,
                  remoteAddress: endpoint.remoteAddress,
                  remotePort: endpoint.remotePort,
                  remoteAddressApproximate: endpoint.remoteAddressApproximate,
                  state: endpoint.state,
                ),
              )
              .toList(),
        ),
      rust_api.SocketDetailSectionDto_Restricted(:final reason) =>
        ProcessDetailRestricted(reason),
      rust_api.SocketDetailSectionDto_Unsupported(:final reason) =>
        ProcessDetailUnsupported(reason),
      rust_api.SocketDetailSectionDto_NotFound(:final reason) =>
        ProcessDetailNotFound(reason),
    };
  }

  ProcessDetailSection<ThreadInspectionInfo> _mapThreadSection(
    rust_api.ThreadDetailSectionDto section,
  ) {
    return switch (section) {
      rust_api.ThreadDetailSectionDto_Available(:final value) =>
        ProcessDetailAvailable(
          ThreadInspectionInfo(
            summary: value.summary == null
                ? null
                : TaskSummaryInfo(
                    threadCount: value.summary!.threadCount,
                    machSyscallCount: value.summary!.machSyscallCount,
                    rosettaTranslated: value.summary!.rosettaTranslated,
                  ),
            threads: value.threads
                .map(
                  (thread) => ThreadInfo(
                    threadId: thread.threadId.toInt(),
                    cpuPercent: thread.cpuPercent,
                    cpuPercentApproximate: thread.cpuPercentApproximate,
                    state: thread.state,
                  ),
                )
                .toList(),
          ),
        ),
      rust_api.ThreadDetailSectionDto_Restricted(:final reason) =>
        ProcessDetailRestricted(reason),
      rust_api.ThreadDetailSectionDto_Unsupported(:final reason) =>
        ProcessDetailUnsupported(reason),
      rust_api.ThreadDetailSectionDto_NotFound(:final reason) =>
        ProcessDetailNotFound(reason),
    };
  }

  ProcessDetailSection<SecurityDetailInfo> _mapSecuritySection(
    rust_api.SecurityDetailSectionDto section,
  ) {
    return switch (section) {
      rust_api.SecurityDetailSectionDto_Available(:final value) =>
        ProcessDetailAvailable(
          SecurityDetailInfo(
            signingStatus: value.signingStatus,
            signingAuthority: value.signingAuthority,
            teamId: value.teamId,
            bundleId: value.bundleId,
            entitlementsSummary: value.entitlementsSummary,
            entitlementsApproximate: value.entitlementsApproximate,
            gatekeeperOrigin: value.gatekeeperOrigin,
            sandbox: value.sandbox,
            hardenedRuntime: value.hardenedRuntime,
            architecture: value.architecture,
            rosettaTranslated: value.rosettaTranslated,
          ),
        ),
      rust_api.SecurityDetailSectionDto_Restricted(:final reason) =>
        ProcessDetailRestricted(reason),
      rust_api.SecurityDetailSectionDto_Unsupported(:final reason) =>
        ProcessDetailUnsupported(reason),
      rust_api.SecurityDetailSectionDto_NotFound(:final reason) =>
        ProcessDetailNotFound(reason),
    };
  }

  ProcessSnapshot _bootstrapSnapshot(String reason) {
    return ProcessSnapshot(
      generatedAtUnixMs: DateTime.now().millisecondsSinceEpoch,
      platform: Platform.operatingSystem,
      error: reason,
      processes: <ProcessRecord>[
        ProcessRecord(
          pid: pid,
          ppid: 0,
          uid: 0,
          user: Platform.environment['USER'] ?? '',
          status: ProcessStatus.running,
          rssBytes: 0,
          virtualMemoryBytes: 0,
          cpuTimeNanos: 0,
          threadCount: 0,
          openFileCount: 0,
          nice: 0,
          priority: 0,
          cpuUsage: 0,
          gpuUsage: 0,
          networkInBytesPerSecond: 0,
          networkOutBytesPerSecond: 0,
          totalNetworkInBytes: 0,
          totalNetworkOutBytes: 0,
          treeCpuUsage: 0,
          treeGpuUsage: 0,
          treeRssBytes: 0,
          treeNetworkInBytesPerSecond: 0,
          treeNetworkOutBytesPerSecond: 0,
          descendantCount: 0,
          startTimeUnixMs: 0,
          name: 'ProcessLama',
          executablePath: Platform.resolvedExecutable,
          commandLine: Platform.executableArguments.join(' '),
          appBundlePath: '',
        ),
      ],
    );
  }
}

List<File> rustCoreLibraryCandidates({
  required String operatingSystem,
  required String resolvedExecutable,
}) {
  final exeDir = File(resolvedExecutable).parent.path;
  final contentsDir = Directory(exeDir).parent.path;

  final bundledLibrary = switch (operatingSystem) {
    'macos' => File(
      '$contentsDir/Frameworks/processlama_core.framework/processlama_core',
    ),
    'linux' => File('$exeDir/lib/libprocesslama_core.so'),
    'windows' => File('$exeDir/processlama_core.dll'),
    _ => File(
      '$contentsDir/Frameworks/processlama_core.framework/processlama_core',
    ),
  };

  return <File>[bundledLibrary];
}

/// Stateful native snapshot decoder owned by the repository. It materializes
/// parent/child maps only when Rust sends a new structural version.
class RustProcessSnapshotMapper {
  ProcessTopology? _topology;

  BigInt? get knownTopologyVersion =>
      _topology?.version == null ? null : BigInt.from(_topology!.version!);

  ProcessSnapshot map(rust_api.ProcessSnapshotDto dto) {
    final version = dto.topologyVersion?.toInt();
    var topology = _topology;
    if (version == null) {
      topology = null;
    } else if (dto.topology case final links?) {
      topology = ProcessTopology(
        version: version,
        parents: {
          for (final link in links)
            _identity(link.identity): link.parent == null
                ? null
                : _identity(link.parent!),
        },
      );
    } else if (topology?.version != version) {
      // Request a complete structure again after a missed/invalid response.
      _topology = null;
      throw StateError('Missing process topology for version $version');
    }
    final snapshot = ProcessSnapshot(
      generatedAtUnixMs: dto.generatedAtUnixMs.toInt(),
      platform: dto.platform,
      processes: dto.processes.map(_mapRecord).toList(),
      topology: topology,
    );
    _topology = topology;
    return snapshot;
  }

  ProcessRecord _mapRecord(rust_api.ProcessRecordDto dto) {
    return ProcessRecord(
      pid: dto.pid,
      ppid: dto.ppid,
      uid: dto.uid,
      user: dto.user,
      status: _mapStatus(dto.status),
      rssBytes: dto.rssBytes.toInt(),
      virtualMemoryBytes: dto.virtualMemoryBytes.toInt(),
      cpuTimeNanos: dto.cpuTimeNanos.toInt(),
      threadCount: dto.threadCount,
      openFileCount: dto.openFileCount,
      localPorts: dto.localPorts?.toList(),
      listeningPorts: dto.listeningPorts?.toList(),
      nice: dto.nice,
      priority: dto.priority,
      cpuUsage: dto.cpuUsage,
      gpuUsage: dto.gpuUsage,
      networkInBytesPerSecond: dto.networkInBytesPerSecond,
      networkOutBytesPerSecond: dto.networkOutBytesPerSecond,
      totalNetworkInBytes: dto.totalNetworkInBytes.toInt(),
      totalNetworkOutBytes: dto.totalNetworkOutBytes.toInt(),
      storageReadBytesPerSecond: dto.storageReadBytesPerSecond,
      storageWriteBytesPerSecond: dto.storageWriteBytesPerSecond,
      totalStorageReadBytes: dto.totalStorageReadBytes.toInt(),
      totalStorageWriteBytes: dto.totalStorageWriteBytes.toInt(),
      storageIoAvailable: dto.storageIoAvailable,
      treeCpuUsage: dto.treeCpuUsage,
      treeGpuUsage: dto.treeGpuUsage,
      treeRssBytes: dto.treeRssBytes.toInt(),
      treeNetworkInBytesPerSecond: dto.treeNetworkInBytesPerSecond,
      treeNetworkOutBytesPerSecond: dto.treeNetworkOutBytesPerSecond,
      treeStorageReadBytesPerSecond: dto.treeStorageReadBytesPerSecond,
      treeStorageWriteBytesPerSecond: dto.treeStorageWriteBytesPerSecond,
      treeStorageIoAvailable: dto.treeStorageIoAvailable,
      descendantCount: dto.descendantCount.toInt(),
      startTimeUnixMs: dto.startTimeUnixMs.toInt(),
      name: dto.name,
      executablePath: dto.executablePath,
      commandLine: dto.commandLine,
      appBundlePath: dto.appBundlePath,
      iconUri: dto.iconUri,
    );
  }

  ProcessStatus _mapStatus(rust_api.ProcessStatusDto status) {
    return switch (status) {
      rust_api.ProcessStatusDto.running => ProcessStatus.running,
      rust_api.ProcessStatusDto.sleeping => ProcessStatus.sleeping,
      rust_api.ProcessStatusDto.stopped => ProcessStatus.stopped,
      rust_api.ProcessStatusDto.zombie => ProcessStatus.zombie,
      rust_api.ProcessStatusDto.unknown => ProcessStatus.unknown,
    };
  }

  ProcessIdentity _identity(rust_api.ProcessIdentityDto identity) =>
      ProcessIdentity(
        pid: identity.pid,
        startTimeUnixMs: identity.startTimeUnixMs.toInt(),
      );
}

NativeDiagnosticBridge? _nativeDiagnostics;
