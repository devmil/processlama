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
        implicitWidth: control.thickness
        implicitHeight: Metrics.scrollbarMinLength
        opacity: control.alwaysShown || control.active || control.emphasized ? 1 : 0
        Behavior on opacity {
            SequentialAnimation {
                PauseAnimation { duration: control.active || control.emphasized ? 0 : 600 }
                NumberAnimation { duration: 300 }
            }
        }
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
