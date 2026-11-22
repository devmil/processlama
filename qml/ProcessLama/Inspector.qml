pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Templates as T
import Meridian

// The inspector island: the selected process, its tabs and their content.
MeridianIsland {
    id: inspector

    readonly property var app: Store.app
    readonly property var session: Store.session
    readonly property var view: app.inspector ?? ({ hasProcess: false })
    readonly property bool hasProcess: view.hasProcess === true
    readonly property var row: view.tree ?? null
    readonly property var detail: view.detail ?? null
    readonly property var histories: view.histories ?? null
    readonly property bool networkUnavailable: session.networkUnavailable ?? false
    readonly property int tab: Store.inspectorTab
    property bool treeScope: true

    // The network banner: install the local service, or copy a remote host's
    // install command and read the guide.
    readonly property var networkHint: {
        const remote = session.remote
        if (remote) {
            return {
                title: L10n.t("networkTelemetryUnavailable"),
                message: remote.installable ? L10n.t("remoteCapabilityNetworkMissing") : L10n.t("remoteCapabilityNetworkUnsupported"),
                action: remote.installable ? L10n.t("remoteCapabilityCopyInstallCommand") : "",
                run: () => inspector.app.copyNetworkInstallCommand(remote.profileId),
                guide: true
            }
        }
        return {
            title: L10n.t("networkTelemetryUnavailable"),
            message: L10n.t("networkTelemetryUnavailableDescription"),
            action: L10n.t("installNetworkTelemetry"),
            run: () => Store.actions.installNetworkTelemetry(),
            guide: false
        }
    }

    function portList(values) {
        if (values === undefined || values === null)
            return L10n.t("portsNotReported")
        return values.length === 0 ? "—" : values.join(", ")
    }
    function endpoint(address, port, approximate) {
        const prefix = approximate ? "~" : ""
        return port <= 0 ? prefix + address : prefix + address + ":" + port
    }
    function dash(value) { return (value ?? "").trim().length === 0 ? "-" : value }
    function yesNo(value) { return value ? L10n.t("yes") : L10n.t("no") }
    function orUnknown(value) { return (value ?? "").length === 0 ? L10n.t("unknown") : value }
    function sampleMax(samples, current) {
        let max = 0
        for (const sample of samples ?? [])
            if (isFinite(sample) && sample > max)
                max = sample
        return Math.max(0.1, max, current)
    }

    // The header: icon, name, pid and platform.
    Item {
        id: header
        width: parent.width
        height: headerRow.height + Theme.space.s6 + Theme.space.s4
        ProcessIcon {
            id: headerIcon
            x: Theme.space.s6
            anchors.verticalCenter: headerRow.verticalCenter
            avatarSize: MeridianAvatar.Large
            name: inspector.hasProcess ? inspector.view.name : L10n.t("inspector")
            iconUrl: inspector.hasProcess ? inspector.view.iconUrl : ""
        }
        Column {
            id: headerRow
            anchors.left: headerIcon.right
            anchors.leftMargin: Theme.space.s5
            anchors.right: parent.right
            anchors.rightMargin: Theme.space.s6
            y: Theme.space.s6
            MeridianText {
                width: parent.width
                role: MeridianText.Heading
                elide: Text.ElideRight
                text: inspector.hasProcess ? inspector.view.name : L10n.t("inspector")
            }
            MeridianText {
                width: parent.width
                role: MeridianText.CodeSm
                tabular: true
                color: Theme.colors.inkMuted
                elide: Text.ElideRight
                text: inspector.hasProcess ? L10n.t("pidPlatform", [inspector.view.pid, inspector.session.platform ?? ""])
                                           : L10n.t("noProcessSelected")
            }
        }
    }

    MeridianTabs {
        id: tabs
        anchors.top: header.bottom
        x: Theme.space.s5
        width: parent.width - 2 * Theme.space.s5
        currentIndex: inspector.tab
        tabs: [
            { label: L10n.t("tabOverview") },
            { label: L10n.t("tabDetails") },
            { label: L10n.t("tabNetwork") },
            { label: L10n.t("tabThreads") },
            { label: L10n.t("tabFilesAndSockets") }
        ]
        onActivated: index => Store.inspectorTab = index
    }

    MeridianHairline {
        id: tabRule
        anchors.top: tabs.bottom
        width: parent.width
    }

    MeridianBanner {
        id: snapshotBanner
        visible: (inspector.session.snapshotError ?? null) !== null
        anchors.top: tabRule.bottom
        anchors.topMargin: visible ? Theme.space.s5 : 0
        x: Theme.space.s5
        width: parent.width - 2 * Theme.space.s5
        height: visible ? implicitHeight : 0
        tone: MeridianBanner.Warning
        message: visible ? L10n.t("bootstrapModeMessage", [inspector.session.snapshotError]) : ""
    }

    MeridianEmptyState {
        visible: !inspector.hasProcess
        anchors.top: snapshotBanner.bottom
        anchors.bottom: parent.bottom
        width: parent.width
        iconName: "activity"
        title: L10n.t("noProcessSelected")
        message: inspector.tab === 2 ? L10n.t("selectProcessToInspectNetwork") : L10n.t("selectProcessToInspect")
    }

    Flickable {
        id: page
        MeridianWheelScroll { flickable: page }
        visible: inspector.hasProcess
        anchors.top: snapshotBanner.bottom
        anchors.bottom: parent.bottom
        width: parent.width
        contentHeight: pages.height + 2 * Theme.space.s6
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        T.ScrollBar.vertical: MeridianScrollBar {}

        Loader {
            id: pages
            x: Theme.space.s6
            y: Theme.space.s6
            width: page.width - 2 * Theme.space.s6
            active: inspector.hasProcess
            sourceComponent: [overviewPage, detailsPage, networkPage, threadsPage, filesPage][inspector.tab]
            onSourceComponentChanged: page.contentY = 0
        }
    }

    component Section: MeridianText {
        topPadding: Theme.space.s7
        bottomPadding: Theme.space.s4
        role: MeridianText.Overline
        color: Theme.colors.inkMuted
    }

    // Why a section has nothing to show, or its rows.
    component StateBanner: MeridianBanner {
        property string state: "available"
        width: parent ? parent.width : 0
        tone: state === "restricted" ? MeridianBanner.Attention : MeridianBanner.Info
        iconName: state === "restricted" ? "shield-alert" : state === "unsupported" ? "ban" : "info"
    }

    component DetailSection: Column {
        id: section
        property var value: null
        property string emptyMessage
        property var rows: []
        default property alias footer: footerSlot.data
        width: parent ? parent.width : 0
        spacing: Theme.space.s5
        readonly property string state: value ? value.state : "pending"
        StateBanner {
            visible: section.state !== "available" || section.rows.length === 0
            state: section.state
            message: section.state === "pending" ? L10n.t("inspectorDetailsPending")
                   : section.state === "restricted" ? L10n.t("restrictedByMacos", [section.value.reason])
                   : section.state === "available" ? section.emptyMessage
                   : section.value.reason
        }
        PropertyRows {
            visible: section.state === "available" && section.rows.length > 0
            width: parent.width
            properties: section.rows
        }
        Column {
            id: footerSlot
            visible: section.state === "available" && section.rows.length > 0 && children.length > 0
            width: parent.width
            spacing: Theme.space.s5
        }
    }

    component PortChips: Column {
        id: chips
        property var ports: null
        width: parent ? parent.width : 0
        MeridianText {
            visible: !chips.ports || chips.ports.count === 0
            role: MeridianText.Caption
            color: Theme.colors.inkMuted
            text: !chips.ports ? L10n.t("portsNotReported") : L10n.t("noOccupiedPorts")
        }
        // Fixed groups and counted chips: telemetry arrives as new arrays
        // every poll, and an array model would recreate every chip.
        PortGroup {
            label: L10n.t("listeningPorts")
            values: chips.ports ? chips.ports.listening : []
            tone: MeridianChip.Accent
        }
        PortGroup {
            label: L10n.t("otherLocalPorts")
            values: chips.ports ? chips.ports.other : []
            tone: MeridianChip.Neutral
        }
    }

    component PortGroup: Column {
        id: group
        property string label
        property var values: []
        property int tone
        visible: values.length > 0
        width: parent ? parent.width : 0
        bottomPadding: Theme.space.s4
        spacing: Theme.space.s2
        MeridianText { text: group.label; role: MeridianText.Caption; color: Theme.colors.inkMuted }
        Flow {
            width: parent.width
            spacing: Theme.space.s2
            Repeater {
                model: group.values.length
                MeridianChip {
                    required property int index
                    readonly property int port: group.values[index] ?? 0
                    text: String(port)
                    tone: group.tone
                    interactive: true
                    Accessible.name: L10n.t("showPortProcesses", [port])
                    onClicked: inspector.app.showPort(port)
                }
            }
        }
    }

    // A headline metric: an overline name over the value on a pane-alt inset.
    component MetricTile: Rectangle {
        id: tile
        property string label
        property string value
        property bool warning: false
        property bool actionable: false
        signal activated()
        height: tileColumn.height + 2 * Theme.space.s4
        radius: Theme.radius.md
        color: Theme.colors.paneAlt
        Accessible.role: actionable ? Accessible.Button : Accessible.StaticText
        Accessible.name: actionable ? L10n.t("networkTelemetryUnavailable") + ". " + L10n.t("installNetworkTelemetry")
                                    : label + ": " + value
        Column {
            id: tileColumn
            x: Theme.space.s5
            y: Theme.space.s4
            width: parent.width - 2 * Theme.space.s5
            spacing: Theme.space.s2
            Item {
                width: parent.width
                height: tileLabel.height
                MeridianText {
                    id: tileLabel
                    anchors.left: parent.left
                    anchors.right: arrow.visible ? arrow.left : parent.right
                    role: MeridianText.Overline
                    color: Theme.colors.inkMuted
                                elide: Text.ElideRight
                    text: tile.label
                }
                MeridianIcon {
                    id: arrow
                    visible: tile.actionable
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    name: "arrow-right"
                    iconSize: MeridianIcon.Small
                    color: Theme.colors.accentInk
                }
            }
            MeridianText {
                width: parent.width
                role: MeridianText.Code
                tabular: true
                fontPixelSize: Theme.type.heading.pixelSize
                fontWeight: Font.DemiBold
                lineHeight: Theme.type.headingLineHeight
                lineHeightMode: Text.FixedHeight
                elide: Text.ElideRight
                color: tile.warning ? Theme.colors.warning : Theme.colors.ink
                text: tile.value
            }
        }
        TapHandler {
            enabled: tile.actionable
            onTapped: tile.activated()
        }
        HoverHandler { enabled: tile.actionable; cursorShape: Qt.PointingHandCursor }
    }

    component NetworkBanner: MeridianBanner {
        width: parent ? parent.width : 0
        tone: MeridianBanner.Attention
        iconName: "shield-alert"
        title: inspector.networkHint.title
        message: inspector.networkHint.message
        MeridianButton {
            visible: inspector.networkHint.action.length > 0
            text: inspector.networkHint.action
            controlSize: MeridianButton.Small
            onClicked: inspector.networkHint.run()
        }
        MeridianButton {
            visible: inspector.networkHint.guide
            text: L10n.t("remoteHostSetupGuide")
            controlSize: MeridianButton.Small
            variant: MeridianButton.Quiet
            onClicked: Store.actions.openSetupGuide()
        }
    }

    Component {
        id: overviewPage
        Column {
            id: overviewContent
            readonly property var view: inspector.view
            readonly property var row: inspector.row
            readonly property bool useTree: inspector.treeScope && row !== null
            readonly property var h: inspector.histories ?? ({})
            readonly property var ports: useTree ? view.treePorts : view.ports
            readonly property real cpu: useTree ? row.cpu : view.cpu
            readonly property real gpu: useTree ? row.gpu : view.gpu
            readonly property real rss: useTree ? row.rss : view.rss
            readonly property real netIn: useTree ? row.netIn : view.netIn
            readonly property real netOut: useTree ? row.netOut : view.netOut
            readonly property real storageRead: useTree ? row.storageRead : view.storageRead
            readonly property real storageWrite: useTree ? row.storageWrite : view.storageWrite
            readonly property bool storageAvailable: useTree ? row.storageAvailable : view.storageAvailable
            readonly property var cpuHistory: (useTree ? h.treeCpu : h.cpu) ?? []
            readonly property var gpuHistory: (useTree ? h.treeGpu : h.gpu) ?? []
            readonly property var rssHistory: (useTree ? h.treeRss : h.rss) ?? []
            readonly property var netInHistory: (useTree ? h.treeNetIn : h.netIn) ?? []
            readonly property var netOutHistory: (useTree ? h.treeNetOut : h.netOut) ?? []
            readonly property var readHistory: (useTree ? h.treeStorageRead : h.storageRead) ?? []
            readonly property var writeHistory: (useTree ? h.treeStorageWrite : h.storageWrite) ?? []
            readonly property var tiles: {
                const result = [
                    { label: L10n.t("columnCpu"), value: Format.percent(cpu), warning: cpu >= 50 },
                    { label: L10n.t("overviewMemory"), value: Format.bytes(rss) },
                    { label: L10n.t("columnGpu"), value: Format.percent(gpu) },
                    { label: L10n.t("tabNetwork"), value: inspector.networkUnavailable ? L10n.t("metricUnavailable") : Format.rate(netIn + netOut),
                      actionable: inspector.networkUnavailable },
                    { label: L10n.t("overviewStorage"), value: storageAvailable ? Format.rate(storageRead + storageWrite) : L10n.t("metricUnavailable") }
                ]
                if (useTree)
                    result.push({ label: L10n.t("descendants"), value: String(row.descendants) })
                return result
            }

            spacing: 0

            MeridianSegmented {
                visible: overviewContent.row !== null
                label: L10n.t("tree")
                controlSize: MeridianButton.Small
                value: inspector.treeScope ? "tree" : "process"
                segments: [{ value: "tree", label: L10n.t("tree") }, { value: "process", label: L10n.t("processScope") }]
                onActivated: value => inspector.treeScope = value === "tree"
            }
            Item { visible: overviewContent.row !== null; width: 1; height: Theme.space.s5 }

            Flow {
                width: parent.width
                spacing: Theme.space.s3
                Repeater {
                    model: overviewContent.tiles.length
                    MetricTile {
                        required property int index
                        readonly property var entry: overviewContent.tiles[index] ?? ({})
                        width: (overviewContent.width - Theme.space.s3) / 2
                        label: entry.label ?? ""
                        value: entry.value ?? ""
                        warning: entry.warning ?? false
                        actionable: entry.actionable ?? false
                        onActivated: Store.actions.installNetworkTelemetry()
                    }
                }
            }

            Item { width: 1; height: Theme.space.s5 }

            MeridianDisclosure {
                id: portsDisclosure
                width: parent.width
                title: L10n.t("occupiedPorts")
                readonly property string key: inspector.view.key ?? ""
                onKeyChanged: expanded = false
                trailing: [
                    MeridianCount {
                        label: overviewContent.ports ? String(overviewContent.ports.count) : "—"
                        semanticLabel: overviewContent.ports ? L10n.t("occupiedPorts") + ": " + overviewContent.ports.count : L10n.t("portsNotReported")
                    }
                ]
                Item { width: 1; height: Theme.space.s3 }
                PortChips { ports: overviewContent.ports }
            }

            Column {
                visible: overviewContent.row !== null
                width: parent.width
                topPadding: Theme.space.s5
                spacing: Theme.space.s3
                HistoryChart {
                    label: L10n.t("columnCpu")
                    value: Format.percent(overviewContent.cpu)
                    samples: overviewContent.cpuHistory
                    scaleMax: inspector.sampleMax(overviewContent.cpuHistory, overviewContent.cpu)
                    formatValue: v => Format.percent(v)
                }
                HistoryChart {
                    label: L10n.t("columnRss")
                    value: Format.bytes(overviewContent.rss)
                    samples: overviewContent.rssHistory
                    scaleMax: inspector.sampleMax(overviewContent.rssHistory, overviewContent.rss)
                    formatValue: v => Format.bytes(Math.round(v))
                }
                HistoryChart {
                    label: L10n.t("columnGpu")
                    value: Format.percent(overviewContent.gpu)
                    samples: overviewContent.gpuHistory
                    scaleMax: inspector.sampleMax(overviewContent.gpuHistory, overviewContent.gpu)
                    formatValue: v => Format.percent(v)
                }
                HistoryChart {
                    visible: !inspector.networkUnavailable
                    diverging: true
                    label: L10n.t("networkHistory")
                    detail: L10n.t("networkOutIn")
                    value: Format.rate(overviewContent.netOut) + " / " + Format.rate(overviewContent.netIn)
                    samples: overviewContent.netOutHistory
                    lowerSamples: overviewContent.netInHistory
                    scaleMax: inspector.sampleMax(overviewContent.netOutHistory.concat(overviewContent.netInHistory),
                                                  Math.max(overviewContent.netOut, overviewContent.netIn))
                }
                HistoryChart {
                    visible: overviewContent.storageAvailable
                    diverging: true
                    label: L10n.t("storageHistory")
                    detail: L10n.t("storageReadWrite")
                    value: Format.rate(overviewContent.storageRead) + " / " + Format.rate(overviewContent.storageWrite)
                    samples: overviewContent.readHistory
                    lowerSamples: overviewContent.writeHistory
                    scaleMax: inspector.sampleMax(overviewContent.readHistory.concat(overviewContent.writeHistory),
                                                  Math.max(overviewContent.storageRead, overviewContent.storageWrite))
                }
            }
        }
    }

    Component {
        id: detailsPage
        Column {
            readonly property var p: inspector.view
            readonly property var files: inspector.detail ? inspector.detail.files : null
            readonly property int openFiles: files && files.state === "available" ? files.value.length : p.openFiles
            readonly property bool storage: p.storageAvailable
            readonly property string unavailable: L10n.t("metricUnavailable")
            readonly property bool net: !inspector.networkUnavailable
            PropertyRows {
                width: parent.width
                properties: [
                    { label: L10n.t("parentPid"), value: String(parent.p.ppid), monospace: true },
                    { label: L10n.t("userId"), value: (parent.p.user ?? "").length === 0 ? String(parent.p.uid) : parent.p.user + " (" + parent.p.uid + ")" },
                    { label: L10n.t("status"), value: parent.p.status },
                    { label: L10n.t("listeningPortsLabel"), value: inspector.portList(parent.p.ports ? parent.p.ports.listening : null), monospace: true },
                    { label: L10n.t("otherLocalPorts"), value: inspector.portList(parent.p.ports ? parent.p.ports.other : null), monospace: true },
                    { label: L10n.t("threads"), value: String(parent.p.threads), monospace: true },
                    { label: L10n.t("openFiles"), value: String(parent.openFiles), monospace: true },
                    { label: L10n.t("virtualMemory"), value: Format.bytes(parent.p.virtualMemory), monospace: true },
                    { label: L10n.t("nice"), value: String(parent.p.nice), monospace: true },
                    { label: L10n.t("priority"), value: String(parent.p.priority), monospace: true },
                    { label: L10n.t("gpu"), value: Format.percent(parent.p.gpu), monospace: true },
                    { label: L10n.t("netIn"), value: parent.net ? Format.rate(parent.p.netIn) : parent.unavailable, monospace: true },
                    { label: L10n.t("netOut"), value: parent.net ? Format.rate(parent.p.netOut) : parent.unavailable, monospace: true },
                    { label: L10n.t("storageRead"), value: parent.storage ? Format.rate(parent.p.storageRead) : parent.unavailable, monospace: true },
                    { label: L10n.t("storageWrite"), value: parent.storage ? Format.rate(parent.p.storageWrite) : parent.unavailable, monospace: true },
                    { label: L10n.t("totalStorageRead"), value: parent.storage ? Format.bytes(parent.p.totalStorageRead) : parent.unavailable, monospace: true },
                    { label: L10n.t("totalStorageWrite"), value: parent.storage ? Format.bytes(parent.p.totalStorageWrite) : parent.unavailable, monospace: true },
                    { label: L10n.t("identity"), value: parent.p.pid + "@" + parent.p.startTime, monospace: true },
                    { label: L10n.t("executable"), value: inspector.orUnknown(parent.p.executable), monospace: true },
                    { label: L10n.t("applicationBundle"), value: inspector.orUnknown(parent.p.bundle), monospace: true },
                    { label: L10n.t("commandLine"), value: inspector.orUnknown(parent.p.commandLine), monospace: true }
                ]
            }
            Section { text: L10n.t("tabSecurity") }
            DetailSection {
                readonly property var security: inspector.detail ? inspector.detail.security : null
                value: security
                emptyMessage: L10n.t("noSecurityMetadataReported")
                rows: {
                    if (!security || security.state !== "available")
                        return []
                    const s = security.value
                    const result = [
                        { label: L10n.t("signing"), value: s.signingStatus },
                        { label: L10n.t("authority"), value: inspector.dash(s.signingAuthority) },
                        { label: L10n.t("teamId"), value: inspector.dash(s.teamId), monospace: true },
                        { label: L10n.t("bundleId"), value: inspector.dash(s.bundleId), monospace: true },
                        { label: L10n.t("entitlements"), value: inspector.dash(s.entitlementsSummary) },
                        { label: L10n.t("origin"), value: inspector.dash(s.gatekeeperOrigin) },
                        { label: L10n.t("sandbox"), value: inspector.yesNo(s.sandbox) },
                        { label: L10n.t("hardenedRuntime"), value: inspector.yesNo(s.hardenedRuntime) },
                        { label: L10n.t("architecture"), value: s.architecture }
                    ]
                    if (s.rosettaTranslated)
                        result.push({ label: L10n.t("rosetta"), value: L10n.t("yes") })
                    return result
                }
            }
        }
    }

    Component {
        id: networkPage
        Column {
            readonly property var p: inspector.view
            readonly property var h: inspector.histories ?? ({})
            readonly property bool unavailable: inspector.networkUnavailable
            readonly property string na: L10n.t("metricUnavailable")
            NetworkBanner { visible: parent.unavailable }
            Item { visible: parent.unavailable; width: 1; height: Theme.space.s5 }
            PropertyRows {
                width: parent.width
                properties: [
                    { label: L10n.t("networkIn"), value: parent.unavailable ? parent.na : Format.rate(parent.p.netIn), monospace: true },
                    { label: L10n.t("networkOut"), value: parent.unavailable ? parent.na : Format.rate(parent.p.netOut), monospace: true },
                    { label: L10n.t("totalIn"), value: parent.unavailable ? parent.na : Format.bytes(parent.p.totalNetIn), monospace: true },
                    { label: L10n.t("totalOut"), value: parent.unavailable ? parent.na : Format.bytes(parent.p.totalNetOut), monospace: true }
                ]
            }
            Item { visible: chart.visible; width: 1; height: Theme.space.s7 }
            HistoryChart {
                id: chart
                readonly property var row: inspector.row
                readonly property var outHistory: parent.h.treeNetOut ?? []
                readonly property var inHistory: parent.h.treeNetIn ?? []
                visible: row !== null && !parent.unavailable
                diverging: true
                label: L10n.t("networkHistory")
                detail: L10n.t("networkOutIn")
                value: row ? Format.rate(row.netOut) + " / " + Format.rate(row.netIn) : ""
                samples: outHistory
                lowerSamples: inHistory
                scaleMax: row ? inspector.sampleMax(outHistory.concat(inHistory), Math.max(row.netOut, row.netIn)) : 0.1
            }
        }
    }

    Component {
        id: threadsPage
        Column {
            DetailSection {
                readonly property var threads: inspector.detail ? inspector.detail.threads : null
                value: threads
                emptyMessage: L10n.t("noThreadsReported")
                rows: {
                    if (!threads || threads.state !== "available")
                        return []
                    const result = []
                    const summary = threads.value.summary
                    if (summary)
                        result.push({ label: L10n.t("summary"),
                                      value: "~" + summary.threadCount + " threads · ~" + summary.machSyscallCount + " mach syscalls" })
                    for (const thread of threads.value.threads)
                        result.push({ label: "tid " + thread.id,
                                      value: (thread.approximate ? "~" : "") + Format.percent(thread.cpu) + " · " + thread.state,
                                      monospace: true })
                    return result
                }
            }
        }
    }

    Component {
        id: filesPage
        Column {
            id: filesContent
            readonly property var owners: inspector.view.listenerOwners ?? []
            DetailSection {
                id: fileSection
                readonly property var files: inspector.detail ? inspector.detail.files : null
                value: files
                emptyMessage: L10n.t("noOpenFilesReported")
                rows: files && files.state === "available"
                    ? files.value.map(file => ({ label: file.fd + " · " + file.kind,
                                                 value: file.path.length === 0 ? L10n.t("noPathAvailable") : file.path,
                                                 monospace: true }))
                    : []
                StateBanner {
                    visible: fileSection.rows.length >= 500
                    message: L10n.t("openFilesTruncated")
                }
            }
            Section { text: L10n.t("occupiedPorts") }
            PortChips { ports: inspector.view.ports }
            MeridianText {
                width: parent.width
                wrapMode: Text.Wrap
                role: MeridianText.Caption
                text: L10n.t("localPortsExplanation")
            }
            Section { text: L10n.t("tabSockets") }
            DetailSection {
                id: sockets
                readonly property var endpoints: inspector.detail ? inspector.detail.sockets : null
                value: endpoints
                emptyMessage: L10n.t("noSocketsReported")
                rows: endpoints && endpoints.state === "available"
                    ? endpoints.value.map(e => ({
                        label: e.protocol,
                        value: inspector.endpoint(e.localAddress, e.localPort, e.localApproximate) + " -> "
                               + inspector.endpoint(e.remoteAddress, e.remotePort, e.remoteApproximate) + " · " + e.state,
                        monospace: true }))
                    : []
                // Links from loopback sockets to the local listeners.
                Column {
                    visible: filesContent.owners.length > 0
                    width: parent.width
                    spacing: Theme.space.s2
                    MeridianText { text: L10n.t("socketPeers"); role: MeridianText.Caption; color: Theme.colors.inkMuted }
                    Flow {
                        width: parent.width
                        spacing: Theme.space.s2
                        Repeater {
                            id: peers
                            readonly property var sorted: filesContent.owners.slice().sort((a, b) => a.port - b.port)
                            model: sorted.length
                            MeridianButton {
                                required property int index
                                readonly property var modelData: peers.sorted[index]
                                text: ":" + modelData.port + " · " + L10n.t("goToPortOwner", [modelData.name, modelData.pid])
                                variant: MeridianButton.Quiet
                                controlSize: MeridianButton.Small
                                iconName: "arrow-right"
                                Accessible.name: L10n.t("goToPortOwnerLabel", [modelData.name, modelData.pid, modelData.port])
                                onClicked: inspector.app.selectProcess(modelData.key)
                            }
                        }
                    }
                }
            }
        }
    }
}
