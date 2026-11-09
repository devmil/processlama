import 'dart:async';

import 'remote_timers.dart';

/// The bounded reconnect schedule: 2, 5, 15 and 30 seconds, then every 60
/// seconds until [window] has passed since the connection was lost.
final class ReconnectSchedule {
  const ReconnectSchedule({
    this.delays = const [
      Duration(seconds: 2),
      Duration(seconds: 5),
      Duration(seconds: 15),
      Duration(seconds: 30),
    ],
    this.repeat = const Duration(seconds: 60),
    this.window = const Duration(minutes: 10),
  });

  final List<Duration> delays;
  final Duration repeat;
  final Duration window;

  /// The delay before attempt [attempt] (from 0), or null when that attempt
  /// would start after the window, measured from the loss at [elapsed] 0.
  Duration? delayFor(int attempt, Duration elapsed) {
    final delay = attempt < delays.length ? delays[attempt] : repeat;
    if (elapsed + delay > window) {
      return null;
    }
    return delay;
  }
}

/// What one reconnect attempt reported.
enum ReconnectResult {
  /// Connected again; the reconnector stops.
  connected,

  /// A retryable failure; the schedule continues.
  retry,

  /// A failure that needs the user; the reconnector stops.
  giveUp,
}

/// Runs reconnect attempts on [schedule] after a connection was lost.
///
/// Only one attempt runs at a time. [stop] cancels the pending delay; an
/// attempt already running finishes, but its result is ignored.
final class RemoteReconnector {
  RemoteReconnector({
    required this.attempt,
    this.schedule = const ReconnectSchedule(),
    this.onExhausted,
    this._timer = systemRemoteTimer,
    Duration Function()? clock,
  }) : _clock = clock ?? _stopwatchClock();

  /// One connection attempt.
  final Future<ReconnectResult> Function() attempt;
  final ReconnectSchedule schedule;

  /// Called once when the window ends without a connection.
  final void Function()? onExhausted;
  final RemoteTimerFactory _timer;

  /// Monotonic time; attempts count against the window too.
  final Duration Function() _clock;

  Timer? _pending;
  var _attempts = 0;
  var _lostAt = Duration.zero;
  var _running = false;
  var _generation = 0;

  bool get isRunning => _running;

  /// Attempts made since [start].
  int get attempts => _attempts;

  /// Starts the schedule. Restarting resets it.
  void start() {
    stop();
    _running = true;
    _attempts = 0;
    _lostAt = _clock();
    _scheduleNext(_generation);
  }

  void stop() {
    _generation++;
    _running = false;
    _pending?.cancel();
    _pending = null;
  }

  void _scheduleNext(int generation) {
    final delay = schedule.delayFor(_attempts, _clock() - _lostAt);
    if (delay == null) {
      _running = false;
      onExhausted?.call();
      return;
    }
    _pending = _timer(delay, () async {
      if (generation != _generation) {
        return;
      }
      _attempts++;
      final ReconnectResult result;
      try {
        result = await attempt();
      } on Object {
        if (generation == _generation) {
          _scheduleNext(generation);
        }
        return;
      }
      if (generation != _generation) {
        return;
      }
      switch (result) {
        case ReconnectResult.connected:
        case ReconnectResult.giveUp:
          _running = false;
        case ReconnectResult.retry:
          _scheduleNext(generation);
      }
    });
  }
}

Duration Function() _stopwatchClock() {
  final stopwatch = Stopwatch()..start();
  return () => stopwatch.elapsed;
}
