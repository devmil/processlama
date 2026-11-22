pragma ComponentBehavior: Bound
import QtQuick
import Meridian

// The tree island: the subtree focus bar, the pinned strip and the process
// table, or the empty state when nothing matches.
MeridianIsland {
    id: island

    readonly property var app: Store.app
    readonly property var session: Store.session
    readonly property bool empty: Store.tree ? Store.tree.rowTotal === 0 : true
    readonly property var pinned: app.pinnedRows ?? []

    // Shows the focused subtree with the way back.
    Rectangle {
        id: focusBar
        visible: island.session.focused ?? false
        width: parent.width
        height: visible ? Theme.size.islandHeader : 0
        color: Theme.colors.accentSoft
        MeridianHairline {
            anchors.bottom: parent.bottom
            width: parent.width
        }
        MeridianIcon {
            id: focusIcon
            x: Theme.space.s5
            anchors.verticalCenter: parent.verticalCenter
            name: "list-tree"
            iconSize: MeridianIcon.Small
            color: Theme.colors.accentInk
        }
        MeridianText {
            anchors.left: focusIcon.right
            anchors.leftMargin: Theme.space.s4
            anchors.right: focusButtons.left
            anchors.verticalCenter: parent.verticalCenter
            role: MeridianText.BodyStrong
            elide: Text.ElideRight
            text: L10n.t("focusedOnSubtree", [island.session.focusedName ?? L10n.t("subtree")])
        }
        Row {
            id: focusButtons
            anchors.right: parent.right
            anchors.rightMargin: Theme.space.s3
            anchors.verticalCenter: parent.verticalCenter
            spacing: Theme.space.s1
            readonly property bool root: (island.session.focusStackDepth ?? 0) === 0
            MeridianIconButton {
                anchors.verticalCenter: parent.verticalCenter
                text: focusButtons.root ? L10n.t("leaveSubtreeFocus") : L10n.t("backOneSubtree")
                iconName: focusButtons.root ? "x" : "arrow-left"
                controlSize: MeridianButton.Small
                surfaceColor: Theme.colors.accentSoft
                onClicked: focusButtons.root ? island.app.clearSubtreeFocus() : island.app.popSubtreeFocus()
            }
            MeridianButton {
                anchors.verticalCenter: parent.verticalCenter
                text: L10n.t("showFullTree")
                iconName: "list-tree"
                controlSize: MeridianButton.Small
                variant: MeridianButton.Quiet
                surfaceColor: Theme.colors.accentSoft
                onClicked: island.app.clearSubtreeFocus()
            }
        }
    }

    Column {
        anchors.centerIn: parent
        anchors.verticalCenterOffset: focusBar.height / 2
        visible: island.empty
        width: Math.min(parent.width - 2 * Theme.space.s6, Metrics.emptyStateMaxWidth)
        Image {
            anchors.horizontalCenter: parent.horizontalCenter
            source: "qrc:/ProcessLama/brand/lama-resting.svg"
            height: AppTheme.emptyLamaHeight
            fillMode: Image.PreserveAspectFit
            sourceSize.height: height * 2
            Accessible.ignored: true
        }
        MeridianEmptyState {
            width: parent.width
            iconName: "text-search"
            title: L10n.t("noProcessesMatchFilter")
            message: L10n.t("filterNoMatchesHelp")
        }
    }

    // Pinned processes as chips above the table.
    ListView {
        id: pinnedStrip
        visible: !island.empty && island.pinned.length > 0
        y: focusBar.height
        width: parent.width
        height: visible ? Metrics.chipHeight + 2 * Theme.space.s3 : 0
        orientation: ListView.Horizontal
        leftMargin: Theme.space.s3
        rightMargin: Theme.space.s3
        topMargin: Theme.space.s3
        spacing: Theme.space.s3
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        model: island.pinned
        delegate: MeridianChip {
            required property var modelData
            text: modelData.name
            iconName: "pin"
            interactive: true
            selected: Store.tree.selectedKey === modelData.key
            onClicked: island.app.selectProcess(modelData.key)
        }
    }

    ProcessTable {
        id: table
        visible: !island.empty
        y: pinnedStrip.y + pinnedStrip.height
        width: parent.width
        height: parent.height - y
        focus: true
        islandFocused: island.focused
    }
}
