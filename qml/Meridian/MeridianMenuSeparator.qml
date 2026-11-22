import QtQuick
import QtQuick.Templates as T

// Splits menu groups; destructive commands follow the last one.
T.MenuSeparator {
    implicitWidth: Metrics.menuMinWidth
    implicitHeight: Theme.space.s4 + 1
    padding: 0
    contentItem: Rectangle {
        implicitHeight: 1
        x: Theme.space.s4
        width: parent ? parent.width - 2 * Theme.space.s4 : 0
        color: Theme.colors.line
    }
}
