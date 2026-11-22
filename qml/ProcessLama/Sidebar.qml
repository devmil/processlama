pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Templates as T
import Meridian

// The sidebar on ground: pinned processes, the live system and saved
// snapshots, and saved filters; the brand button opens About.
Item {
    id: sidebar

    readonly property var app: Store.app
    readonly property var pinned: (app.pinnedRows ?? []).slice(0, 6)
    readonly property var snapshots: (app.snapshots ?? []).slice(0, 6)
    readonly property var filters: (app.savedFilters ?? []).slice(0, 8)
    readonly property string selectedKey: Store.tree ? Store.tree.selectedKey : ""
    readonly property string loadedPath: Store.session.loadedSnapshotPath ?? ""
    property var menuSnapshot: null
    property string menuFilter: ""

    component Hint: MeridianText {
        x: Theme.space.s4
        width: parent ? parent.width - 2 * Theme.space.s4 : 0
        topPadding: Theme.space.s2
        bottomPadding: Theme.space.s2
        role: MeridianText.Caption
        color: Theme.colors.inkMuted
        wrapMode: Text.Wrap
    }

    Flickable {
        id: scroller
        MeridianWheelScroll { flickable: scroller }
        anchors.top: parent.top
        anchors.bottom: brand.top
        width: parent.width
        contentHeight: sections.height + Theme.space.s3
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        T.ScrollBar.vertical: MeridianScrollBar {}

        Column {
            id: sections
            width: scroller.width

            MeridianNavSection {
                width: parent.width
                title: L10n.t("pinned")
                Hint {
                    visible: sidebar.pinned.length === 0
                    text: L10n.t("pinRowsForQuickAccess")
                }
                Repeater {
                    model: sidebar.pinned
                    MeridianNavRow {
                        id: pinnedRow
                        required property var modelData
                        width: parent.width
                        text: modelData.name
                        trailingText: String(modelData.pid)
                        selected: sidebar.selectedKey === modelData.key
                        leadingContent: ProcessIcon {
                            width: Theme.size.iconSmall
                            height: Theme.size.iconSmall
                            name: pinnedRow.modelData.name
                            iconUrl: pinnedRow.modelData.iconUrl
                        }
                        onClicked: sidebar.app.selectProcess(modelData.key)
                    }
                }
            }

            MeridianNavSection {
                width: parent.width
                title: L10n.t("snapshots")
                actions: [
                    MeridianIconButton {
                        text: L10n.t("openSnapshot")
                        iconName: "folder-open"
                        controlSize: MeridianButton.Small
                        onGround: true
                        onClicked: Store.actions.openSnapshot()
                    },
                    MeridianIconButton {
                        text: L10n.t("takeSnapshot")
                        iconName: "plus"
                        controlSize: MeridianButton.Small
                        onGround: true
                        onClicked: Store.actions.takeSnapshot()
                    }
                ]
                MeridianNavRow {
                    width: parent.width
                    text: L10n.t("livePlatform", [Store.session.platform ?? ""])
                    iconName: "activity"
                    trailingText: L10n.t("now")
                    selected: sidebar.loadedPath.length === 0
                    onClicked: sidebar.app.showLive()
                }
                Repeater {
                    model: sidebar.snapshots
                    MeridianNavRow {
                        required property var modelData
                        width: parent.width
                        text: modelData.label
                        iconName: "history"
                        count: modelData.count
                        selected: sidebar.loadedPath === modelData.path
                        onClicked: Store.actions.loadSnapshot(modelData.path)
                        onContextMenuRequested: (x, y) => {
                            sidebar.menuSnapshot = modelData
                            snapshotMenu.popup(this, x, y)
                        }
                    }
                }
            }

            MeridianNavSection {
                width: parent.width
                title: L10n.t("filters")
                Hint {
                    visible: sidebar.filters.length === 0
                    text: L10n.t("noSavedFilters")
                }
                Repeater {
                    model: sidebar.filters
                    MeridianNavRow {
                        required property var modelData
                        width: parent.width
                        text: modelData.text
                        iconName: "list-filter"
                        count: modelData.count
                        selected: modelData.selected
                        onClicked: sidebar.app.applySavedFilter(modelData.text)
                        onContextMenuRequested: (x, y) => {
                            sidebar.menuFilter = modelData.text
                            filterMenu.popup(this, x, y)
                        }
                    }
                }
            }
        }
    }

    // The brand button: the lama signature opens About.
    T.AbstractButton {
        id: brand
        anchors.bottom: parent.bottom
        x: Theme.space.s3
        width: Theme.size.control
        height: Theme.size.control
        hoverEnabled: true
        Accessible.name: L10n.t("aboutApp")
        onClicked: Store.actions.showAbout()

        background: Rectangle {
            color: brand.hovered ? Theme.colors.groundHover : Qt.alpha(Theme.colors.groundHover, 0)
            Behavior on color { ColorAnimation { duration: Motion.hoverFor(brand.hovered) } }
            MeridianFocusRing { target: brand; shown: brand.visualFocus }
        }
        contentItem: Item {
            BrandSignature {
                anchors.centerIn: parent
                height: Theme.size.icon
                width: height * 96.7 / 89.8
                color: brand.hovered || brand.activeFocus ? Theme.colors.inkMuted : Theme.colors.inkFaint
            }
        }

        MeridianTooltip {
            text: L10n.t("brandTooltip")
            shown: brand.hovered
        }
    }

    MeridianMenu {
        id: snapshotMenu
        MeridianMenuItem {
            text: L10n.t("renameSnapshot")
            iconName: "pencil"
            onTriggered: Store.actions.renameSnapshot(sidebar.menuSnapshot)
        }
        MeridianMenuItem {
            text: L10n.t("exportSnapshot")
            iconName: "download"
            onTriggered: Store.actions.exportSnapshot(sidebar.menuSnapshot)
        }
        MeridianMenuSeparator {}
        MeridianMenuItem {
            text: L10n.t("deleteSnapshot")
            iconName: "trash-2"
            danger: true
            onTriggered: Store.actions.deleteSnapshot(sidebar.menuSnapshot)
        }
    }

    MeridianMenu {
        id: filterMenu
        MeridianMenuItem {
            text: L10n.t("deleteFilter")
            iconName: "trash-2"
            danger: true
            onTriggered: sidebar.app.removeSavedFilter(sidebar.menuFilter)
        }
    }
}
