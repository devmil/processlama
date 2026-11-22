import QtQuick
import QtTest

// Pointer handlers declared inside a TableView attach to its content item:
// their `position` already scrolls with the rows. ProcessTable maps scene
// positions onto the content item instead of adding contentY again.
Item {
    id: host
    width: 400
    height: 300

    TableView {
        id: table
        anchors.fill: parent
        model: 200
        rowHeightProvider: () => 20
        columnWidthProvider: () => 400
        delegate: Rectangle { implicitWidth: 400; implicitHeight: 20 }

        HoverHandler { id: hover }
    }

    function rowAtScene(scenePosition) {
        const local = table.contentItem.mapFromItem(null, scenePosition.x, scenePosition.y)
        return Math.floor(local.y / 20)
    }

    TestCase {
        name: "TablePointer"
        when: windowShown

        function test_scrolled_pointer_maps_to_the_row_under_it() {
            table.contentY = 400
            wait(50)
            mouseMove(host, 50, 30)
            tryVerify(() => hover.hovered)
            // 30px into the viewport, scrolled by 20 rows of 20px: row 21.
            compare(host.rowAtScene(hover.point.scenePosition), 21)
            // The handler's own position is already in content coordinates.
            compare(Math.floor(hover.point.position.y / 20), 21)
        }
    }
}
