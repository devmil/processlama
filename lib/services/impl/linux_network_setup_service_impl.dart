import '../../repositories/linux_network_setup_repository.dart';
import '../linux_network_setup_service.dart';

class LinuxNetworkSetupServiceImpl implements LinuxNetworkSetupService {
  LinuxNetworkSetupServiceImpl({required this.repository});

  final LinuxNetworkSetupRepository repository;

  @override
  Future<bool> isAvailable() => repository.isAvailable();

  @override
  Future<void> installOrRepair() async {
    try {
      await repository.installOrRepair();
    } on LinuxNetworkSetupFailure catch (error) {
      throw LinuxNetworkSetupException(error.code);
    }
  }
}
