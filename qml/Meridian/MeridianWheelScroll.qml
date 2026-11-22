import QtQuick

// Desktop wheel scrolling for a Flickable, ListView or TableView. Declare it
// inside the view: `MeridianWheelScroll { flickable: view }`.
//
// Qt Quick turns each wheel notch into a velocity-capped flick, so a fast
// wheel spin barely outruns a single notch. This moves the content by
// `wheelScrollLines` lines per notch instead, adds notches linearly and
// follows touchpad pixel deltas one to one. On Qt Wayland, which sends no
// inertia, lifting the fingers flicks with their last speed; other platforms
// deliver their own momentum (`ScrollMomentum`), which it follows instead. Shift, or a view that only scrolls sideways, turns vertical wheel
// motion horizontal.
WheelHandler {
    id: scroller

    required property Flickable flickable
    /// The distance of one line; a notch moves `wheelScrollLines` of them.
    property real lineHeight: 20

    /// Synthetic touchpad momentum: only Qt Wayland lacks native inertia.
    property bool syntheticMomentum: Qt.platform.pluginName === "wayland" && !Motion.reduced

    property real _vx: 0
    property real _vy: 0
    property real _time: 0

    target: null
    acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad

    function _clamp(value, origin, size, before, after, extent) {
        const low = origin - before
        return Math.max(low, Math.min(value, Math.max(low, origin + size + after - extent)))
    }

    function scrollBy(dx, dy) {
        const f = flickable
        if (dx !== 0 && f.contentWidth > f.width)
            f.contentX = _clamp(f.contentX - dx, f.originX, f.contentWidth, f.leftMargin, f.rightMargin, f.width)
        if (dy !== 0)
            f.contentY = _clamp(f.contentY - dy, f.originY, f.contentHeight, f.topMargin, f.bottomMargin, f.height)
    }

    onWheel: event => {
        const f = flickable
        if (!f || !f.interactive)
            return
        const pixels = event.pixelDelta.x !== 0 || event.pixelDelta.y !== 0
        let dx, dy
        if (pixels) {
            dx = event.pixelDelta.x
            dy = event.pixelDelta.y
        } else {
            const step = Application.styleHints.wheelScrollLines * lineHeight / 120
            dx = event.angleDelta.x * step
            dy = event.angleDelta.y * step
        }
        // Shift, or a view that only scrolls sideways, turns the wheel horizontal.
        const sideways = f.contentWidth > f.width && f.contentHeight + f.topMargin + f.bottomMargin <= f.height
        if ((sideways || (event.modifiers & Qt.ShiftModifier)) && dx === 0) {
            dx = dy
            dy = 0
        }
        if (dx !== 0 || dy !== 0) {
            f.cancelFlick()
            scrollBy(dx, dy)
        }
        if (event.phase === Qt.ScrollMomentum) {
            // The platform's own inertia: no synthetic flick after it.
            _vx = _vy = 0
        } else if (event.phase === Qt.ScrollEnd) {
            // Fingers lifted: hand the last speed to a flick.
            if (syntheticMomentum && (Math.abs(_vx) > 50 || Math.abs(_vy) > 50))
                f.flick(_vx, _vy)
            _vx = _vy = 0
        } else if (pixels) {
            const now = Date.now()
            const dt = Math.max(1, now - _time)
            if (event.phase === Qt.ScrollBegin || dt > 100)
                _vx = _vy = 0
            // Smoothed speed in px/s, for the flick at ScrollEnd.
            _vx = 0.6 * (dx * 1000 / dt) + 0.4 * _vx
            _vy = 0.6 * (dy * 1000 / dt) + 0.4 * _vy
            _time = now
        }
    }
}
