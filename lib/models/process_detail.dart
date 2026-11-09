import 'process_identity.dart';

sealed class ProcessDetailSection<T> {
  const ProcessDetailSection();
}

class ProcessDetailAvailable<T> extends ProcessDetailSection<T> {
  const ProcessDetailAvailable(this.value);

  final T value;
}

class ProcessDetailRestricted<T> extends ProcessDetailSection<T> {
  const ProcessDetailRestricted(this.reason);

  final String reason;
}

class ProcessDetailUnsupported<T> extends ProcessDetailSection<T> {
  const ProcessDetailUnsupported(this.reason);

  final String reason;
}

class ProcessDetailNotFound<T> extends ProcessDetailSection<T> {
  const ProcessDetailNotFound(this.reason);

  final String reason;
}

class ProcessDetail {
  const ProcessDetail({
    required this.identity,
    required this.files,
    required this.sockets,
    required this.threads,
    required this.security,
  });

  final ProcessIdentity identity;
  final ProcessDetailSection<List<FileDescriptorInfo>> files;
  final ProcessDetailSection<List<NetworkEndpointInfo>> sockets;
  final ProcessDetailSection<ThreadInspectionInfo> threads;
  final ProcessDetailSection<SecurityDetailInfo> security;
}

class FileDescriptorInfo {
  const FileDescriptorInfo({
    required this.fd,
    required this.kind,
    required this.path,
  });

  final int fd;
  final String kind;
  final String path;
}

class NetworkEndpointInfo {
  const NetworkEndpointInfo({
    required this.protocol,
    required this.localAddress,
    required this.localPort,
    required this.localAddressApproximate,
    required this.remoteAddress,
    required this.remotePort,
    required this.remoteAddressApproximate,
    required this.state,
  });

  final String protocol;
  final String localAddress;
  final int localPort;
  final bool localAddressApproximate;
  final String remoteAddress;
  final int remotePort;
  final bool remoteAddressApproximate;
  final String state;
}

class ThreadInspectionInfo {
  const ThreadInspectionInfo({required this.summary, required this.threads});

  final TaskSummaryInfo? summary;
  final List<ThreadInfo> threads;
}

class TaskSummaryInfo {
  const TaskSummaryInfo({
    required this.threadCount,
    required this.machSyscallCount,
    required this.rosettaTranslated,
  });

  final int threadCount;
  final int machSyscallCount;
  final bool rosettaTranslated;
}

class ThreadInfo {
  const ThreadInfo({
    required this.threadId,
    required this.cpuPercent,
    required this.cpuPercentApproximate,
    required this.state,
  });

  final int threadId;
  final double cpuPercent;
  final bool cpuPercentApproximate;
  final String state;
}

class SecurityDetailInfo {
  const SecurityDetailInfo({
    required this.signingStatus,
    required this.signingAuthority,
    required this.teamId,
    required this.bundleId,
    required this.entitlementsSummary,
    required this.entitlementsApproximate,
    required this.gatekeeperOrigin,
    required this.sandbox,
    required this.hardenedRuntime,
    required this.architecture,
    required this.rosettaTranslated,
  });

  final String signingStatus;
  final String signingAuthority;
  final String teamId;
  final String bundleId;
  final String entitlementsSummary;
  final bool entitlementsApproximate;
  final String gatekeeperOrigin;
  final bool sandbox;
  final bool hardenedRuntime;
  final String architecture;
  final bool rosettaTranslated;
}
