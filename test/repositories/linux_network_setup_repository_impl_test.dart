import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:processlama/repositories/impl/linux_network_setup_repository_impl.dart';

void main() {
  test('snapshot path matches the shared fixture', () {
    final fixture = File(
      'fixtures/linux_network_snapshot_path.txt',
    ).readAsStringSync().trim();

    expect(LinuxNetworkSetupRepositoryImpl.snapshotPath, fixture);
  });
}
