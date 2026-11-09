import '../models/models.dart';

/// Persists the `remoteHosts.v1` value. Implemented by the settings
/// repository and owned by the settings service.
abstract interface class RemoteHostsSettingsRepository {
  Future<RemoteHostsState> getRemoteHosts();

  Future<void> saveRemoteHosts(RemoteHostsState state);
}

/// Keeps the value in memory, for hosts without persistent settings.
final class MemoryRemoteHostsSettingsRepository
    implements RemoteHostsSettingsRepository {
  RemoteHostsState _state = const RemoteHostsState();

  @override
  Future<RemoteHostsState> getRemoteHosts() async => _state;

  @override
  Future<void> saveRemoteHosts(RemoteHostsState state) async => _state = state;
}
