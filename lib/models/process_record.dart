import 'process_icon_ref.dart';
import 'process_identity.dart';

enum ProcessStatus {
  running,
  sleeping,
  stopped,
  zombie,
  unknown;

  static ProcessStatus fromJson(String? value) {
    return switch (value) {
      'running' => ProcessStatus.running,
      'sleeping' => ProcessStatus.sleeping,
      'stopped' => ProcessStatus.stopped,
      'zombie' => ProcessStatus.zombie,
      _ => ProcessStatus.unknown,
    };
  }
}

class ProcessRecord {
  const ProcessRecord({
    required this.pid,
    required this.ppid,
    required this.uid,
    required this.user,
    required this.status,
    required this.rssBytes,
    required this.virtualMemoryBytes,
    required this.cpuTimeNanos,
    required this.threadCount,
    required this.openFileCount,
    this.localPorts,
    this.listeningPorts,
    required this.nice,
    required this.priority,
    required this.cpuUsage,
    required this.gpuUsage,
    required this.networkInBytesPerSecond,
    required this.networkOutBytesPerSecond,
    required this.totalNetworkInBytes,
    required this.totalNetworkOutBytes,
    this.storageReadBytesPerSecond = 0,
    this.storageWriteBytesPerSecond = 0,
    this.totalStorageReadBytes = 0,
    this.totalStorageWriteBytes = 0,
    this.storageIoAvailable = false,
    this.treeCpuUsage = 0,
    this.treeGpuUsage = 0,
    this.treeRssBytes = 0,
    this.treeNetworkInBytesPerSecond = 0,
    this.treeNetworkOutBytesPerSecond = 0,
    this.treeStorageReadBytesPerSecond = 0,
    this.treeStorageWriteBytesPerSecond = 0,
    this.treeStorageIoAvailable = false,
    this.descendantCount = 0,
    required this.startTimeUnixMs,
    required this.name,
    required this.executablePath,
    required this.commandLine,
    required this.appBundlePath,
    this.iconUri,
    this._iconRef,
  });

  factory ProcessRecord.fromJson(Map<String, Object?> json) {
    return ProcessRecord(
      pid: (json['pid'] as num?)?.toInt() ?? 0,
      ppid: (json['ppid'] as num?)?.toInt() ?? 0,
      uid: (json['uid'] as num?)?.toInt() ?? 0,
      user: json['user'] as String? ?? '',
      status: ProcessStatus.fromJson(json['status'] as String?),
      rssBytes: (json['rss_bytes'] as num?)?.toInt() ?? 0,
      virtualMemoryBytes: (json['virtual_memory_bytes'] as num?)?.toInt() ?? 0,
      cpuTimeNanos: (json['cpu_time_nanos'] as num?)?.toInt() ?? 0,
      threadCount: (json['thread_count'] as num?)?.toInt() ?? 0,
      openFileCount: (json['open_file_count'] as num?)?.toInt() ?? 0,
      localPorts: (json['local_ports'] as List<Object?>?)?.cast<int>(),
      listeningPorts: (json['listening_ports'] as List<Object?>?)?.cast<int>(),
      nice: (json['nice'] as num?)?.toInt() ?? 0,
      priority: (json['priority'] as num?)?.toInt() ?? 0,
      cpuUsage: (json['cpu_usage'] as num?)?.toDouble() ?? 0,
      gpuUsage: (json['gpu_usage'] as num?)?.toDouble() ?? 0,
      networkInBytesPerSecond:
          (json['network_in_bytes_per_second'] as num?)?.toDouble() ?? 0,
      networkOutBytesPerSecond:
          (json['network_out_bytes_per_second'] as num?)?.toDouble() ?? 0,
      totalNetworkInBytes:
          (json['total_network_in_bytes'] as num?)?.toInt() ?? 0,
      totalNetworkOutBytes:
          (json['total_network_out_bytes'] as num?)?.toInt() ?? 0,
      storageReadBytesPerSecond:
          (json['storage_read_bytes_per_second'] as num?)?.toDouble() ?? 0,
      storageWriteBytesPerSecond:
          (json['storage_write_bytes_per_second'] as num?)?.toDouble() ?? 0,
      totalStorageReadBytes:
          (json['total_storage_read_bytes'] as num?)?.toInt() ?? 0,
      totalStorageWriteBytes:
          (json['total_storage_write_bytes'] as num?)?.toInt() ?? 0,
      storageIoAvailable: json['storage_io_available'] as bool? ?? false,
      treeCpuUsage:
          (json['tree_cpu_usage'] as num?)?.toDouble() ??
          (json['tree_cpu_percent'] as num?)?.toDouble() ??
          0,
      treeGpuUsage:
          (json['tree_gpu_usage'] as num?)?.toDouble() ??
          (json['tree_gpu_percent'] as num?)?.toDouble() ??
          0,
      treeRssBytes: (json['tree_rss_bytes'] as num?)?.toInt() ?? 0,
      treeNetworkInBytesPerSecond:
          (json['tree_network_in_bytes_per_second'] as num?)?.toDouble() ?? 0,
      treeNetworkOutBytesPerSecond:
          (json['tree_network_out_bytes_per_second'] as num?)?.toDouble() ?? 0,
      treeStorageReadBytesPerSecond:
          (json['tree_storage_read_bytes_per_second'] as num?)?.toDouble() ?? 0,
      treeStorageWriteBytesPerSecond:
          (json['tree_storage_write_bytes_per_second'] as num?)?.toDouble() ??
          0,
      treeStorageIoAvailable:
          json['tree_storage_io_available'] as bool? ?? false,
      descendantCount: (json['descendant_count'] as num?)?.toInt() ?? 0,
      startTimeUnixMs: (json['start_time_unix_ms'] as num?)?.toInt() ?? 0,
      name: json['name'] as String? ?? 'Unknown',
      executablePath: json['executable_path'] as String? ?? '',
      commandLine: json['command_line'] as String? ?? '',
      appBundlePath: json['app_bundle_path'] as String? ?? '',
      iconUri: json['icon_uri'] as String?,
      iconRef: switch (json['icon_sha256']) {
        final String sha256 => ProcessIconRef.remote(sha256),
        _ => null,
      },
    );
  }

  final int pid;
  final int ppid;
  final int uid;
  final String user;
  final ProcessStatus status;
  final int rssBytes;
  final int virtualMemoryBytes;
  final int cpuTimeNanos;
  final int threadCount;
  final int openFileCount;

  /// Local TCP/UDP ports reported by the host; null when unavailable.
  final List<int>? localPorts;

  /// The subset of [localPorts] this process serves on: TCP listeners and UDP
  /// sockets bound to a well-known port. Null when unavailable.
  final List<int>? listeningPorts;
  final int nice;
  final int priority;
  final double cpuUsage;
  final double gpuUsage;
  final double networkInBytesPerSecond;
  final double networkOutBytesPerSecond;
  final int totalNetworkInBytes;
  final int totalNetworkOutBytes;
  final double storageReadBytesPerSecond;
  final double storageWriteBytesPerSecond;
  final int totalStorageReadBytes;
  final int totalStorageWriteBytes;
  final bool storageIoAvailable;
  final double treeCpuUsage;
  final double treeGpuUsage;
  final int treeRssBytes;
  final double treeNetworkInBytesPerSecond;
  final double treeNetworkOutBytesPerSecond;
  final double treeStorageReadBytesPerSecond;
  final double treeStorageWriteBytesPerSecond;
  final bool treeStorageIoAvailable;
  final int descendantCount;
  final int startTimeUnixMs;
  final String name;
  final String executablePath;
  final String commandLine;
  final String appBundlePath;
  final String? iconUri;
  final ProcessIconRef? _iconRef;

  /// The icon source at the model boundary: a remote content hash, or the
  /// local file the native core rendered.
  ProcessIconRef? get iconRef =>
      _iconRef ?? (iconUri == null ? null : ProcessIconRef.file(iconUri!));

  String get displayName {
    final executableName = _basename(executablePath);
    if (appBundlePath.isEmpty || executableName.isEmpty) {
      return name;
    }

    final bundleName = _bundleDisplayName(appBundlePath);
    final normalizedExecutableName = _normalizeExecutableName(executableName);
    final normalizedBundleName = _normalizeExecutableName(bundleName);
    final normalizedName = _normalizeExecutableName(name);

    if (_isDirectBundleExecutable(
          executablePath: executablePath,
          appBundlePath: appBundlePath,
        ) ||
        normalizedExecutableName == normalizedBundleName ||
        normalizedExecutableName == normalizedName) {
      return name;
    }

    return executableName;
  }

  ProcessIdentity get identity {
    return ProcessIdentity(pid: pid, startTimeUnixMs: startTimeUnixMs);
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'pid': pid,
      'ppid': ppid,
      'uid': uid,
      'user': user,
      'status': status.name,
      'rss_bytes': rssBytes,
      'virtual_memory_bytes': virtualMemoryBytes,
      'cpu_time_nanos': cpuTimeNanos,
      'thread_count': threadCount,
      'open_file_count': openFileCount,
      'local_ports': localPorts,
      'listening_ports': listeningPorts,
      'nice': nice,
      'priority': priority,
      'cpu_usage': cpuUsage,
      'gpu_usage': gpuUsage,
      'network_in_bytes_per_second': networkInBytesPerSecond,
      'network_out_bytes_per_second': networkOutBytesPerSecond,
      'total_network_in_bytes': totalNetworkInBytes,
      'total_network_out_bytes': totalNetworkOutBytes,
      'storage_read_bytes_per_second': storageReadBytesPerSecond,
      'storage_write_bytes_per_second': storageWriteBytesPerSecond,
      'total_storage_read_bytes': totalStorageReadBytes,
      'total_storage_write_bytes': totalStorageWriteBytes,
      'storage_io_available': storageIoAvailable,
      'tree_cpu_usage': treeCpuUsage,
      'tree_gpu_usage': treeGpuUsage,
      'tree_rss_bytes': treeRssBytes,
      'tree_network_in_bytes_per_second': treeNetworkInBytesPerSecond,
      'tree_network_out_bytes_per_second': treeNetworkOutBytesPerSecond,
      'tree_storage_read_bytes_per_second': treeStorageReadBytesPerSecond,
      'tree_storage_write_bytes_per_second': treeStorageWriteBytesPerSecond,
      'tree_storage_io_available': treeStorageIoAvailable,
      'descendant_count': descendantCount,
      'start_time_unix_ms': startTimeUnixMs,
      'name': name,
      'executable_path': executablePath,
      'command_line': commandLine,
      'app_bundle_path': appBundlePath,
      'icon_uri': iconUri,
      if (_iconRef case ProcessRemoteIcon(:final sha256)) 'icon_sha256': sha256,
    };
  }

  ProcessRecord copyWith({
    int? pid,
    int? ppid,
    int? uid,
    String? user,
    ProcessStatus? status,
    int? rssBytes,
    int? virtualMemoryBytes,
    int? cpuTimeNanos,
    int? threadCount,
    int? openFileCount,
    List<int>? localPorts,
    List<int>? listeningPorts,
    int? nice,
    int? priority,
    double? cpuUsage,
    double? gpuUsage,
    double? networkInBytesPerSecond,
    double? networkOutBytesPerSecond,
    int? totalNetworkInBytes,
    int? totalNetworkOutBytes,
    double? storageReadBytesPerSecond,
    double? storageWriteBytesPerSecond,
    int? totalStorageReadBytes,
    int? totalStorageWriteBytes,
    bool? storageIoAvailable,
    double? treeCpuUsage,
    double? treeGpuUsage,
    int? treeRssBytes,
    double? treeNetworkInBytesPerSecond,
    double? treeNetworkOutBytesPerSecond,
    double? treeStorageReadBytesPerSecond,
    double? treeStorageWriteBytesPerSecond,
    bool? treeStorageIoAvailable,
    int? descendantCount,
    int? startTimeUnixMs,
    String? name,
    String? executablePath,
    String? commandLine,
    String? appBundlePath,
    String? iconUri,
    ProcessIconRef? iconRef,
  }) {
    return ProcessRecord(
      pid: pid ?? this.pid,
      ppid: ppid ?? this.ppid,
      uid: uid ?? this.uid,
      user: user ?? this.user,
      status: status ?? this.status,
      rssBytes: rssBytes ?? this.rssBytes,
      virtualMemoryBytes: virtualMemoryBytes ?? this.virtualMemoryBytes,
      cpuTimeNanos: cpuTimeNanos ?? this.cpuTimeNanos,
      threadCount: threadCount ?? this.threadCount,
      openFileCount: openFileCount ?? this.openFileCount,
      localPorts: localPorts ?? this.localPorts,
      listeningPorts: listeningPorts ?? this.listeningPorts,
      nice: nice ?? this.nice,
      priority: priority ?? this.priority,
      cpuUsage: cpuUsage ?? this.cpuUsage,
      gpuUsage: gpuUsage ?? this.gpuUsage,
      networkInBytesPerSecond:
          networkInBytesPerSecond ?? this.networkInBytesPerSecond,
      networkOutBytesPerSecond:
          networkOutBytesPerSecond ?? this.networkOutBytesPerSecond,
      totalNetworkInBytes: totalNetworkInBytes ?? this.totalNetworkInBytes,
      totalNetworkOutBytes: totalNetworkOutBytes ?? this.totalNetworkOutBytes,
      storageReadBytesPerSecond:
          storageReadBytesPerSecond ?? this.storageReadBytesPerSecond,
      storageWriteBytesPerSecond:
          storageWriteBytesPerSecond ?? this.storageWriteBytesPerSecond,
      totalStorageReadBytes:
          totalStorageReadBytes ?? this.totalStorageReadBytes,
      totalStorageWriteBytes:
          totalStorageWriteBytes ?? this.totalStorageWriteBytes,
      storageIoAvailable: storageIoAvailable ?? this.storageIoAvailable,
      treeCpuUsage: treeCpuUsage ?? this.treeCpuUsage,
      treeGpuUsage: treeGpuUsage ?? this.treeGpuUsage,
      treeRssBytes: treeRssBytes ?? this.treeRssBytes,
      treeNetworkInBytesPerSecond:
          treeNetworkInBytesPerSecond ?? this.treeNetworkInBytesPerSecond,
      treeNetworkOutBytesPerSecond:
          treeNetworkOutBytesPerSecond ?? this.treeNetworkOutBytesPerSecond,
      treeStorageReadBytesPerSecond:
          treeStorageReadBytesPerSecond ?? this.treeStorageReadBytesPerSecond,
      treeStorageWriteBytesPerSecond:
          treeStorageWriteBytesPerSecond ?? this.treeStorageWriteBytesPerSecond,
      treeStorageIoAvailable:
          treeStorageIoAvailable ?? this.treeStorageIoAvailable,
      descendantCount: descendantCount ?? this.descendantCount,
      startTimeUnixMs: startTimeUnixMs ?? this.startTimeUnixMs,
      name: name ?? this.name,
      executablePath: executablePath ?? this.executablePath,
      commandLine: commandLine ?? this.commandLine,
      appBundlePath: appBundlePath ?? this.appBundlePath,
      iconUri: iconUri ?? this.iconUri,
      iconRef: iconRef ?? _iconRef,
    );
  }
}

String _basename(String path) {
  final normalized = path.replaceAll(r'\', '/');
  final trimmed = normalized.endsWith('/')
      ? normalized.substring(0, normalized.length - 1)
      : normalized;
  final separator = trimmed.lastIndexOf('/');
  return separator == -1 ? trimmed : trimmed.substring(separator + 1);
}

String _bundleDisplayName(String appBundlePath) {
  final bundleDirectory = _basename(appBundlePath);
  return bundleDirectory.endsWith('.app')
      ? bundleDirectory.substring(0, bundleDirectory.length - 4)
      : bundleDirectory;
}

bool _isDirectBundleExecutable({
  required String executablePath,
  required String appBundlePath,
}) {
  final normalizedExecutablePath = executablePath.replaceAll(r'\', '/');
  final normalizedBundlePath = appBundlePath.replaceAll(r'\', '/');
  final bundleExecutableDirectory = normalizedBundlePath.endsWith('/')
      ? '${normalizedBundlePath}Contents/MacOS/'
      : '$normalizedBundlePath/Contents/MacOS/';

  if (!normalizedExecutablePath.startsWith(bundleExecutableDirectory)) {
    return false;
  }

  final relativePath = normalizedExecutablePath.substring(
    bundleExecutableDirectory.length,
  );
  return relativePath.isNotEmpty && !relativePath.contains('/');
}

String _normalizeExecutableName(String value) {
  return value.toLowerCase().replaceAll(RegExp(r'[\s._-]+'), '');
}
