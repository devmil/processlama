import '../models/models.dart';

enum ProcessSignal { terminate, kill, suspend, resume }

abstract interface class ProcessRepository {
  Future<ProcessSnapshot> fetchSnapshot({required int pollingIntervalMs});
  Future<ProcessDetail> fetchProcessDetail(ProcessIdentity identity);
  Future<void> sendSignal(ProcessIdentity identity, ProcessSignal signal);
}
