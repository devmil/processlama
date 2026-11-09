import 'dart:convert';

import 'package:devmil_remote/devmil_remote.dart';
import 'package:test/test.dart';

void main() {
  test('takes the last non-empty line', () {
    expect(
      lastNonEmptyLine(utf8.encode('Welcome!\nmotd\r\nX-INSTALL 1 ok\n\n  \n')),
      'X-INSTALL 1 ok',
    );
    expect(lastNonEmptyLine(const []), isNull);
    expect(lastNonEmptyLine([0xff, 0x0a, 0x41]), 'A');
  });

  test('parses status markers strictly', () {
    final marker = StatusMarker.parse(
      'X-BOOTSTRAP 1 missing linux/x86_64',
      'X-BOOTSTRAP',
    )!;
    expect(marker.version, 1);
    expect(marker.words, ['missing', 'linux/x86_64']);
    for (final line in [
      'X-BOOTSTRAP',
      'X-BOOTSTRAP one missing',
      'X-BOOTSTRAP 01 missing',
      'Y-BOOTSTRAP 1 missing',
      'X-BOOTSTRAP 1 ${'w' * 65}',
      'X-BOOTSTRAP 1 a\tb',
    ]) {
      expect(StatusMarker.parse(line, 'X-BOOTSTRAP'), isNull, reason: line);
    }
  });

  test('frames start after the start line, after any login text', () {
    final probe = BootstrapProbe(prefix: 'X-BOOTSTRAP');
    expect(probe.add(utf8.encode('Last login: today\nX-BOOT')), isNull);
    final rest = probe.add([...utf8.encode('STRAP 1 start\n'), 0, 0, 0, 5]);
    expect(probe.state, BootstrapState.frames);
    expect(rest, [0, 0, 0, 5]);
  });

  test('reports the marker when output ends without a start line', () {
    final probe = BootstrapProbe(prefix: 'X-BOOTSTRAP');
    probe.add(utf8.encode('banner\nX-BOOTSTRAP 1 missing linux/aarch64\n'));
    expect(probe.marker()!.words, ['missing', 'linux/aarch64']);
  });

  test('fails on unbounded text', () {
    final probe = BootstrapProbe(prefix: 'X-BOOTSTRAP', maxBytes: 16);
    probe.add(utf8.encode('a' * 32));
    expect(probe.state, BootstrapState.failed);
    expect(probe.marker(), isNull);
  });
}
