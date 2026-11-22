pragma ComponentBehavior: Bound
import QtQuick
import Meridian

// The window's tabs: Local first and fixed, the remote tabs in a Meridian tab
// strip, a chevron menu when they do not fit, and the "+" menu.
Rectangle {
    id: strip

    readonly property var app: Store.app
    readonly property var tabs: app.tabs ?? []
    readonly property var remoteTabs: tabs.filter(tab => !tab.local)
    readonly property string activeTab: app.activeTab ?? "local"
    readonly property var profiles: (app.remoteHosts ?? {}).profiles ?? []
    readonly property var closedProfiles: profiles.filter(profile => !profile.open)
    readonly property real stripWidth: Math.max(0, width - 2 * Theme.space.s3 - localPill.width
                                                - 2 * Theme.size.controlSmall - Theme.space.s3)
    readonly property bool overflowing: remoteTabs.length * Metrics.tabPillMinWidth > stripWidth

    height: Metrics.tabStripHeight
    color: Theme.colors.ground

    Connections {
        target: Store
        function onTabMenuRequested() { strip.openMenu() }
    }

    function openMenu() {
        addMenu.popup(addButton, 0, addButton.height)
    }

    function tabEntry(tab) {
        const phase = tab.phase ?? "idle"
        return {
            id: tab.key,
            label: tab.label,
            tooltip: tab.platform ? L10n.t("remoteTabTooltip", [tab.alias, tab.platform, tab.compatibility]) : tab.alias,
            semanticLabel: L10n.t("remoteTabSemantics", [tab.label, Labels.phase(phase)]),
            dotTone: AppTheme.phaseTone(phase),
            dotHalo: phase === "live"
        }
    }

    // The Local tab: a pill that can be selected but never closed.
    Item {
        id: localPill
        readonly property bool selected: strip.activeTab === "local"
        x: Theme.space.s3
        width: Metrics.tabPillMinWidth
        height: parent.height
        Accessible.role: Accessible.PageTab
        Accessible.name: L10n.t("remoteTabLocal")
        Accessible.selected: selected
        Accessible.onPressAction: strip.app.activateTab("local")

        HoverHandler { id: localHover; cursorShape: Qt.PointingHandCursor }
        TapHandler { onTapped: strip.app.activateTab("local") }

        MeridianShadow {
            anchors.fill: pill
            visible: localPill.selected
            layers: Theme.shadows.pane
            radius: Theme.radius.md
        }
        Rectangle {
            id: pill
            anchors.centerIn: parent
            width: parent.width
            height: Metrics.tabPillHeight
            radius: Theme.radius.md
            color: localPill.selected ? Theme.colors.pane
                 : localHover.hovered ? Theme.colors.groundHover : Qt.alpha(Theme.colors.groundHover, 0)
            Behavior on color { ColorAnimation { duration: localHover.hovered ? Motion.hover : Motion.hoverOut } }

            Row {
                anchors.left: parent.left
                anchors.leftMargin: Theme.space.s4
                anchors.right: parent.right
                anchors.rightMargin: Theme.space.s4
                anchors.verticalCenter: parent.verticalCenter
                spacing: Theme.space.s3
                MeridianIcon {
                    id: monitorIcon
                    anchors.verticalCenter: parent.verticalCenter
                    name: "monitor"
                    iconSize: MeridianIcon.Small
                    color: localPill.selected ? Theme.colors.ink : Theme.colors.inkMuted
                }
                MeridianText {
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width - monitorIcon.width - parent.spacing
                    text: L10n.t("remoteTabLocal")
                    role: MeridianText.Label
                    elide: Text.ElideRight
                    color: localPill.selected || localHover.hovered ? Theme.colors.ink : Theme.colors.inkMuted
                }
            }
        }
    }

    MeridianTabStrip {
        id: remoteStrip
        visible: strip.remoteTabs.length > 0
        anchors.left: localPill.right
        anchors.verticalCenter: parent.verticalCenter
        width: Math.min(implicitWidth, strip.stripWidth)
        height: parent.height
        tabs: strip.remoteTabs.map(tab => strip.tabEntry(tab))
        activeTab: strip.activeTab
        closeLabel: L10n.t("remoteTabClose", ["%1"])
        moveLeftLabel: L10n.t("remoteTabMoveLeft")
        moveRightLabel: L10n.t("remoteTabMoveRight")
        onActivated: id => strip.app.activateTab(id)
        onCloseRequested: id => strip.app.closeTab(id)
        onMoveRequested: (id, index) => strip.app.moveTab(strip.tabs.findIndex(tab => tab.key === id), index + 1)
    }

    Row {
        anchors.right: parent.right
        anchors.rightMargin: Theme.space.s3
        anchors.verticalCenter: parent.verticalCenter
        MeridianIconButton {
            id: overflowButton
            visible: strip.overflowing
            text: L10n.t("remoteTabMore")
            iconName: "chevron-down"
            controlSize: MeridianButton.Small
            onGround: true
            onClicked: allTabsMenu.popup(overflowButton, 0, overflowButton.height)
        }
        MeridianIconButton {
            id: addButton
            text: L10n.t("remoteTabOpenMenu")
            iconName: "plus"
            controlSize: MeridianButton.Small
            onGround: true
            onClicked: strip.openMenu()
        }
    }

    MeridianMenu {
        id: allTabsMenu
        Instantiator {
            model: strip.tabs
            delegate: MeridianMenuItem {
                required property var modelData
                text: modelData.local ? L10n.t("remoteTabLocal") : modelData.label
                checked: modelData.key === strip.activeTab
                onTriggered: strip.app.activateTab(modelData.key)
            }
            onObjectAdded: (index, object) => allTabsMenu.insertItem(index, object)
            onObjectRemoved: (index, object) => allTabsMenu.removeItem(object)
        }
    }

    MeridianMenu {
        id: addMenu
        Instantiator {
            model: strip.closedProfiles
            delegate: MeridianMenuItem {
                required property var modelData
                text: modelData.displayName
                dotColor: {
                    switch (AppTheme.phaseTone(modelData.phase)) {
                    case MeridianStatusDot.Success: return Theme.colors.success
                    case MeridianStatusDot.Warning: return Theme.colors.warning
                    case MeridianStatusDot.Danger: return Theme.colors.danger
                    default: return Theme.colors.inkFaint
                    }
                }
                hint: Labels.phase(modelData.phase)
                onTriggered: strip.app.openRemoteTab(modelData.id)
            }
            onObjectAdded: (index, object) => addMenu.insertItem(index, object)
            onObjectRemoved: (index, object) => addMenu.removeItem(object)
        }
        MeridianMenuItem {
            visible: strip.closedProfiles.length === 0
            height: visible ? implicitHeight : 0
            text: L10n.t("remoteHostMenuEmpty")
        }
        MeridianMenuSeparator {}
        MeridianMenuItem {
            text: L10n.t("remoteHostAddMenu")
            iconName: "circle-plus"
            onTriggered: Store.actions.showRemoteHostEditor(null, true)
        }
        MeridianMenuItem {
            text: L10n.t("remoteHostManageMenu")
            iconName: "server"
            onTriggered: Store.actions.showPreferences(3)
        }
    }
}
