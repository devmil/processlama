import QtQuick
import QtTest

// ProcessTable's header cells have a reorder DragHandler and, on their right
// divider, a resize grip with its own DragHandler. Both see a press on the
// grip and the reorder drag takes the grab first, so the table turns the
// reorder drag off while a grip is under the pointer. This mirrors that
// arrangement, including the header's TapHandlers.
Item {
    id: host
    width: 400
    height: 100
    property var widths: [150, 150]
    property string reordered: ""
    property string gripColumn: ""

    Row {
        height: 30
        Repeater {
            model: 2
            Item {
                id: cell
                required property int index
                readonly property string columnId: "c" + index
                width: host.widths[index]
                height: 30
                z: 2 - index

                TapHandler { gesturePolicy: TapHandler.ReleaseWithinBounds }
                DragHandler {
                    enabled: host.gripColumn.length === 0
                    target: null
                    yAxis.enabled: false
                    onActiveChanged: if (active) host.reordered = cell.columnId
                }
                Item {
                    anchors.right: parent.right
                    anchors.rightMargin: -width / 2
                    width: 24
                    height: parent.height
                    HoverHandler {
                        id: gripHover
                        onHoveredChanged: {
                            if (hovered)
                                host.gripColumn = cell.columnId
                            else if (!grip.active && host.gripColumn === cell.columnId)
                                host.gripColumn = ""
                        }
                    }
                    TapHandler {}
                    DragHandler {
                        id: grip
                        property real startWidth: 0
                        target: null
                        yAxis.enabled: false
                        onActiveChanged: {
                            if (active)
                                startWidth = cell.width
                            else if (host.gripColumn === cell.columnId && !gripHover.hovered)
                                host.gripColumn = ""
                        }
                        onTranslationChanged: {
                            if (!active)
                                return
                            const widths = host.widths.slice()
                            widths[cell.index] = startWidth + translation.x
                            host.widths = widths
                        }
                    }
                }
            }
        }
    }

    TestCase {
        name: "HeaderGrip"
        when: windowShown

        function init() {
            host.widths = [150, 150]
            host.reordered = ""
            mouseMove(host, 300, 80)
        }

        function drag(fromX, toX) {
            mouseMove(host, fromX, 15)
            wait(20)
            mousePress(host, fromX, 15)
            for (let i = 1; i <= 10; ++i) {
                mouseMove(host, fromX + (toX - fromX) * i / 10, 15)
                wait(10)
            }
            mouseRelease(host, toX, 15)
        }

        function test_dragging_the_divider_resizes() {
            drag(148, 188)
            compare(host.reordered, "")
            compare(host.widths[0], 190)
        }

        function test_dragging_the_label_reorders() {
            drag(60, 200)
            compare(host.reordered, "c0")
            compare(host.widths[0], 150)
        }
    }
}
