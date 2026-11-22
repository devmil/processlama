pragma ComponentBehavior: Bound
import QtQuick
import Meridian

// The preferences: appearance, process tree, columns, remote hosts, updates
// and diagnostics. Every change applies straight away.
MeridianSettingsDialog {
    id: dialog

    readonly property var app: Store.app
    readonly property var settings: Store.settings
    readonly property var visibleColumns: settings.visibleColumns ?? ["name"]

    title: L10n.t("preferences")
    closeLabel: L10n.t("close")
    pages: [
        { label: L10n.t("appearance"), icon: "palette", description: L10n.t("preferencesPageAppearanceDetail") },
        { label: L10n.t("preferencesPageProcessTree"), icon: "list-tree", description: L10n.t("preferencesPageProcessTreeDetail") },
        { label: L10n.t("columns"), icon: "columns-2", description: L10n.t("preferencesPageColumnsDetail") },
        { label: L10n.t("preferencesPageRemoteHosts"), icon: "server", description: L10n.t("preferencesPageRemoteHostsDetail") },
        { label: L10n.t("preferencesPageUpdates"), icon: "download", description: L10n.t("preferencesPageUpdatesDetail") },
        { label: L10n.t("diagnosticsTitle"), icon: "activity", description: L10n.t("diagnosticsDescription") }
    ]

    function setColumn(id, show) {
        const next = visibleColumns.slice()
        const index = next.indexOf(id)
        if (show && index < 0)
            next.push(id)
        else if (!show && index >= 0)
            next.splice(index, 1)
        app.setVisibleColumns(next)
    }

    function moveColumn(id, delta) {
        const next = visibleColumns.slice()
        const index = next.indexOf(id)
        if (index < 0)
            return
        next.splice(index, 1)
        next.splice(index + delta, 0, id)
        app.setVisibleColumns(next)
    }

    // Appearance
    MeridianSettingsGroup {
        MeridianSettingsRow {
            width: parent.width
            label: L10n.t("preferencesTheme")
            MeridianSegmented {
                label: L10n.t("preferencesTheme")
                value: dialog.settings.appearanceMode
                segments: [
                    { value: "system", label: L10n.t("system") },
                    { value: "light", label: L10n.t("light") },
                    { value: "dark", label: L10n.t("dark") }
                ]
                onActivated: value => dialog.app.setAppearance(value)
            }
        }
        MeridianSettingsRow {
            width: parent.width
            label: L10n.t("rowDensity")
            MeridianSegmented {
                label: L10n.t("rowDensity")
                value: dialog.settings.rowDensity
                segments: [
                    { value: "compact", label: L10n.t("rowDensityCompact") },
                    { value: "regular", label: L10n.t("rowDensityRegular") },
                    { value: "comfortable", label: L10n.t("rowDensityComfortable") }
                ]
                onActivated: value => dialog.app.setRowDensity(value)
            }
        }
    }

    // Process tree
    MeridianSettingsGroup {
        MeridianSettingsRow {
            width: parent.width
            label: L10n.t("pollingInterval")
            MeridianSlider {
                label: L10n.t("pollingInterval")
                from: 250
                to: 10000
                stepSize: 250
                snapMode: MeridianSlider.SnapAlways
                value: Math.max(250, Math.min(10000, dialog.settings.pollingIntervalMs ?? 1000))
                valueLabel: v => Math.round(v) + " ms"
                onMoved: dialog.app.setPollingInterval(Math.round(value))
            }
        }
        MeridianSettingsRow {
            width: parent.width
            label: L10n.t("tree")
            MeridianSwitch {
                text: L10n.t("rememberTreeExpansion")
                checked: dialog.settings.rememberTreeExpansion ?? false
                onToggled: dialog.app.setRememberTreeExpansion(checked)
            }
            MeridianSwitch {
                text: L10n.t("rowHeatmap")
                checked: dialog.settings.rowHeatmap ?? false
                onToggled: dialog.app.setRowHeatmap(checked)
            }
        }
    }

    // Columns: visible ones first in their order, hidden ones after them.
    Column {
        readonly property var ordered: dialog.visibleColumns.concat(
            Labels.availableColumns.filter(id => dialog.visibleColumns.indexOf(id) < 0))
        Repeater {
            model: parent.ordered
            Item {
                id: columnRow
                required property string modelData
                readonly property int position: dialog.visibleColumns.indexOf(modelData)
                width: parent.width
                height: Math.max(Theme.size.control, check.implicitHeight)
                MeridianCheckbox {
                    id: check
                    anchors.verticalCenter: parent.verticalCenter
                    text: Labels.column(columnRow.modelData)
                    checked: columnRow.position >= 0
                    enabled: columnRow.modelData !== "name"
                    onToggled: dialog.setColumn(columnRow.modelData, checked)
                }
                Row {
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    MeridianIconButton {
                        text: L10n.t("moveColumnEarlier")
                        iconName: "arrow-up"
                        controlSize: MeridianButton.Small
                        enabled: columnRow.position > 0
                        onClicked: dialog.moveColumn(columnRow.modelData, -1)
                    }
                    MeridianIconButton {
                        text: L10n.t("moveColumnLater")
                        iconName: "arrow-down"
                        controlSize: MeridianButton.Small
                        enabled: columnRow.position >= 0 && columnRow.position < dialog.visibleColumns.length - 1
                        onClicked: dialog.moveColumn(columnRow.modelData, 1)
                    }
                }
            }
        }
    }

    // Remote hosts
    RemoteHostsSettings {}

    // Updates
    MeridianSettingsGroup {
        MeridianSettingsRow {
            width: parent.width
            label: L10n.t("releaseChannel")
            MeridianSegmented {
                label: L10n.t("releaseChannel")
                value: dialog.settings.releaseChannel
                segments: [
                    { value: "stable", label: L10n.t("releaseChannelStable") },
                    { value: "beta", label: L10n.t("releaseChannelBeta") }
                ]
                onActivated: value => dialog.app.setReleaseChannel(value)
            }
        }
    }

    // Diagnostics
    DiagnosticsSettings {}
}
