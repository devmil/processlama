import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:processlama/services/tree_order_lock_controller.dart';

void main() {
  group('TreeOrderLockController', () {
    test('hover acquires the lock immediately', () {
      final controller = TreeOrderLockController();
      addTearDown(controller.dispose);

      controller.setHovering(true);

      expect(controller.locked.value, isTrue);
    });

    test(
      'context menu outlasts hover and interaction and hands off to dialog',
      () {
        FakeAsync().run((async) {
          final controller = TreeOrderLockController();
          addTearDown(controller.dispose);
          controller.setHovering(true);
          controller.markInteraction();
          controller.setContextMenuOpen(true);
          controller.setHovering(false);
          async.elapse(const Duration(seconds: 5));
          expect(controller.locked.value, isTrue);

          controller.setModalOverlayOpen(true);
          controller.setContextMenuOpen(false);
          async.elapse(const Duration(seconds: 5));
          expect(controller.locked.value, isTrue);

          controller.setModalOverlayOpen(false);
          async.elapse(const Duration(milliseconds: 149));
          expect(controller.locked.value, isTrue);
          async.elapse(const Duration(milliseconds: 1));
          expect(controller.locked.value, isFalse);
        });
      },
    );

    test('closing a context menu preserves hover', () {
      FakeAsync().run((async) {
        final controller = TreeOrderLockController();
        addTearDown(controller.dispose);
        controller.setContextMenuOpen(true);
        expect(controller.locked.value, isTrue);
        controller.setHovering(true);
        controller.setContextMenuOpen(false);
        async.elapse(const Duration(seconds: 5));
        expect(controller.locked.value, isTrue);
        controller.setHovering(false);
        async.elapse(const Duration(milliseconds: 150));
        expect(controller.locked.value, isFalse);
      });
    });

    test('modal overlay acquires the lock immediately', () {
      final controller = TreeOrderLockController();
      addTearDown(controller.dispose);

      controller.setModalOverlayOpen(true);

      expect(controller.locked.value, isTrue);
    });

    test('interaction acquires the lock for the hold duration', () {
      FakeAsync().run((async) {
        final controller = TreeOrderLockController(
          interactionHoldDuration: const Duration(milliseconds: 2500),
          releaseDelay: Duration.zero,
        );
        addTearDown(controller.dispose);

        controller.markInteraction();

        expect(controller.locked.value, isTrue);

        async.elapse(const Duration(milliseconds: 2499));
        expect(controller.locked.value, isTrue);

        async.elapse(const Duration(milliseconds: 2));
        expect(controller.locked.value, isFalse);
      });
    });

    test('repeated interactions extend the hold from the last event', () {
      FakeAsync().run((async) {
        final controller = TreeOrderLockController(
          interactionHoldDuration: const Duration(milliseconds: 2500),
          releaseDelay: Duration.zero,
        );
        addTearDown(controller.dispose);

        controller.markInteraction();
        async.elapse(const Duration(milliseconds: 2000));
        controller.markInteraction();

        // 1000ms after the first interaction's timer would have fired: still
        // locked because the second interaction reset the window.
        async.elapse(const Duration(milliseconds: 1000));
        expect(controller.locked.value, isTrue);

        async.elapse(const Duration(milliseconds: 1500));
        expect(controller.locked.value, isFalse);
      });
    });

    test('release is debounced so overlapping surfaces stay continuous', () {
      FakeAsync().run((async) {
        final transitions = <bool>[];
        final controller = TreeOrderLockController(
          releaseDelay: const Duration(milliseconds: 150),
          interactionHoldDuration: const Duration(milliseconds: 2500),
        );
        addTearDown(controller.dispose);
        controller.locked.addListener(
          () => transitions.add(controller.locked.value),
        );

        // Hover keeps the tree locked.
        controller.setHovering(true);
        expect(transitions, [true]);

        // Hover ends (e.g. pointer moves toward a native menu), but the
        // release is deferred.
        controller.setHovering(false);
        expect(
          controller.locked.value,
          isTrue,
          reason: 'release must be deferred',
        );
        expect(transitions, [true]);

        // Before the debounce window elapses, the confirmation dialog opens.
        async.elapse(const Duration(milliseconds: 100));
        controller.setModalOverlayOpen(true);
        expect(controller.locked.value, isTrue);
        expect(transitions, [
          true,
        ], reason: 'no transition while another surface remains active');

        // The debounce timer must have been cancelled: even after the original
        // 150ms window passes, the modal keeps the lock.
        async.elapse(const Duration(milliseconds: 200));
        expect(controller.locked.value, isTrue);

        // Dialog closes; release is deferred again, then fires.
        controller.setModalOverlayOpen(false);
        expect(controller.locked.value, isTrue);
        async.elapse(const Duration(milliseconds: 149));
        expect(controller.locked.value, isTrue);
        async.elapse(const Duration(milliseconds: 2));
        expect(controller.locked.value, isFalse);
        expect(transitions, [true, false]);
      });
    });

    test(
      'a refresh between menu close and dialog open cannot sneak through',
      () {
        FakeAsync().run((async) {
          final controller = TreeOrderLockController(
            releaseDelay: const Duration(milliseconds: 150),
            interactionHoldDuration: const Duration(milliseconds: 2500),
          );
          addTearDown(controller.dispose);

          controller.setHovering(true);

          // Native context menu dismisses: hover drops.
          controller.setHovering(false);

          // The polling refresh that used to sneak through happens here.
          async.elapse(const Duration(milliseconds: 20));
          expect(
            controller.locked.value,
            isTrue,
            reason: 'debounced release must bridge the gap',
          );

          // Confirmation dialog opens before the debounce fires.
          controller.setModalOverlayOpen(true);
          async.elapse(const Duration(milliseconds: 500));
          expect(controller.locked.value, isTrue);
        });
      },
    );

    test('release fires when no surface is active after the delay', () {
      FakeAsync().run((async) {
        final controller = TreeOrderLockController(
          releaseDelay: const Duration(milliseconds: 150),
          interactionHoldDuration: const Duration(milliseconds: 2500),
        );
        addTearDown(controller.dispose);

        controller.setHovering(true);
        controller.setHovering(false);

        async.elapse(const Duration(milliseconds: 150));
        expect(controller.locked.value, isFalse);
      });
    });

    test('resetInteraction clears the interaction hold and releases', () {
      FakeAsync().run((async) {
        final controller = TreeOrderLockController(
          interactionHoldDuration: const Duration(milliseconds: 2500),
          releaseDelay: Duration.zero,
        );
        addTearDown(controller.dispose);

        controller.markInteraction();
        expect(controller.locked.value, isTrue);

        controller.resetInteraction();
        expect(controller.locked.value, isFalse);
      });
    });

    test('resetInteraction does not drop hover or modal locks', () {
      FakeAsync().run((async) {
        final controller = TreeOrderLockController(
          interactionHoldDuration: const Duration(milliseconds: 2500),
          releaseDelay: Duration.zero,
        );
        addTearDown(controller.dispose);

        controller.setHovering(true);
        controller.markInteraction();
        controller.resetInteraction();

        expect(controller.locked.value, isTrue);
      });
    });

    test('listeners are only notified on actual state transitions', () {
      FakeAsync().run((async) {
        final controller = TreeOrderLockController(
          releaseDelay: const Duration(milliseconds: 150),
          interactionHoldDuration: const Duration(milliseconds: 2500),
        );
        addTearDown(controller.dispose);
        var notifications = 0;
        controller.locked.addListener(() => notifications++);

        controller.setHovering(true);
        expect(notifications, 1);

        // Re-asserting the same surface is a no-op.
        controller.setHovering(true);
        expect(notifications, 1);

        // Adding a second surface while already locked is a no-op.
        controller.setModalOverlayOpen(true);
        expect(notifications, 1);

        controller.setHovering(false);
        // Still locked by modal + deferred release; no notification yet.
        expect(notifications, 1);

        controller.setModalOverlayOpen(false);
        async.elapse(const Duration(milliseconds: 150));
        expect(notifications, 2);
      });
    });
  });
}
