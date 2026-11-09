// The icon part of the --performance lane: 80 fixture applications with PNG
// and SVG icons in an Ubuntu 22.04 container. Measures how long until every
// fixture row shows its icon, on the plain link and through a tc-throttled
// one, the telemetry gaps meanwhile, and that a changed icon file costs
// exactly one fetch. Prints an ICONS line the lane records.
@TestOn('linux')
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated_io.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:processlama/models/models.dart';
import 'package:processlama/repositories/repositories.dart';
import 'package:processlama/repositories/impl/remote/bundled_remote_helper_repository.dart';
import 'package:processlama/repositories/impl/remote/file_remote_icon_cache_repository.dart';
import 'package:processlama/repositories/impl/remote/ssh_remote_connection_repository.dart';
import 'package:processlama/rust/frb_generated.dart';
import 'package:processlama/services/impl/process_icon_service_impl.dart';
import 'package:processlama/services/impl/remote_host_service_impl.dart';
import 'package:processlama/services/impl/settings_service_impl.dart';
import 'package:processlama/services/services.dart';

String _fixture(String name) {
  final value = Platform.environment[name];
  if (value == null || value.isEmpty) {
    throw StateError('run through scripts/verify_remote_hosts.py ($name)');
  }
  return value;
}

final class _Port implements RemoteHostInteractionPort {
  @override
  bool get isActive => true;

  @override
  Future<RemoteInstallChoice> confirmInstall(
    RemoteInstallRequest request,
  ) async => RemoteInstallChoice.install;

  @override
  Future<bool> confirmHelperRemoval(RemoteHostProfile profile) async => true;

  @override
  void report(RemoteHostReport report) {}
}

class _NoAppSettings implements SettingsRepository {
  @override
  Future<AppSettings> getSettings() async => const AppSettings();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Counts what the icon service fetches.
final class _CountingIcons extends ProcessIconServiceImpl {
  _CountingIcons({required super.cache});

  final fetched = <List<String>>[];

  @override
  void ensure(String sourceKey, Set<String> hashes, RemoteIconFetcher fetch) {
    super.ensure(sourceKey, hashes, (requested) {
      fetched.add(List.of(requested));
      return fetch(requested);
    });
  }
}

const _apps = 80;

Future<void> _exec(String container, List<String> command) async {
  final result = await Process.run('podman', ['exec', container, ...command]);
  expect(result.exitCode, 0, reason: '${result.stderr}');
}

void main() {
  setUpAll(() async {
    await RustLib.init(
      externalLibrary: ExternalLibrary.open(
        _fixture('PROCESSLAMA_NATIVE_LIBRARY'),
      ),
    );
  });

  test('icons fill in on plain and throttled links', () async {
    final alias = _fixture('PROCESSLAMA_TEST_ALIAS');
    final container = _fixture('PROCESSLAMA_TEST_CONTAINER');
    final settings = SettingsServiceImpl(
      settingsRepository: _NoAppSettings(),
      remoteHostsRepository: MemoryRemoteHostsSettingsRepository(),
    );
    await settings.initialize();

    Future<Map<String, Object?>> measure(String label) async {
      final cacheRoot = await Directory.systemTemp.createTemp('icons-$label-');
      addTearDown(() => cacheRoot.delete(recursive: true));
      final icons = _CountingIcons(
        cache: FileRemoteIconCacheRepository(root: () async => cacheRoot),
      );
      await icons.initialize();
      final service = RemoteHostServiceImpl(
        connections: SshRemoteConnectionRepository(
          configFile: _fixture('PROCESSLAMA_SSH_CONFIG'),
        ),
        artifacts: BundledRemoteHelperRepository(
          resolvedExecutable: '/nonexistent/processlama',
          environment: {
            'PROCESSLAMA_REMOTE_HELPER_DIR': _fixture(
              'PROCESSLAMA_REMOTE_HELPER_DIR',
            ),
          },
          releaseBuild: false,
        ),
        remoteHostsSettings: settings,
        settingsService: settings,
        icons: icons,
      );
      final workflows = RemoteHostWorkflows(
        remoteHosts: service,
        port: _Port(),
      );
      final profile = await service.addProfile(
        RemoteHostProfileDraft(sshAlias: alias),
      );
      expect(
        (await workflows.connect(profile.id)).phase,
        RemoteConnectionPhase.live,
      );
      final source = service.createSource(profile.id)!;
      final arrivals = <DateTime>[];
      ProcessSnapshot? latest;
      source.updates.listen((snapshot) {
        arrivals.add(DateTime.now());
        latest = snapshot;
      });
      await source.setCadence(const ProcessCadence.live(Duration(seconds: 1)));

      List<ProcessRecord> apps() => [
        for (final record in latest?.processes ?? const <ProcessRecord>[])
          if (record.executablePath.startsWith('/home/tester/bin/app')) record,
      ];
      bool resolved() {
        final rows = apps();
        return rows.length == _apps &&
            rows.every((record) => icons.pathFor(record.iconRef) != null);
      }

      while (apps().length < _apps) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
      final visible = DateTime.now();
      final deadline = visible.add(const Duration(seconds: 30));
      while (!resolved() && DateTime.now().isBefore(deadline)) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
      final shown = DateTime.now().difference(visible);
      expect(resolved(), isTrue, reason: 'every fixture row gets its icon');
      // Keep sampling a little after the transfer for the gap measurement.
      await Future<void>.delayed(const Duration(seconds: 3));
      final gaps = [
        for (var index = 1; index < arrivals.length; index++)
          arrivals[index].difference(arrivals[index - 1]).inMilliseconds,
      ];
      final result = <String, Object?>{
        'allIconsMs': shown.inMilliseconds,
        'fetches': icons.fetched.length,
        'iconsFetched': icons.fetched.fold<int>(
          0,
          (n, batch) => n + batch.length,
        ),
        'maxGapMs': gaps.reduce((a, b) => a > b ? a : b),
      };

      if (label == 'plain') {
        // A changed icon file is fetched once, under its new hash.
        final before = icons.fetched.length;
        final changed = apps().firstWhere(
          (record) => record.executablePath.endsWith('/app01'),
        );
        final oldHash = (changed.iconRef! as ProcessRemoteIcon).sha256;
        await _exec(container, [
          'sh',
          '-c',
          "sed -i 's/#[0-9a-f]\\{6\\}/#123456/' /home/tester/icons/app01.svg",
        ]);
        String? newHash;
        final changeDeadline = DateTime.now().add(const Duration(seconds: 20));
        while (DateTime.now().isBefore(changeDeadline)) {
          final now = apps().firstWhere(
            (record) => record.executablePath.endsWith('/app01'),
          );
          final hash = (now.iconRef as ProcessRemoteIcon?)?.sha256;
          if (hash != null &&
              hash != oldHash &&
              icons.pathFor(now.iconRef) != null) {
            newHash = hash;
            break;
          }
          await Future<void>.delayed(const Duration(milliseconds: 50));
        }
        expect(
          newHash,
          isNotNull,
          reason: 'the new icon arrives without action',
        );
        await Future<void>.delayed(const Duration(seconds: 2));
        final after = icons.fetched.sublist(before);
        expect(after, [
          [newHash],
        ], reason: 'exactly one fetch for the changed icon');
        result['changedIconFetches'] = after.length;
      }

      await source.dispose();
      expect(await workflows.removeHelper(profile.id), RemoteInstallResult.ok);
      await service.dispose();
      return result;
    }

    final plain = await measure('plain');
    // The first non-loopback interface; rootless networking names vary.
    const device = r'"$(ls /sys/class/net | grep -v "^lo$" | head -n 1)"';
    await _exec(container, [
      'sh',
      '-c',
      'tc qdisc add dev $device root netem rate 10mbit delay 20ms',
    ]);
    final throttled = await measure('throttled');
    await _exec(container, ['sh', '-c', 'tc qdisc del dev $device root']);
    // ignore: avoid_print
    print('ICONS ${jsonEncode({'plain': plain, 'throttled': throttled})}');
  }, timeout: const Timeout(Duration(minutes: 5)));
}
