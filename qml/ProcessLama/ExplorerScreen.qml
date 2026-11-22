import QtQuick
import Meridian

// Toolbar, workspace tabs, the remote banner, the sidebar | tree | inspector
// row and the status bar.
Item {
    id: screen

    readonly property var app: Store.app
    readonly property real savedInspectorWidth: Store.settings.inspectorWidth ?? 360
    // A drag resizes locally and commits once on release: a round trip
    // through the core and the open/close animation per pointer event made
    // the inspector trail the pointer.
    property real dragInspectorWidth: -1
    readonly property real inspectorWidth: dragInspectorWidth >= 0 ? dragInspectorWidth : savedInspectorWidth
    readonly property real minInspectorWidth: 240
    readonly property real maxInspectorWidth: 720

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
            onDragStarted: {
                screen.dragInspectorWidth = screen.savedInspectorWidth
                screen.app.setWindowResizing(true)
            }
            onDragged: delta => {
                const width = Math.max(screen.minInspectorWidth, Math.min(screen.maxInspectorWidth, screen.inspectorWidth - delta))
                if (dragging)
                    screen.dragInspectorWidth = width
                else
                    screen.app.setInspectorWidth(width)
            }
            onDragFinished: {
                screen.app.setInspectorWidth(screen.dragInspectorWidth)
                screen.app.setWindowResizing(false)
                // The local width yields once the committed one comes back.
                if (Math.abs(screen.savedInspectorWidth - screen.dragInspectorWidth) < 0.5)
                    screen.dragInspectorWidth = -1
            }
            onReset: screen.app.resetInspectorWidth()
        }

        // Clips the sliding inspector to its animated width while leaving
        // room for the island's shadow.
        Item {
            id: inspectorHost
            property real openWidth: Store.inspectorOpen ? screen.inspectorWidth : 0
            Behavior on openWidth {
                enabled: screen.dragInspectorWidth < 0
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

    onSavedInspectorWidthChanged: if (!resize.dragging) dragInspectorWidth = -1

    ExplorerStatusBar {
        id: statusBar
        anchors.bottom: parent.bottom
        width: parent.width
    }
}
