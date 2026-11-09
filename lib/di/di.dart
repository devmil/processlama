import 'dart:async';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';

import '../repositories/impl/settings_repository_impl.dart';
import '../repositories/impl/file_snapshot_repository.dart';
import '../repositories/impl/linux_network_setup_repository_impl.dart';
import 'package:path_provider/path_provider.dart';

import '../repositories/impl/remote/bundled_remote_helper_repository.dart';
import '../repositories/impl/remote/file_remote_icon_cache_repository.dart';
import '../repositories/impl/remote/ssh_remote_connection_repository.dart';
import '../repositories/impl/rust_process_repository.dart';
import '../repositories/repositories.dart';
import '../services/impl/process_service_impl.dart';
import '../services/impl/process_session_factory_impl.dart';
import '../services/impl/workspace_tabs_service_impl.dart';
import '../services/impl/linux_network_setup_service_impl.dart';
import '../services/impl/platform_app_update_service.dart';
import '../services/impl/process_icon_service_impl.dart';
import '../services/impl/remote_host_service_impl.dart';
import '../services/impl/settings_workspace_tabs_store.dart';
import '../services/impl/repository_operation_tracker_impl.dart';
import '../services/impl/settings_service_impl.dart';
import '../services/services.dart';
import 'component_creation_info.dart';

final _componentDefinitions =
    <Type, ({int nr, ComponentCreationInfo<dynamic, dynamic> creationInfo})>{};

bool _componentsRegistered = false;
bool _componentsInitialized = false;

Widget createComponentProviderTree({required Widget child}) {
  _ensureComponents();

  return MultiProvider(
    providers: _componentDefinitions.values
        .map((definition) => definition.creationInfo.provider)
        .toList(),
    child: child,
  );
}

Future<void> initializeComponents({bool forTest = false}) async {
  _ensureComponents();

  if (_componentsInitialized) {
    return;
  }

  _componentsInitialized = true;

  final components = [..._componentDefinitions.values]
    ..sort((left, right) => left.nr.compareTo(right.nr));

  for (final component in components) {
    if (forTest &&
        (component.creationInfo.contractType == ProcessService ||
            component.creationInfo.contractType == AppUpdateService)) {
      continue;
    }
    await component.creationInfo.maybeExecuteInitializer();
  }
}

T getComponentFor<T>() {
  _ensureComponents();

  final definition = _componentDefinitions[T];
  if (definition == null) {
    throw StateError('Component not registered for type $T');
  }

  return definition.creationInfo.instance as T;
}

void _ensureComponents() {
  if (_componentsRegistered) {
    return;
  }

  _componentsRegistered = true;

  _registerComponent(
    ComponentCreationInfo<
      RepositoryOperationTracker,
      RepositoryOperationTrackerImpl
    >(creator: () => RepositoryOperationTrackerImpl()),
  );
  _registerComponent(
    ComponentCreationInfo<SettingsRepository, SettingsRepositoryImpl>(
      creator: () => SettingsRepositoryImpl(),
    ),
  );
  _registerComponent(
    ComponentCreationInfo<SettingsService, SettingsServiceImpl>(
      creator: () => SettingsServiceImpl(
        settingsRepository: getComponentFor<SettingsRepository>(),
      ),
      initializer: (service) => service.initialize(),
    ),
  );
  _registerComponent(
    ComponentCreationInfo<RemoteHostsSettings, SettingsServiceImpl>(
      // The settings service owns the remote hosts section of the settings.
      creator: () => getComponentFor<SettingsService>() as SettingsServiceImpl,
    ),
  );
  _registerComponent(
    ComponentCreationInfo<AppUpdateService, PlatformAppUpdateService>(
      creator: () => PlatformAppUpdateService(
        settingsService: getComponentFor<SettingsService>(),
      ),
      initializer: (service) => service.initialize(),
    ),
  );
  _registerComponent(
    ComponentCreationInfo<ProcessRepository, RustProcessRepository>(
      creator: () => RustProcessRepository(),
    ),
  );
  _registerComponent(
    ComponentCreationInfo<
      LinuxNetworkSetupRepository,
      LinuxNetworkSetupRepositoryImpl
    >(creator: () => LinuxNetworkSetupRepositoryImpl()),
  );
  _registerComponent(
    ComponentCreationInfo<
      LinuxNetworkSetupService,
      LinuxNetworkSetupServiceImpl
    >(
      creator: () => LinuxNetworkSetupServiceImpl(
        repository: getComponentFor<LinuxNetworkSetupRepository>(),
      ),
    ),
  );
  _registerComponent(
    ComponentCreationInfo<SnapshotRepository, FileSnapshotRepository>(
      creator: () => FileSnapshotRepository(),
    ),
  );
  _registerComponent(
    ComponentCreationInfo<
      RemoteConnectionRepository,
      SshRemoteConnectionRepository
    >(creator: () => SshRemoteConnectionRepository()),
  );
  _registerComponent(
    ComponentCreationInfo<
      RemoteHelperArtifactRepository,
      BundledRemoteHelperRepository
    >(creator: () => BundledRemoteHelperRepository()),
  );
  _registerComponent(
    ComponentCreationInfo<
      RemoteIconCacheRepository,
      FileRemoteIconCacheRepository
    >(
      creator: () => FileRemoteIconCacheRepository(
        root: () async {
          final support = await getApplicationSupportDirectory();
          return Directory('${support.path}/remote-icons/v1');
        },
      ),
    ),
  );
  _registerComponent(
    ComponentCreationInfo<ProcessIconService, ProcessIconServiceImpl>(
      creator: () => ProcessIconServiceImpl(
        cache: getComponentFor<RemoteIconCacheRepository>(),
        remoteHostsSettings: getComponentFor<RemoteHostsSettings>(),
      ),
      // The icon cache loads in the background; startup never waits for it.
      initializer: (service) => unawaited(service.initialize()),
    ),
  );
  _registerComponent(
    ComponentCreationInfo<RemoteHostService, RemoteHostServiceImpl>(
      creator: () => RemoteHostServiceImpl(
        connections: getComponentFor<RemoteConnectionRepository>(),
        artifacts: getComponentFor<RemoteHelperArtifactRepository>(),
        remoteHostsSettings: getComponentFor<RemoteHostsSettings>(),
        settingsService: getComponentFor<SettingsService>(),
        icons: getComponentFor<ProcessIconService>(),
      ),
      initializer: (service) => service.initialize(),
    ),
  );
  _registerComponent(
    ComponentCreationInfo<ProcessSessionFactory, ProcessSessionFactoryImpl>(
      creator: () => ProcessSessionFactoryImpl(
        processRepository: getComponentFor<ProcessRepository>(),
        snapshotRepository: getComponentFor<SnapshotRepository>(),
        repositoryOperationTracker:
            getComponentFor<RepositoryOperationTracker>(),
        settingsService: getComponentFor<SettingsService>(),
        remoteSources: getComponentFor<RemoteHostService>(),
        iconResolver: getComponentFor<ProcessIconService>(),
        iconService: getComponentFor<ProcessIconService>(),
      ),
    ),
  );
  _registerComponent(
    ComponentCreationInfo<WorkspaceTabsService, WorkspaceTabsServiceImpl>(
      creator: () => WorkspaceTabsServiceImpl(
        sessionFactory: getComponentFor<ProcessSessionFactory>(),
        store: SettingsWorkspaceTabsStore(
          getComponentFor<RemoteHostsSettings>(),
        ),
      ),
    ),
  );
  _registerComponent(
    ComponentCreationInfo<ProcessService, ProcessServiceImpl>(
      creator: () {
        final tabs = getComponentFor<WorkspaceTabsService>();
        return ProcessServiceImpl.overSessions(
          activeSession: tabs.activeSession,
          initializer: tabs.initialize,
        );
      },
      initializer: (service) => service.initialize(),
    ),
  );
}

void _registerComponent<TContract, TImpl extends TContract>(
  ComponentCreationInfo<TContract, TImpl> creationInfo,
) {
  final nr = _componentDefinitions.length;
  _componentDefinitions[TContract] = (nr: nr, creationInfo: creationInfo);
}
