import 'process_record.dart';

enum ProcessSearchAspect { all, name, pid, user, command, path, port }

class ProcessSearchOptions {
  const ProcessSearchOptions({
    this.matchCase = false,
    this.wholeWord = false,
    this.aspect = ProcessSearchAspect.all,
  });

  final bool matchCase;
  final bool wholeWord;
  final ProcessSearchAspect aspect;

  String savedQuery(String query) => '${aspect.name}:$query';

  ProcessSearchOptions copyWith({
    bool? matchCase,
    bool? wholeWord,
    ProcessSearchAspect? aspect,
  }) {
    return ProcessSearchOptions(
      matchCase: matchCase ?? this.matchCase,
      wholeWord: wholeWord ?? this.wholeWord,
      aspect: aspect ?? this.aspect,
    );
  }
}

/// Shared filter semantics for the process tree and saved-filter counts.
class ProcessSearchQuery {
  ProcessSearchQuery(this.text, this.options)
    : _pattern = options.wholeWord && text.isNotEmpty
          ? RegExp(
              r'(^|[^\w])' + RegExp.escape(text) + r'($|[^\w])',
              caseSensitive: options.matchCase,
            )
          : null;

  factory ProcessSearchQuery.parse(
    String value, {
    ProcessSearchOptions options = const ProcessSearchOptions(),
  }) {
    final text = value.trim();
    // `:8080`, as in `host:port`, is shorthand for `port:8080`.
    if (_portShorthand.hasMatch(text)) {
      return ProcessSearchQuery(
        text.substring(1),
        options.copyWith(aspect: ProcessSearchAspect.port),
      );
    }
    for (final aspect in ProcessSearchAspect.values) {
      final prefix = '${aspect.name}:';
      if (text.startsWith(prefix)) {
        return ProcessSearchQuery(
          text.substring(prefix.length).trim(),
          options.copyWith(aspect: aspect),
        );
      }
    }
    return ProcessSearchQuery(text, options);
  }

  static final RegExp _portShorthand = RegExp(r'^:[0-9]+$');
  static final RegExp _digits = RegExp(r'^[0-9]+$');

  final String text;
  final ProcessSearchOptions options;
  final RegExp? _pattern;

  /// The port [text] names, or null when it is not a valid port number.
  int? get port {
    if (!_digits.hasMatch(text)) return null;
    final port = int.tryParse(text);
    return port != null && port > 0 && port <= 65535 ? port : null;
  }

  bool matches(ProcessRecord record) {
    if (text.isEmpty) return true;
    if (options.aspect == ProcessSearchAspect.port) {
      final port = this.port;
      return port != null && (record.localPorts?.contains(port) ?? false);
    }
    // A bare number in the default search also finds the processes using
    // that port, so typing `8080` answers "who is on 8080?".
    if (options.aspect == ProcessSearchAspect.all &&
        (record.localPorts?.contains(port) ?? false)) {
      return true;
    }
    final fields = switch (options.aspect) {
      ProcessSearchAspect.all => [
        record.displayName,
        record.pid.toString(),
        record.executablePath,
        record.commandLine,
        record.appBundlePath,
      ],
      ProcessSearchAspect.name => [record.displayName],
      ProcessSearchAspect.pid => [record.pid.toString()],
      ProcessSearchAspect.user => [record.user, record.uid.toString()],
      ProcessSearchAspect.command => [record.commandLine],
      ProcessSearchAspect.path => [record.executablePath, record.appBundlePath],
      ProcessSearchAspect.port => const <String>[],
    };
    return fields.any(
      (field) =>
          _pattern?.hasMatch(field) ??
          (options.matchCase
              ? field.contains(text)
              : field.toLowerCase().contains(text.toLowerCase())),
    );
  }
}
