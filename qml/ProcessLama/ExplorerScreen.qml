import QtQuick
import Meridian

// Toolbar, workspace tabs, the remote banner, the sidebar | tree | inspector
// row and the status bar.
Item {
    id: screen

    readonly property var app: Store.app
    readonly property real inspectorWidth: Store.settings.inspectorWidth ?? 360

    WindowToolbar {
        id: toolbar
        width: parent.width
    }

    WorkspaceTabStrip {
        id: tabStrip
        anchors.top: toolbar.bottom
        width: parent.width
    }

    RemoteTabBanner {
        id: banner
        anchors.top: tabStrip.bottom
        width: parent.width
    }

    Item {
        id: body
        anchors.top: banner.bottom
        anchors.bottom: statusBar.top
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.leftMargin: Theme.space.s3
        anchors.rightMargin: Theme.space.s3

        Sidebar {
            id: sidebar
            width: AppTheme.sidebarWidth
            height: parent.height
        }

        TreeIsland {
            id: treeIsland
            x: sidebar.width + Theme.space.s3
            width: Math.max(0, inspectorHost.x - x - (Store.inspectorOpen ? resize.width : 0))
            height: parent.height
        }

        // The inspector is the right island: dragging left widens it.
        MeridianResizeHandle {
            id: resize
            visible: Store.inspectorOpen
            x: inspectorHost.x - width
            height: parent.height
            semanticLabel: L10n.t("resizeInspector")
            onDragged: delta => screen.app.setInspectorWidth(screen.inspectorWidth - delta)
            onReset: screen.app.resetInspectorWidth()
        }

        // Clips the sliding inspector to its animated width while leaving
        // room for the island's shadow.
        Item {
            id: inspectorHost
            property real openWidth: Store.inspectorOpen ? screen.inspectorWidth : 0
            Behavior on openWidth {
                NumberAnimation { duration: Motion.emphasized; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.standard }
            }
            x: parent.width - openWidth
            width: openWidth
            height: parent.height

            Item {
                anchors.fill: parent
                anchors.margins: -Theme.space.s2
                clip: true
                Inspector {
                    x: Theme.space.s2
                    y: Theme.space.s2
                    width: screen.inspectorWidth
                    height: inspectorHost.height
                    visible: opacity > 0
                    opacity: Store.inspectorOpen ? 1 : 0
                    Behavior on opacity { NumberAnimation { duration: Motion.emphasized } }
                }
            }
        }
    }

    ExplorerStatusBar {
        id: statusBar
        anchors.bottom: parent.bottom
        width: parent.width
    }
}
