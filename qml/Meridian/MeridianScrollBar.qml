import QtQuick
import QtQuick.Templates as T

// Meridian's scrollbar (Flutter: MeridianScrollbarThumb): a pill thumb in
// `line-strong` that thickens and darkens to `control-edge` on hover or
// drag, no track, fading out 600 ms after scrolling stops.
T.ScrollBar {
    id: control

    /// Keep it visible (hover visibility is the default).
    property bool alwaysShown: false
    readonly property bool emphasized: hovered || pressed
    /// The view scrolled recently without a flick (wheel, keys, code):
    /// Qt marks the bar `active` only while the view is moving.
    property bool scrolled: false

    readonly property Flickable _view: parent as Flickable
    Connections {
        target: control._view
        function onContentYChanged() { if (control.orientation === Qt.Vertical) control._noteScroll() }
        function onContentXChanged() { if (control.orientation === Qt.Horizontal) control._noteScroll() }
    }
    function _noteScroll() {
        scrolled = true
        scrolledTimer.restart()
    }
    Timer {
        id: scrolledTimer
        interval: 100
        onTriggered: control.scrolled = false
    }
    property real _emphasis: emphasized ? 1 : 0
    Behavior on _emphasis { NumberAnimation { duration: Motion.overlay } }

    readonly property real thickness: Metrics.scrollbarThickness
        + (Metrics.scrollbarThicknessHover - Metrics.scrollbarThickness) * _emphasis

    hoverEnabled: true
    minimumSize: orientation === Qt.Horizontal ? height / Math.max(1, width) : width / Math.max(1, height)
    implicitWidth: orientation === Qt.Vertical ? Metrics.scrollbarThicknessHover + 2 * Metrics.scrollbarMargin : 100
    implicitHeight: orientation === Qt.Horizontal ? Metrics.scrollbarThicknessHover + 2 * Metrics.scrollbarMargin : 100
    padding: Metrics.scrollbarMargin
    visible: size < 1
    policy: T.ScrollBar.AsNeeded

    contentItem: Item {
        id: thumb
        implicitWidth: control.thickness
        implicitHeight: Metrics.scrollbarMinLength
        // Lingers 600 ms after the last reason to show, then fades. A
        // timer rather than a paused animation: a Behavior restarted during
        // its pause could leave the thumb invisible while scrolling.
        readonly property bool wanted: control.alwaysShown || control.active || control.emphasized || control.scrolled
        readonly property bool shown: wanted || linger.running
        onWantedChanged: if (!wanted) linger.restart()
        Timer { id: linger; interval: 600 }
        opacity: shown ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: 300 } }
        Rectangle {
            anchors.right: control.orientation === Qt.Vertical ? parent.right : undefined
            anchors.bottom: control.orientation === Qt.Horizontal ? parent.bottom : undefined
            width: control.orientation === Qt.Vertical ? control.thickness : parent.width
            height: control.orientation === Qt.Horizontal ? control.thickness : Math.max(Metrics.scrollbarMinLength, parent.height)
            radius: control.thickness / 2
            color: control.pressed ? Theme.colors.controlEdge : Theme.blend(Theme.colors.lineStrong, Theme.colors.controlEdge, control._emphasis)
        }
    }
}
