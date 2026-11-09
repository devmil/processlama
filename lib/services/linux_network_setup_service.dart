abstract class LinuxNetworkSetupService {
  static const availabilityPollInterval = Duration(seconds: 3);

  Future<bool> isAvailable();
  Future<void> installOrRepair();
}

class LinuxNetworkSetupException implements Exception {
  const LinuxNetworkSetupException(this.code);

  final String code;
}
