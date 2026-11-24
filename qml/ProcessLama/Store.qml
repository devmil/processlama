pragma Singleton
import QtQuick

// The window's bridge objects, set once by Main before the content loads, so
// every component reads the same state and sends the same commands.
QtObject {
    /// The AppState bridge: projections and commands.
    property var app: null
    /// The ProcessTreeModel bridge: the active tab's visible rows.
    property var tree: null
    /// The window's dialog and toast orchestration (Actions.qml).
    property var actions: null
    /// Whether the inspector island is shown.
    property bool inspectorOpen: true
    /// The inspector's tab: overview, details, network, threads, files.
    property int inspectorTab: 0
    /// Whether the inspector shows a page that reads the selection's detail:
    /// details, threads or files. The core fetches detail only then.
    readonly property bool inspectorShowsDetail:
        inspectorOpen && (inspectorTab === 1 || inspectorTab === 3 || inspectorTab === 4)

    /// Cmd/Ctrl+F: the tree island opens its search overlay.
    signal treeSearchRequested()
    /// Cmd/Ctrl+T: the tab strip opens its "+" menu.
    signal tabMenuRequested()

    function requestTreeSearch() { treeSearchRequested() }
    function requestTabMenu() { tabMenuRequested() }

    readonly property var settings: app ? app.settings : ({})
    readonly property var session: app ? app.session : ({})
    readonly property var platform: app ? app.platform : ({})
    readonly property string os: platform && platform.os ? platform.os : Qt.platform.os
    readonly property bool isMac: os === "macos"
    readonly property bool isLinux: os === "linux"
    readonly property bool isWindows: os === "windows"
    readonly property bool live: !(session && session.loadedSnapshotPath)
    readonly property bool remote: !!(session && session.isRemote)

    /// The modifier name Qt shortcuts use for "command" on this platform.
    readonly property string commandKey: "Ctrl"
}
