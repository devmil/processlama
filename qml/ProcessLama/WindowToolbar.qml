pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Window
import Meridian

// The unified title bar and toolbar on ground: the window's name and source,
// the filter field, and the commands. The background moves the window; on
// Linux the window controls sit at its right edge.
Item {
    id: toolbar

    readonly property var app: Store.app
    readonly property var session: Store.session
    readonly property var settings: Store.settings
    readonly property bool showLabels: width >= AppTheme.toolbarLabelBreakpoint
    readonly property var pollingChoices: {
        const values = [500, 1000, 2000, 5000]
        const current = settings.pollingIntervalMs ?? 1000
        if (values.indexOf(current) < 0)
            values.push(current)
        return values.sort((a, b) => a - b)
    }

    height: Theme.size.toolbar

    // Drag to move; double-click maximizes like a native title bar.
    Item {
        anchors.fill: parent
        DragHandler {
            target: null
            grabPermissions: PointerHandler.TakeOverForbidden
            onActiveChanged: if (active) toolbar.Window.window.startSystemMove()
        }
        TapHandler {
            acceptedButtons: Qt.LeftButton
            onDoubleTapped: toolbar.toggleMaximized()
        }
    }

    function toggleMaximized() {
        const window = Window.window
        if (window.visibility === Window.Maximized)
            window.showNormal()
        else
            window.showMaximized()
    }

    Row {
        id: leading
        anchors.left: parent.left
        anchors.leftMargin: Store.isMac ? AppTheme.macTrafficLightsEnd + Theme.space.s7 : Theme.space.s6
        anchors.verticalCenter: parent.verticalCenter
        spacing: 0

        // The window's name and what it shows; clicks pass through to the
        // drag area.
        Column {
            id: title
            anchors.verticalCenter: parent.verticalCenter
            width: Math.min(180, Math.max(appName.implicitWidth, source.implicitWidth))
            MeridianText {
                id: appName
                width: parent.width
                text: L10n.t("appTitle")
                role: MeridianText.BodyStrong
                elide: Text.ElideRight
            }
            MeridianText {
                id: source
                width: parent.width
                text: Store.live ? L10n.t("livePlatform", [toolbar.session.platform ?? ""]) : (toolbar.session.sourceLabel ?? "")
                role: MeridianText.Caption
                color: Theme.colors.inkMuted
                elide: Text.ElideRight
            }
        }

        Item { width: Theme.space.s7; height: 1 }

        FilterField {
            id: filter
            anchors.verticalCenter: parent.verticalCenter
            // Shares the free space with the spacer before the commands, up
            // to its maximum.
            width: Math.max(0, Math.min(AppTheme.searchMaxWidth,
                (trailing.x - leading.x - title.width - Theme.space.s7 - Theme.space.s2 - filterButtons.width) / 2))
        }

        Item { width: Theme.space.s2; height: 1 }

        Row {
            id: filterButtons
            anchors.verticalCenter: parent.verticalCenter
            MeridianIconButton {
                text: L10n.t("saveCurrentFilter")
                iconName: "bookmark-plus"
                enabled: (toolbar.session.filter ?? "").length > 0
                onClicked: toolbar.app.saveCurrentFilter()
            }
            MeridianIconButton {
                id: savedButton
                text: L10n.t("savedFilters")
                iconName: "list-filter"
                disabledReason: L10n.t("noSavedFilters")
                enabled: (toolbar.app.savedFilters ?? []).length > 0
                onClicked: savedMenu.popup(savedButton, 0, savedButton.height)
            }
        }
    }

    MeridianMenu {
        id: savedMenu
        Instantiator {
            model: toolbar.app.savedFilters ?? []
            delegate: MeridianMenuItem {
                required property var modelData
                text: modelData.text
                checked: modelData.selected
                onTriggered: toolbar.app.applySavedFilter(modelData.text)
            }
            onObjectAdded: (index, object) => savedMenu.insertItem(index, object)
            onObjectRemoved: (index, object) => savedMenu.removeItem(object)
        }
    }

    Row {
        id: trailing
        anchors.right: parent.right
        anchors.rightMargin: Theme.space.s5
        anchors.verticalCenter: parent.verticalCenter
        spacing: 0

        MeridianSelect {
            anchors.verticalCenter: parent.verticalCenter
            label: L10n.t("pollingInterval")
            value: toolbar.settings.pollingIntervalMs ?? 1000
            values: toolbar.pollingChoices
            valueLabel: v => v + " ms"
            onActivated: value => toolbar.app.setPollingInterval(value)
        }

        Item { width: Theme.space.s5; height: 1 }

        MeridianToolbarButton {
            anchors.verticalCenter: parent.verticalCenter
            readonly property bool frozen: toolbar.session.frozen ?? false
            text: L10n.t("toolbarLock")
            tooltip: frozen ? L10n.t("unlockProcessTree") : L10n.t("lockProcessTree")
            iconName: frozen ? "lock" : "lock-open"
            selected: frozen
            showLabel: toolbar.showLabels
            onClicked: toolbar.app.toggleFrozen()
        }
        MeridianToolbarButton {
            anchors.verticalCenter: parent.verticalCenter
            text: L10n.t("toolbarSnapshot")
            tooltip: L10n.t("takeSnapshot")
            iconName: "camera"
            showLabel: toolbar.showLabels
            menuLabel: L10n.t("snapshotOptions")
            onClicked: Store.actions.takeSnapshot()
            menu: MeridianMenu {
                MeridianMenuItem {
                    text: L10n.t("takeSnapshot")
                    iconName: "camera"
                    onTriggered: Store.actions.takeSnapshot()
                }
                MeridianMenuItem {
                    text: L10n.t("openSnapshot")
                    iconName: "folder-open"
                    onTriggered: Store.actions.openSnapshot()
                }
            }
        }
        MeridianToolbarButton {
            anchors.verticalCenter: parent.verticalCenter
            visible: Store.platform.updateSupported ?? false
            text: L10n.t("toolbarUpdates")
            tooltip: L10n.t("checkForUpdates")
            iconName: "download"
            showLabel: toolbar.showLabels
            onClicked: Store.actions.checkForUpdates()
        }
        MeridianToolbarButton {
            anchors.verticalCenter: parent.verticalCenter
            text: L10n.t("inspector")
            tooltip: Store.inspectorOpen ? L10n.t("hideInspector") : L10n.t("showInspector")
            iconName: "panel-right"
            selected: Store.inspectorOpen
            showLabel: toolbar.showLabels
            onClicked: Store.inspectorOpen = !Store.inspectorOpen
        }
        MeridianToolbarButton {
            anchors.verticalCenter: parent.verticalCenter
            text: L10n.t("preferences")
            iconName: "settings"
            showLabel: toolbar.showLabels
            menuLabel: L10n.t("morePreferencesOptions")
            onClicked: Store.actions.showPreferences(0)
            menu: Store.isLinux ? linuxPreferencesMenu : null
        }

        Item { visible: Store.isLinux; width: Theme.space.s3; height: 1 }
        MeridianIconButton {
            anchors.verticalCenter: parent.verticalCenter
            visible: Store.isLinux
            text: L10n.t("minimizeWindow")
            iconName: "minus"
            onClicked: toolbar.Window.window.showMinimized()
        }
        MeridianIconButton {
            anchors.verticalCenter: parent.verticalCenter
            visible: Store.isLinux
            text: L10n.t("maximizeWindow")
            iconName: "square"
            onClicked: toolbar.toggleMaximized()
        }
        MeridianIconButton {
            anchors.verticalCenter: parent.verticalCenter
            visible: Store.isLinux
            text: L10n.t("closeWindow")
            iconName: "x"
            onClicked: toolbar.Window.window.close()
        }
    }

    MeridianMenu {
        id: linuxPreferencesMenu
        MeridianMenuItem {
            text: L10n.t("installNetworkTelemetry")
            iconName: "download"
            onTriggered: Store.actions.installNetworkTelemetry()
        }
    }
}
