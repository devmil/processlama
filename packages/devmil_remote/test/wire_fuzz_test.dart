import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:devmil_remote/devmil_remote.dart';
import 'package:test/test.dart';

/// Seeded, bounded mutation fuzzing of the frame decoder and the strict JSON
/// parser. Every failure must be a [WireFormatException].
const _seed = 0x5eed6175;
const _iterations = 20000;

final class _XorShift {
  _XorShift(this._state);
  int _state;

  int next() {
    _state ^= (_state << 13) & 0xffffffff;
    _state ^= _state >> 17;
    _state ^= (_state << 5) & 0xffffffff;
    return _state & 0x7fffffff;
  }

  int below(int bound) => bound <= 0 ? 0 : next() % bound;
}

final _corpus = [
  '{"protocolMajor":1,"nonce":"00112233445566778899aabbccddeeff","incarnation":"ffeeddccbbaa99887766554433221100","requestId":7,"kind":"result","payload":{"ok":{"cpu":[1,2,3]}}}',
  r'[[[[{"a":[1,2,3],"b":"é😀"}]]]]',
  '{"kind":"hello","limits":{"frameBytes":4194304}}',
].map((text) => Uint8List.fromList(utf8.encode(text))).toList();

const _tokens = ['"', '{', '}', '[', ']', ',', ':', r'\u', '-0', '1e9', '1.5'];

Uint8List _mutate(_XorShift random, Uint8List input) {
  var bytes = List<int>.of(input);
  for (var round = 0; round <= random.below(4); round += 1) {
    switch (random.below(5)) {
      case 0 when bytes.isNotEmpty:
        final index = random.below(bytes.length);
        bytes[index] ^= 1 << random.below(8);
      case 1 when bytes.isNotEmpty:
        bytes = bytes.sublist(0, random.below(bytes.length));
      case 2:
        final index = random.below(bytes.length + 1);
        bytes.insertAll(
          index,
          utf8.encode(_tokens[random.below(_tokens.length)]),
        );
      case 3:
        final index = random.below(bytes.length + 1);
        bytes.insert(index, random.below(256));
      default:
        if (bytes.length > 1) {
          final index = random.below(bytes.length - 1);
          final byte = bytes[index];
          bytes[index] = bytes[index + 1];
          bytes[index + 1] = byte;
        }
    }
  }
  return Uint8List.fromList(bytes);
}

void main() {
  test('mutated JSON only ever fails with WireFormatException', () {
    final random = _XorShift(_seed);
    for (var iteration = 0; iteration < _iterations; iteration += 1) {
      final input = _mutate(random, _corpus[random.below(_corpus.length)]);
      try {
        parseWireJson(input, WireParseLimits.standard);
      } on WireFormatException {
        // Expected for most inputs.
      }
    }
  });

  test('strict JSON rejects duplicate keys, fractions and lone surrogates', () {
    for (final text in [
      '{"a":1,"a":2}',
      '{"a":1.5}',
      '{"a":1e3}',
      r'"\ud800"',
      '{"a":1} x',
      '[01]',
      '{"a":9007199254740993}',
    ]) {
      expect(
        () => parseWireJson(
          Uint8List.fromList(utf8.encode(text)),
          WireParseLimits.standard,
        ),
        throwsA(isA<WireFormatException>()),
        reason: text,
      );
    }
    expect(
      () => parseWireJson(
        Uint8List.fromList([0x22, 0xc3, 0x28, 0x22]),
        WireParseLimits.standard,
      ),
      throwsA(isA<WireFormatException>()),
    );
  });

  test('depth and collection bounds hold', () {
    final deep = '${'[' * 17}${']' * 17}';
    expect(
      () => parseWireJson(
        Uint8List.fromList(utf8.encode(deep)),
        WireParseLimits.standard,
      ),
      throwsA(isA<WireFormatException>()),
    );
    final wide = '[${List.filled(5, '1').join(',')}]';
    expect(
      () => parseWireJson(
        Uint8List.fromList(utf8.encode(wide)),
        const WireParseLimits(depth: 4, collection: 4),
      ),
      throwsA(isA<WireFormatException>()),
    );
  });

  test(
    'frames split at every byte decode in order; bad lengths fail early',
    () {
      final bytes = <int>[
        ...encodeFrame(Uint8List.fromList(utf8.encode('{"a":1}'))),
        ...encodeFrame(Uint8List.fromList(utf8.encode('[]'))),
      ];
      final decoder = FrameDecoder(maxFrameBytes: 64, onDeadline: () {});
      final frames = <String>[];
      for (final byte in bytes) {
        decoder.add([byte]);
        for (
          var frame = decoder.next();
          frame != null;
          frame = decoder.next()
        ) {
          frames.add(utf8.decode(frame));
        }
      }
      expect(frames, ['{"a":1}', '[]']);

      for (final length in [0, 65, 0xffffffff]) {
        final header = Uint8List(4)..buffer.asByteData().setUint32(0, length);
        final failing = FrameDecoder(maxFrameBytes: 64, onDeadline: () {})
          ..add(header);
        expect(failing.next, throwsA(isA<WireFormatException>()));
      }
    },
  );

  test('a truncated frame reports its deadline', () {
    var expired = false;
    late void Function() fire;
    final decoder = FrameDecoder(
      maxFrameBytes: 64,
      onDeadline: () => expired = true,
      timer: (duration, callback) {
        fire = callback;
        return _NeverTimer();
      },
    )..add([0, 0, 0, 9, 1]);
    expect(decoder.next(), isNull);
    fire();
    expect(expired, isTrue);
  });
}

final class _NeverTimer implements Timer {
  @override
  void cancel() {}

  @override
  bool get isActive => true;

  @override
  int get tick => 0;
}
