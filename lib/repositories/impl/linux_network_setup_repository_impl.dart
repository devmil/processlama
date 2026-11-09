import 'dart:io';

import '../linux_network_setup_repository.dart';

class LinuxNetworkSetupRepositoryImpl implements LinuxNetworkSetupRepository {
  /// Shared with the Rust engine and the network helper through
  /// `fixtures/linux_network_snapshot_path.txt`.
  static const snapshotPath = '/run/processlama/network.json';
  static const _maximumSnapshotAge = Duration(seconds: 5);

  @override
  Future<bool> isAvailable() async {
    try {
      final modified = await File(snapshotPath).lastModified();
      final age = DateTime.now().difference(modified);
      return !age.isNegative && age <= _maximumSnapshotAge;
    } on FileSystemException {
      return false;
    }
  }

  @override
  Future<void> installOrRepair() async {
    final executable = await File(
      Platform.resolvedExecutable,
    ).resolveSymbolicLinks();
    final installer = File(
      '${File(executable).parent.path}/network/install-network-service.sh',
    );
    if (!await installer.exists()) {
      throw const LinuxNetworkSetupFailure('installerMissing');
    }

    ProcessResult result;
    try {
      result = await Process.run('pkexec', [installer.path]);
    } on ProcessException {
      throw const LinuxNetworkSetupFailure('authorizationUnavailable');
    }
    if (result.exitCode != 0) {
      throw LinuxNetworkSetupFailure(
        result.exitCode == 126 ? 'authorizationCancelled' : 'installFailed',
      );
    }
  }
}
