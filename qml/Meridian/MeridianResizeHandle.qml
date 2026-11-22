import QtQuick

// Resizes the islands on either side of its gutter (Flutter:
// MeridianResizeHandle): the `space-3` gap, invisible at rest. Hover grows a
// 2px `accent` rule from the centre after 150 ms, dragging keeps it
// `accent`, keyboard focus `focus`. `dragged(delta)` reports the movement
// along the axis; arrow keys move `keyboardStep`; double click or Enter
// emits `reset`.
Item {
    id: root

    property string semanticLabel
    property bool vertical: false
    property real thickness: Theme.space.s3
    property real keyboardStep: Metrics.resizeKeyboardStep

    signal dragged(real delta)
    signal dragStarted()
    signal dragFinished()
    signal reset()

    readonly property bool dragging: drag.active
    readonly property bool keyboardFocused: activeFocus && focusReason !== Qt.MouseFocusReason
    property int focusReason: Qt.OtherFocusReason
    property real _grow: 0

    implicitWidth: vertical ? 0 : thickness
    implicitHeight: vertical ? thickness : 0
    activeFocusOnTab: true

    Accessible.role: Accessible.Slider
    Accessible.name: semanticLabel

    Keys.onPressed: event => {
        const back = vertical ? Qt.Key_Up : Qt.Key_Left
        const forward = vertical ? Qt.Key_Down : Qt.Key_Right
        if (event.key === back) {
            dragged(-keyboardStep)
            event.accepted = true
        } else if (event.key === forward) {
            dragged(keyboardStep)
            event.accepted = true
        } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
            reset()
            event.accepted = true
        }
    }
    onActiveFocusChanged: if (!activeFocus) focusReason = Qt.OtherFocusReason

    Timer {
        id: hoverDelay
        interval: Motion.spinnerDelay
        onTriggered: {
            if (hover.hovered) {
                grow.to = 1
                grow.restart()
            }
        }
    }
    NumberAnimation {
        id: grow
        target: root
        property: "_grow"
        duration: to > root._grow ? Motion.quick : Motion.exit
        easing.type: Easing.BezierSpline
        easing.bezierCurve: to > root._grow ? Motion.standard : Motion.exitCurve
    }

    HoverHandler {
        id: hover
        cursorShape: root.vertical ? Qt.SplitVCursor : Qt.SplitHCursor
        onHoveredChanged: {
            if (hovered) {
                hoverDelay.restart()
            } else {
                hoverDelay.stop()
                grow.to = 0
                grow.restart()
            }
        }
    }
    DragHandler {
        id: drag
        target: null
        xAxis.enabled: !root.vertical
        yAxis.enabled: root.vertical
        dragThreshold: 0
        cursorShape: root.vertical ? Qt.SplitVCursor : Qt.SplitHCursor
        property real last: 0
        onActiveChanged: {
            if (active) {
                last = 0
                root.dragStarted()
            } else {
                root.dragFinished()
            }
        }
        onActiveTranslationChanged: {
            const value = root.vertical ? activeTranslation.y : activeTranslation.x
            const delta = value - last
            last = value
            if (delta !== 0)
                root.dragged(delta)
        }
    }
    TapHandler {
        onDoubleTapped: root.reset()
        onTapped: root.focusReason = Qt.MouseFocusReason
    }

    Rectangle {
        anchors.centerIn: parent
        readonly property bool full: root.dragging || root.keyboardFocused
        width: root.vertical ? (parent.width - 2 * Theme.space.s5) * (full ? 1 : root._grow) : Metrics.resizeRule
        height: root.vertical ? Metrics.resizeRule : (parent.height - 2 * Theme.space.s5) * (full ? 1 : root._grow)
        radius: Metrics.resizeRule / 2
        color: root.dragging ? Theme.colors.accent
             : root.keyboardFocused ? Theme.colors.focus
             : hover.hovered ? Theme.colors.accent
             : Theme.clear(Theme.colors.accent)
        Behavior on color { ColorAnimation { duration: Motion.hoverFor(hover.hovered || root.dragging) } }
    }
}
