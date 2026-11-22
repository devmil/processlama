pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Window
import Meridian

// The explorer window: toolbar, workspace tabs, the sidebar, tree and
// inspector islands and the status bar, plus the dialogs and toasts.
Window {
    id: appWindow

    required property var app
    required property var treeModel
    required property var hooks
    required property string licensePackages

    readonly property var settings: app.settings ?? ({})
    property bool windowResizing: false

    width: 1180
    height: 760
    minimumWidth: 900
    minimumHeight: 560
    visible: true
    title: L10n.t("appTitle")
    color: Theme.colors.ground
    // Linux draws its own window controls in the toolbar; macOS keeps the
    // native frame with a unified toolbar.
    flags: Store.isLinux ? (Qt.Window | Qt.FramelessWindowHint) : Qt.Window

    FontLoader { source: "qrc:/ProcessLama/fonts/Geist-Regular.ttf" }
    FontLoader { source: "qrc:/ProcessLama/fonts/Geist-Medium.ttf" }
    FontLoader { source: "qrc:/ProcessLama/fonts/Geist-SemiBold.ttf" }
    FontLoader { source: "qrc:/ProcessLama/fonts/Geist-Bold.ttf" }
    FontLoader { source: "qrc:/ProcessLama/fonts/GeistMono-Regular.ttf" }
    FontLoader { source: "qrc:/ProcessLama/fonts/GeistMono-Medium.ttf" }
    FontLoader { source: "qrc:/ProcessLama/fonts/GeistMono-SemiBold.ttf" }
    FontLoader { source: "qrc:/ProcessLama/fonts/GeistMono-Bold.ttf" }

    Binding { target: Theme; property: "brand"; value: "mimameidr" }
    Binding {
        target: Theme
        property: "mode"
        value: appWindow.settings.appearanceMode === "light" ? Theme.Light
             : appWindow.settings.appearanceMode === "dark" ? Theme.Dark : Theme.System
    }
    Binding {
        target: Theme
        property: "density"
        value: appWindow.settings.rowDensity === "regular" ? Theme.Regular
             : appWindow.settings.rowDensity === "comfortable" ? Theme.Comfortable : Theme.Compact
    }
    Binding { target: L10n; property: "language"; value: appWindow.settings.languageCode ?? "en" }

    Component.onCompleted: {
        Store.app = app
        Store.tree = treeModel
        Store.actions = actions
        Theme.reducedMotion = hooks.reduceMotion()
        Theme.textScale = hooks.textScale()
        Qt.callLater(() => appWindow.hooks.configureWindow())
        if (app.startupSnapshot.length > 0)
            app.openSnapshot(app.startupSnapshot)
        const request = hooks.screenshotRequest()
        if (request.length > 0)
            screenshot.start(request)
    }

    // Development: saves the window (after an optional action) and quits.
    Timer {
        id: screenshot
        property string path
        property var steps: []
        interval: 2500
        function start(request) {
            const parts = request.split(";")
            path = parts[0]
            steps = parts.slice(1)
            restart()
        }
        onTriggered: {
            const step = steps.shift()
            if (step !== undefined) {
                const [name, argument] = step.split(":")
                switch (name) {
                case "preferences": actions.showPreferences(Number(argument ?? 0)); break
                case "about": actions.showAbout(); break
                case "licenses": actions.showLicenses(); break
                case "inspector": Store.inspectorTab = Number(argument ?? 0); break
                case "select": appWindow.app.selectNextVisible(); break
                case "search": appWindow.app.setTreeSearch(argument ?? ""); Store.requestTreeSearch(); break
                case "filter": appWindow.app.setFilter(argument ?? ""); break
                case "menu": Store.requestTabMenu(); break
                case "dark": appWindow.app.setAppearance("dark"); break
                case "light": appWindow.app.setAppearance("light"); break
                case "editor": actions.showRemoteHostEditor(null, false); break
                case "freeze": appWindow.app.toggleFrozen(); break
                case "inspector-off": Store.inspectorOpen = false; break
                case "focus": appWindow.app.focusSelectedSubtree(); break
                case "wait": break
                }
                interval = 1200
                restart()
                return
            }
            if (path === "-")
                return
            appWindow.contentItem.grabToImage(result => {
                result.saveToFile(path)
                Qt.quit()
            })
        }
    }

    onClosing: app.flushSettings()

    // Resizing pauses sampling; the last resize event resumes it.
    onWidthChanged: _resized()
    onHeightChanged: _resized()
    function _resized() {
        if (!Store.app)
            return
        if (!windowResizing) {
            windowResizing = true
            app.setWindowResizing(true)
        }
        resizeEnd.restart()
    }
    Timer {
        id: resizeEnd
        interval: 200
        onTriggered: {
            appWindow.windowResizing = false
            appWindow.app.setWindowResizing(false)
            appWindow.app.refresh()
        }
    }

    Shortcut { sequence: "F11"; onActivated: appWindow.visibility === Window.FullScreen ? appWindow.showNormal() : appWindow.showFullScreen() }
    Shortcut { sequences: [StandardKey.Find]; context: Qt.ApplicationShortcut; onActivated: Store.requestTreeSearch() }
    Shortcut { sequence: "Ctrl+T"; onActivated: Store.requestTabMenu() }
    Shortcut { sequence: "Ctrl+Shift+["; onActivated: appWindow.app.cycleTabs(true) }
    Shortcut { sequence: "Ctrl+Shift+]"; onActivated: appWindow.app.cycleTabs(false) }
    Shortcut { sequence: "Ctrl+{"; onActivated: appWindow.app.cycleTabs(true) }
    Shortcut { sequence: "Ctrl+}"; onActivated: appWindow.app.cycleTabs(false) }
    Repeater {
        model: 9
        Item {
            id: digit
            required property int index
            Shortcut {
                sequence: "Ctrl+" + (digit.index + 1)
                onActivated: appWindow.app.activateTabIndex(digit.index)
            }
        }
    }

    MeridianGround { anchors.fill: parent }

    Loader {
        id: content
        anchors.fill: parent
        active: Store.app !== null
        sourceComponent: ExplorerScreen {}
    }

    LinuxResizeEdges {
        anchors.fill: parent
        visible: Store.isLinux && appWindow.visibility === Window.Windowed
    }

    Actions {
        id: actions
        window: appWindow
        licensePackages: appWindow.licensePackages
    }

    MeridianToastHost {
        id: toasts
        anchors.fill: parent
        z: 1000
    }

    Connections {
        target: appWindow.app
        function onToast(key, args, tone) {
            actions.toast(Labels.toast(key, args), tone)
        }
        function onUpdateAvailable(installedVersion, installedBuild, version, build) {
            actions.showUpdateAvailable(installedVersion, installedBuild, version, build)
        }
        function onConfirmHelperInstall(prompt) {
            actions.showHelperInstall(prompt)
        }
        function onCopyToClipboard(text, toastKey) {
            actions.copy(text, toastKey)
        }
    }

    function showToast(message, tone) {
        toasts.show(message, tone === "success" ? MeridianToast.Success
                           : tone === "error" ? MeridianToast.Error : MeridianToast.Neutral)
    }
}
