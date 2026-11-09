import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:processlama/models/models.dart';
import 'package:processlama/repositories/impl/remote/wire/contract.g.dart';
import 'package:processlama/repositories/impl/remote/wire/messages.dart';

void main() {
  final document =
      jsonDecode(
            File('fixtures/remote_contract_vectors.json').readAsStringSync(),
          )
          as Map<String, Object?>;
  final vectors = (document['vectors']! as List).cast<Map<String, Object?>>();

  test('contract vectors are accepted or rejected as declared', () {
    var checked = 0;
    for (final vector in vectors) {
      final name = vector['name'];
      final valid = vector['valid'] == true;
      switch (vector['type']) {
        case 'helloBody':
          if (valid) {
            final hello = parseHelloBody(
              vector['value'],
              buildId: remoteHelperBuildId,
            );
            expect(hello.facts.helperBuildId, remoteHelperBuildId);
          } else {
            expect(
              () =>
                  parseHelloBody(vector['value'], buildId: remoteHelperBuildId),
              throwsA(isA<InvalidRemoteMessage>()),
              reason: '$name',
            );
          }
          checked++;
      }
    }
    expect(checked, greaterThanOrEqualTo(4));
  });

  test('a Linux hello maps to Linux capabilities', () {
    final hello = parseHelloBody(
      vectors.firstWhere((vector) => vector['name'] == 'linux hello')['value'],
      buildId: remoteHelperBuildId,
    );
    expect(hello.facts.target, RemoteHelperTarget.linuxX8664);
    expect(hello.capabilities.operatingSystem, HostOperatingSystem.linux);
    expect(hello.capabilities.networkSource, NetworkRateSource.none);
    expect(
      hello.capabilities.networkUnavailableReason,
      NetworkUnavailableReason.serviceNotInstalled,
    );
    expect(RemoteHostFacts.fromJson(hello.facts.toJson()), hello.facts);
  });

  test('the build ID is the compatibility version as forty digits', () {
    expect(remoteHelperBuildId, hasLength(40));
    expect(int.parse(remoteHelperBuildId), remoteHelperCompatibility);
    final compatibility = File(
      'rust-core/remote-helper/COMPATIBILITY',
    ).readAsLinesSync().firstWhere((line) => line.startsWith('version '));
    expect(compatibility, 'version $remoteHelperCompatibility');
  });

  test('failure codes, signals and outcomes map by name', () {
    for (final outcome in SignalOutcome.values) {
      expect(signalOutcomeFromWire(signalOutcomeToWire(outcome)), outcome);
    }
    for (final code in RemoteFailureCode.values) {
      expect(remoteFailureCodeFromWire(code.name), code);
    }
    expect(remoteFailureCodeFromWire('notACode'), isNull);
    expect(RemoteFailureCode.values.where((code) => code.retryable).toSet(), {
      RemoteFailureCode.sshConnectionFailed,
      RemoteFailureCode.heartbeatLost,
      RemoteFailureCode.helperStartFailed,
    });
  });
}
