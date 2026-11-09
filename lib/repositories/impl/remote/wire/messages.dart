import '../../../../models/models.dart';
import 'contract.g.dart';

/// A received payload does not have its declared shape. Carries a fixed
/// reason only, never received text.
final class InvalidRemoteMessage implements Exception {
  const InvalidRemoteMessage(this.reason);

  final String reason;

  @override
  String toString() => 'InvalidRemoteMessage($reason)';
}

Never _invalid(String reason) => throw InvalidRemoteMessage(reason);

/// The object in [value] when it has exactly [keys].
Map<String, Object?> wireObject(
  Object? value,
  List<String> keys,
  String reason,
) {
  if (value is! Map<String, Object?> ||
      value.length != keys.length ||
      !keys.every(value.containsKey)) {
    _invalid(reason);
  }
  return value;
}

String wireString(
  Map<String, Object?> map,
  String key,
  int maxBytes,
  String reason,
) {
  final value = map[key];
  if (value is! String ||
      value.length > maxBytes ||
      value.codeUnits.any((unit) => unit < 0x20 || unit == 0x7f)) {
    _invalid(reason);
  }
  return value;
}

bool wireBool(Map<String, Object?> map, String key, String reason) {
  final value = map[key];
  if (value is! bool) _invalid(reason);
  return value;
}

int wireUnsigned(Map<String, Object?> map, String key, String reason) {
  final value = map[key];
  if (value is! int || value < 0) _invalid(reason);
  return value;
}

bool _isLowerHex(String text, int length) =>
    text.length == length &&
    text.codeUnits.every(
      (unit) =>
          (unit >= 0x30 && unit <= 0x39) || (unit >= 0x61 && unit <= 0x66),
    );

/// Validates the product part of a helper's hello.
RemoteHelperHello parseHelloBody(Object? value, {required String buildId}) {
  final map = wireObject(value, const [
    'os',
    'arch',
    'target',
    'kernel',
    'hostInstanceId',
    'hostnameHash',
    'processtreeRevision',
    'compatibility',
    'account',
    'capabilities',
    'bounds',
  ], 'hello');
  final target =
      RemoteHelperTarget.values
          .where(
            (candidate) =>
                candidate.wireName == wireString(map, 'target', 32, 'target'),
          )
          .firstOrNull ??
      _invalid('target');
  if (wireString(map, 'os', 16, 'os') != target.os ||
      wireString(map, 'arch', 16, 'arch') != target.arch) {
    _invalid('target');
  }
  final instance = wireString(map, 'hostInstanceId', 32, 'identity');
  final hostname = wireString(map, 'hostnameHash', 16, 'identity');
  final revision = wireString(map, 'processtreeRevision', 40, 'identity');
  if (!_isLowerHex(instance, 32) ||
      !_isLowerHex(hostname, 16) ||
      !RegExp(r'^[0-9a-fA-F]*$').hasMatch(revision)) {
    _invalid('identity');
  }
  final account = wireObject(map['account'], const ['uid'], 'account');
  final capabilities = wireObject(map['capabilities'], const [
    'gpu',
    'storageIo',
    'network',
    'signals',
    'inspector',
    'icons',
    'hidepid',
  ], 'capabilities');
  final network = wireObject(capabilities['network'], const [
    'source',
    'reason',
  ], 'network');
  final source =
      networkRateSourceFromWire(wireString(network, 'source', 16, 'network')) ??
      _invalid('network');
  final reasonValue = network['reason'];
  final NetworkUnavailableReason? reason;
  if (reasonValue == null) {
    reason = null;
  } else if (reasonValue is String) {
    reason =
        networkUnavailableReasonFromWire(reasonValue) ?? _invalid('network');
  } else {
    _invalid('network');
  }
  final inspector = wireObject(capabilities['inspector'], const [
    'files',
    'sockets',
    'threads',
    'security',
  ], 'inspector');
  final bounds = wireObject(map['bounds'], const [
    'iconBytes',
    'iconsPerFetch',
    'iconFetchBytes',
    'processesPerSample',
  ], 'bounds');
  for (final key in bounds.keys) {
    if (wireUnsigned(bounds, key, 'bounds') == 0) _invalid('bounds');
  }
  final facts = RemoteHostFacts(
    target: target,
    kernel: wireString(map, 'kernel', 128, 'kernel'),
    hostInstanceId: instance,
    hostnameHash: hostname,
    helperBuildId: buildId,
    compatibility: wireUnsigned(map, 'compatibility', 'compatibility'),
    processtreeRevision: revision,
    uid: wireUnsigned(account, 'uid', 'account'),
  );
  return RemoteHelperHello(
    facts: facts,
    capabilities: HostCapabilities(
      operatingSystem: facts.operatingSystem,
      gpu: wireBool(capabilities, 'gpu', 'capabilities'),
      storageIo: wireBool(capabilities, 'storageIo', 'capabilities'),
      networkSource: source,
      networkUnavailableReason: reason,
      signals: wireBool(capabilities, 'signals', 'capabilities'),
      inspectorFiles: wireBool(inspector, 'files', 'inspector'),
      inspectorSockets: wireBool(inspector, 'sockets', 'inspector'),
      inspectorThreads: wireBool(inspector, 'threads', 'inspector'),
      inspectorSecurity: wireBool(inspector, 'security', 'inspector'),
      icons: wireBool(capabilities, 'icons', 'capabilities'),
      hidepid: wireBool(capabilities, 'hidepid', 'capabilities'),
    ),
  );
}
