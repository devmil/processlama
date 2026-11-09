import 'package:flutter/foundation.dart';

import '../../models/models.dart';
import '../../repositories/repositories.dart';
import '../process_icon_resolver.dart';
import '../process_icon_service.dart';
import '../process_session.dart';
import '../process_session_factory.dart';
import '../process_source.dart';
import '../repository_operation_tracker.dart';
import '../settings_service.dart';
import 'local_process_source.dart';

class ProcessSessionFactoryImpl implements ProcessSessionFactory {
  ProcessSessionFactoryImpl({
    required this.processRepository,
    required this.snapshotRepository,
    required this.repositoryOperationTracker,
    this.settingsService,
    this.remoteSources,
    this.platform,
    this.iconResolver = const FileIconResolver(),
    this.iconService,
  });

  final ProcessRepository processRepository;
  final SnapshotRepository snapshotRepository;
  final RepositoryOperationTracker repositoryOperationTracker;
  final SettingsService? settingsService;
  final RemoteProcessSourceProvider? remoteSources;
  final TargetPlatform? platform;
  final ProcessIconResolver iconResolver;
  final ProcessIconService? iconService;

  @override
  ProcessSessionHandle create(WorkspaceTab tab) {
    final ProcessSource source;
    var backgroundCadence = const ProcessCadence.background(
      defaultBackgroundRefreshInterval,
    );
    RemoteSnapshotContextProvider? snapshotContext;
    switch (tab) {
      case LocalWorkspaceTab():
        source = LocalProcessSource(
          processRepository: processRepository,
          repositoryOperationTracker: repositoryOperationTracker,
          platform: platform,
        );
      case RemoteWorkspaceTab(:final profileId):
        final provider = remoteSources;
        final remote = provider?.createSource(profileId);
        if (provider == null || remote == null) {
          throw ProcessSessionUnavailable(tab);
        }
        source = remote;
        backgroundCadence = provider.backgroundCadenceFor(profileId);
        snapshotContext = (snapshot) =>
            provider.snapshotContext(profileId, snapshot);
    }
    return ProcessSessionHandle(
      session: ProcessSession(
        source: source,
        snapshotRepository: snapshotRepository,
        repositoryOperationTracker: repositoryOperationTracker,
        settingsService: settingsService,
        iconResolver: iconResolver,
        iconService: iconService,
        remoteSnapshotContext: snapshotContext,
        backgroundCadence: backgroundCadence,
      ),
      source: source,
    );
  }
}
