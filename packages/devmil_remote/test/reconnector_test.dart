import 'package:devmil_remote/devmil_remote.dart';
import 'package:devmil_remote/testing.dart';
import 'package:test/test.dart';

void main() {
  test('follows 2, 5, 15, 30 and then 60 second delays', () async {
    final timers = FakeTimers();
    final attemptsAt = <Duration>[];
    var exhausted = false;
    final reconnector = RemoteReconnector(
      attempt: () async {
        attemptsAt.add(timers.now);
        return ReconnectResult.retry;
      },
      timer: timers.call,
      clock: () => timers.now,
      onExhausted: () => exhausted = true,
    )..start();

    for (var second = 0; second < 700; second++) {
      timers.elapse(const Duration(seconds: 1));
      await settle();
    }

    expect(attemptsAt.take(6).map((at) => at.inSeconds), [
      2,
      7,
      22,
      52,
      112,
      172,
    ]);
    expect(attemptsAt.last.inSeconds, lessThanOrEqualTo(600));
    expect(exhausted, isTrue);
    expect(reconnector.isRunning, isFalse);
  });

  test('stops after a connection or a give-up', () async {
    for (final result in [ReconnectResult.connected, ReconnectResult.giveUp]) {
      final timers = FakeTimers();
      var attempts = 0;
      final reconnector = RemoteReconnector(
        attempt: () async {
          attempts++;
          return result;
        },
        timer: timers.call,
        clock: () => timers.now,
      )..start();
      timers.elapse(const Duration(seconds: 2));
      await settle();
      timers.elapse(const Duration(minutes: 5));
      await settle();
      expect(attempts, 1);
      expect(reconnector.isRunning, isFalse);
    }
  });

  test('stop cancels a pending attempt', () async {
    final timers = FakeTimers();
    var attempts = 0;
    final reconnector = RemoteReconnector(
      attempt: () async {
        attempts++;
        return ReconnectResult.retry;
      },
      timer: timers.call,
      clock: () => timers.now,
    )..start();
    reconnector.stop();
    timers.elapse(const Duration(minutes: 1));
    await settle();
    expect(attempts, 0);
  });
}
