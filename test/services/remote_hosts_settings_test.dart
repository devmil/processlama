import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:processlama/models/models.dart';
import 'package:processlama/repositories/repositories.dart';
import 'package:processlama/services/impl/settings_service_impl.dart';
import 'package:processlama/services/services.dart';

void main() {
  RemoteHostProfile profile(String id, {String alias = 'build-box'}) =>
      RemoteHostProfile(id: id, displayName: 'Box $id', sshAlias: alias);

  late _ControlledRepository repository;
  late SettingsServiceImpl service;

  setUp(() async {
    repository = _ControlledRepository();
    service = SettingsServiceImpl(
      settingsRepository: _NoAppSettings(),
      remoteHostsRepository: repository,
    );
    await service.initialize();
  });

  test('profiles, tabs and options are saved as one value', () async {
    await service.addRemoteHostProfile(profile('a'));
    await service.addRemoteHostProfile(profile('b', alias: 'mac.mini'));
    await service.updateRemoteTabs(['b', 'a', 'unknown'], 'remote:b');
    await service.updateRemoteIconCacheBytes(32 * 1024 * 1024);
    await service.updateDefaultBackgroundRefresh(BackgroundRefreshMode.live);

    final stored = repository.saved!;
    expect(stored.profiles.map((profile) => profile.id), ['a', 'b']);
    expect(stored.openTabs, ['b', 'a']);
    expect(stored.activeTab, 'remote:b');
    expect(stored.iconCacheBytes, 32 * 1024 * 1024);
    expect(stored.defaultBackgroundRefresh, BackgroundRefreshMode.live);

    final reloaded = SettingsServiceImpl(
      settingsRepository: _NoAppSettings(),
      remoteHostsRepository: repository,
    );
    await reloaded.initialize();
    expect(reloaded.remoteHosts.value, stored);
  });

  test('removing a profile closes its tab', () async {
    await service.addRemoteHostProfile(profile('a'));
    await service.updateRemoteTabs(['a'], 'remote:a');
    await service.removeRemoteHostProfile('a');
    expect(service.remoteHosts.value.profiles, isEmpty);
    expect(service.remoteHosts.value.openTabs, isEmpty);
    expect(service.remoteHosts.value.activeTab, 'local');
  });

  test('invalid profiles are rejected before anything is saved', () async {
    for (final (candidate, reason) in [
      (
        profile('a', alias: '-oProxyCommand=x'),
        RemoteHostProfileRejection.invalidAlias,
      ),
      (
        profile('a', alias: 'user@host'),
        RemoteHostProfileRejection.invalidAlias,
      ),
      (
        RemoteHostProfile(id: 'a', displayName: ' ', sshAlias: 'box'),
        RemoteHostProfileRejection.invalidDisplayName,
      ),
      (
        RemoteHostProfile(id: 'a', displayName: 'x' * 65, sshAlias: 'box'),
        RemoteHostProfileRejection.invalidDisplayName,
      ),
    ]) {
      expect(
        () => service.addRemoteHostProfile(candidate),
        throwsA(
          isA<RemoteHostProfileRejected>().having(
            (error) => error.reason,
            'reason',
            reason,
          ),
        ),
      );
    }
    expect(repository.saves, 0);
    await service.addRemoteHostProfile(profile('a'));
    expect(
      () => service.addRemoteHostProfile(profile('a')),
      throwsA(isA<RemoteHostProfileRejected>()),
    );
  });

  test('at most 64 profiles are kept', () async {
    for (var index = 0; index < maximumRemoteHostProfiles; index++) {
      await service.addRemoteHostProfile(profile('$index'));
    }
    expect(
      () => service.addRemoteHostProfile(profile('one-more')),
      throwsA(
        isA<RemoteHostProfileRejected>().having(
          (error) => error.reason,
          'reason',
          RemoteHostProfileRejection.tooManyProfiles,
        ),
      ),
    );
  });

  test('a rejected save restores only its section', () async {
    await service.addRemoteHostProfile(profile('a'));
    repository.gate = Completer<void>();
    repository.failNext = true;
    final failing = service.addRemoteHostProfile(profile('b'));
    final tabs = service.updateRemoteTabs(['a'], 'remote:a');
    expect(service.remoteHosts.value.profiles, hasLength(2));
    repository.gate!.complete();

    await expectLater(
      failing,
      throwsA(
        isA<RemoteHostsSaveFailure>().having(
          (error) => error.section,
          'section',
          'profile',
        ),
      ),
    );
    await tabs;
    final state = service.remoteHosts.value;
    expect(state.profiles.map((profile) => profile.id), ['a']);
    expect(state.openTabs, ['a'], reason: 'the concurrent tab change survives');
    expect(repository.saved!.profiles.map((profile) => profile.id), ['a']);
    expect(repository.saved!.openTabs, ['a']);
  });

  test('editing keeps facts unless the alias changes', () async {
    const facts = RemoteHostFacts(
      target: RemoteHelperTarget.linuxX8664,
      kernel: '6.8',
      hostInstanceId: '0123456789abcdef0123456789abcdef',
      hostnameHash: '0123456789abcdef',
      helperBuildId: '0000000000000000000000000000000000000001',
      compatibility: 1,
      processtreeRevision: 'a9aed83',
      uid: 1000,
    );
    await service.addRemoteHostProfile(profile('a'));
    await service.updateRemoteHostFacts('a', facts);
    await service.updateRemoteHostProfile(
      profile('a').copyWith(displayName: 'Renamed', autoInstallHelper: true),
    );
    var stored = service.remoteHosts.value.profile('a')!;
    expect(stored.displayName, 'Renamed');
    expect(stored.autoInstallHelper, isTrue);
    expect(stored.lastKnown, facts);

    await service.updateRemoteHostProfile(
      stored.copyWith(sshAlias: 'other-box'),
    );
    stored = service.remoteHosts.value.profile('a')!;
    expect(stored.lastKnown, isNull);
  });

  test('stored values tolerate missing fields and keep unknown ones', () {
    final state = RemoteHostsState.fromJson(
      jsonDecode('''
      {
        "version": 1,
        "futureOption": {"x": 1},
        "profiles": [
          {"id": "a", "sshAlias": "box", "newField": true},
          {"id": "bad", "sshAlias": "user@box"},
          {"id": "a", "sshAlias": "duplicate"}
        ],
        "openTabs": ["a", "missing", "a"]
      }
      '''),
    );
    expect(state.profiles, hasLength(1));
    final stored = state.profiles.single;
    expect(stored.displayName, 'box');
    expect(stored.autoReconnect, isTrue);
    expect(stored.autoInstallHelper, isFalse);
    expect(stored.unknownFields, {'newField': true});
    expect(state.openTabs, ['a']);
    expect(state.iconCacheBytes, defaultRemoteIconCacheBytes);
    expect(state.toJson()['futureOption'], {'x': 1});
    expect(state.profiles.single.toJson()['newField'], isTrue);
  });
}

class _ControlledRepository implements RemoteHostsSettingsRepository {
  RemoteHostsState? saved;
  Completer<void>? gate;
  var failNext = false;
  var saves = 0;

  @override
  Future<RemoteHostsState> getRemoteHosts() async =>
      saved ?? const RemoteHostsState();

  @override
  Future<void> saveRemoteHosts(RemoteHostsState state) async {
    saves++;
    final waiting = gate;
    if (waiting != null) {
      gate = null;
      await waiting.future;
    }
    if (failNext) {
      failNext = false;
      throw StateError('disk full');
    }
    saved = RemoteHostsState.fromJson(jsonDecode(jsonEncode(state.toJson())));
  }
}

class _NoAppSettings implements SettingsRepository {
  @override
  Future<AppSettings> getSettings() async => const AppSettings();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
