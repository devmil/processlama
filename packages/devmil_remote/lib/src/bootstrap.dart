import 'dart:convert';

/// The last non-empty line of [bytes], without its line ending. Login
/// scripts may print text before a script's own status line; only the last
/// line is the answer. Bytes are read as Latin-1 so invalid UTF-8 cannot
/// throw.
String? lastNonEmptyLine(List<int> bytes) {
  final text = latin1.decode(bytes);
  final lines = text.split('\n');
  for (final line in lines.reversed) {
    final trimmed = line.endsWith('\r')
        ? line.substring(0, line.length - 1)
        : line;
    if (trimmed.trim().isNotEmpty) {
      return trimmed;
    }
  }
  return null;
}

/// A status line `<PREFIX> <version> <word>...` printed by a fixed script.
final class StatusMarker {
  const StatusMarker({
    required this.prefix,
    required this.version,
    required this.words,
  });

  final String prefix;
  final int version;
  final List<String> words;

  /// Parses [line] when it starts with [prefix] and a decimal version.
  /// Words are at most 64 printable ASCII characters each, at most eight.
  static StatusMarker? parse(String? line, String prefix) {
    if (line == null) {
      return null;
    }
    final parts = line.trim().split(' ');
    if (parts.length < 2 || parts.length > 10 || parts.first != prefix) {
      return null;
    }
    final version = int.tryParse(parts[1]);
    if (version == null || version < 0 || parts[1] != '$version') {
      return null;
    }
    final words = parts.sublist(2);
    for (final word in words) {
      if (word.isEmpty ||
          word.length > 64 ||
          word.codeUnits.any((unit) => unit < 0x21 || unit > 0x7e)) {
        return null;
      }
    }
    return StatusMarker(prefix: prefix, version: version, words: words);
  }
}

enum BootstrapState {
  /// Text so far; no start line yet.
  pending,

  /// The start line arrived; every later byte is a frame.
  frames,

  /// More text than [BootstrapProbe.maxBytes] without a start line.
  failed,
}

/// Classifies a launch script's standard output before the helper's hello.
///
/// The script prints `<prefix> 1 start` on its own line right before it
/// `exec`s the helper; anything a login script printed before that line is
/// discarded. When the output ends without a start line, the last non-empty
/// line is the script's status marker.
final class BootstrapProbe {
  BootstrapProbe({required this.prefix, this.maxBytes = 64 * 1024});

  final String prefix;
  final int maxBytes;
  final _text = <int>[];
  var _state = BootstrapState.pending;
  var _scanned = 0;

  BootstrapState get state => _state;

  String get _startLine => '$prefix 1 start';

  /// Adds output bytes. Once the start line is seen, returns the bytes that
  /// followed it (possibly empty); otherwise null.
  List<int>? add(List<int> bytes) {
    if (_state != BootstrapState.pending) {
      return null;
    }
    _text.addAll(bytes);
    while (true) {
      final newline = _text.indexOf(0x0a, _scanned);
      if (newline < 0) {
        break;
      }
      var line = latin1.decode(_text.sublist(_scanned, newline));
      if (line.endsWith('\r')) {
        line = line.substring(0, line.length - 1);
      }
      _scanned = newline + 1;
      if (line == _startLine) {
        _state = BootstrapState.frames;
        final rest = _text.sublist(_scanned);
        _text.clear();
        return rest;
      }
    }
    if (_text.length > maxBytes) {
      _state = BootstrapState.failed;
      _text.clear();
    }
    return null;
  }

  /// The status marker when the output ended before a start line.
  StatusMarker? marker() {
    if (_state != BootstrapState.pending) {
      return null;
    }
    return StatusMarker.parse(lastNonEmptyLine(_text), prefix);
  }
}
