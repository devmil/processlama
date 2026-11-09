import 'dart:async';
import 'dart:typed_data';

import '../src/remote_process.dart';

/// A [RemoteProcess] whose output the test writes and whose input it reads.
final class FakeRemoteProcess implements RemoteProcess {
  final _stdout = StreamController<List<int>>();
  final _stdin = StreamController<Uint8List>.broadcast(sync: true);
  final _exit = Completer<int>();
  final written = <int>[];
  var stdinClosed = false;
  var terminated = false;

  /// Bytes the client wrote, as they arrive.
  Stream<Uint8List> get stdin => _stdin.stream;

  @override
  Stream<List<int>> get stdout => _stdout.stream;

  @override
  Future<int> get exitCode => _exit.future;

  /// Emits [bytes] on the process's standard output.
  void emit(List<int> bytes) {
    if (!_stdout.isClosed) {
      _stdout.add(bytes);
    }
  }

  /// Ends standard output and exits with [code].
  Future<void> exit([int code = 0]) async {
    if (!_stdout.isClosed) {
      await _stdout.close();
    }
    if (!_exit.isCompleted) {
      _exit.complete(code);
    }
  }

  @override
  void write(List<int> bytes) {
    if (stdinClosed || _exit.isCompleted) {
      return;
    }
    written.addAll(bytes);
    _stdin.add(Uint8List.fromList(bytes));
  }

  @override
  Future<void> closeStdin() async => stdinClosed = true;

  @override
  Future<void> terminate() async {
    terminated = true;
    stdinClosed = true;
    await exit(-15);
  }
}
