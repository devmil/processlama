import 'dart:async';

import 'package:flutter/foundation.dart';

/// Centralizes the decision of whether the process tree should keep its
/// current visible row ordering instead of resorting on the next refresh.
///
/// Inputs arrive from several independent interaction surfaces (pointer hover,
/// keyboard navigation, context menus, modal overlays). Rather than scattering
/// that state and
/// recomputing the lock at every publish site, [TreeOrderLockController] is the
/// single source of truth and emits the computed [locked] state.
///
/// A short [releaseDelay] bridges the brief gap between overlapping surfaces —
/// for example a native context menu dismissing immediately before a
/// confirmation dialog opens — so no single refresh can sneak through and
/// reorder the tree mid-interaction. Acquisition is immediate; only the
/// release is debounced, and only when no surface is still active.
class TreeOrderLockController {
  TreeOrderLockController({
    this._releaseDelay = const Duration(milliseconds: 150),
    this._interactionHoldDuration = const Duration(milliseconds: 2500),
  });

  final Duration _releaseDelay;
  final Duration _interactionHoldDuration;

  bool _hovering = false;
  bool _modalOverlayOpen = false;
  bool _contextMenuOpen = false;
  Timer? _interactionTimer;
  Timer? _releaseTimer;

  final ValueNotifier<bool> _state = ValueNotifier<bool>(false);

  /// Whether tree ordering should currently be preserved.
  ///
  /// Stays `true` for up to [releaseDelay] after the last active surface goes
  /// away, so consecutive overlapping surfaces keep the lock continuous.
  ValueListenable<bool> get locked => _state;

  /// Pointer hover over the tree.
  void setHovering(bool value) {
    if (_hovering == value) {
      return;
    }
    _hovering = value;
    _evaluate();
  }

  /// A process context menu, independent of pointer and dialog state.
  void setContextMenuOpen(bool value) {
    if (_contextMenuOpen == value) {
      return;
    }
    _contextMenuOpen = value;
    _evaluate();
  }

  /// A modal overlay (dialog) covering the tree.
  void setModalOverlayOpen(bool value) {
    if (_modalOverlayOpen == value) {
      return;
    }
    _modalOverlayOpen = value;
    _evaluate();
  }

  /// Records a direct tree interaction (selection, expansion, keyboard
  /// navigation). Keeps ordering stable for [interactionHoldDuration] after
  /// the most recent interaction.
  void markInteraction() {
    _interactionTimer?.cancel();
    _interactionTimer = Timer(_interactionHoldDuration, _onInteractionExpired);
    _evaluate();
  }

  /// Drops the interaction hold immediately. Used when the tree context
  /// changes (e.g. entering or leaving snapshot browsing). Hover and modal
  /// state are untouched since they describe external conditions.
  void resetInteraction() {
    if (_interactionTimer == null) {
      return;
    }
    _interactionTimer!.cancel();
    _interactionTimer = null;
    _evaluate();
  }

  void _onInteractionExpired() {
    _interactionTimer = null;
    _evaluate();
  }

  void _evaluate() {
    if (_anySurfaceActive()) {
      _releaseTimer?.cancel();
      _releaseTimer = null;
      if (!_state.value) {
        _state.value = true;
      }
      return;
    }

    if (!_state.value) {
      return;
    }

    if (_releaseDelay == Duration.zero) {
      _state.value = false;
      return;
    }

    // Schedule a single deferred release; re-entrant activity cancels it.
    _releaseTimer ??= Timer(_releaseDelay, _onRelease);
  }

  void _onRelease() {
    _releaseTimer = null;
    if (!_anySurfaceActive()) {
      _state.value = false;
    }
  }

  bool _anySurfaceActive() =>
      _hovering ||
      _contextMenuOpen ||
      _modalOverlayOpen ||
      (_interactionTimer?.isActive ?? false);

  void dispose() {
    _interactionTimer?.cancel();
    _releaseTimer?.cancel();
    _state.dispose();
  }
}
