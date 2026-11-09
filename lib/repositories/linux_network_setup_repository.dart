abstract class LinuxNetworkSetupRepository {
  Future<bool> isAvailable();
  Future<void> installOrRepair();
}

class LinuxNetworkSetupFailure implements Exception {
  const LinuxNetworkSetupFailure(this.code);

  final String code;
}
