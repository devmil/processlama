pragma Singleton
import QtQuick
import Meridian

// ProcessLama's app-only tokens on top of Meridian: the CPU heat tint of
// process rows, the tree search highlights and the chart series.
QtObject {
    readonly property color rowHeat: Theme.colors.accent
    readonly property color searchMatchRow: Theme.colors.warningBg
    readonly property color searchHighlight: Qt.alpha(Theme.colors.warning, searchHighlightOpacity)
    readonly property color chartLine: Theme.colors.series1
    readonly property color chartUpper: Theme.colors.series1
    readonly property color chartLower: Theme.colors.series2

    readonly property real aboutTileSize: 96
    readonly property real licenseTileSize: 40
    readonly property real emptyLamaHeight: 48
    readonly property real maxRowHeatOpacity: 0.12
    readonly property real searchHighlightOpacity: 0.28
    readonly property real chartHistoryOpacity: 0.55
    /// Opacity of terminated rows (MeridianOpacity.dimmedRow).
    readonly property real dimmedRow: 0.45

    readonly property real sidebarWidth: 216
    readonly property real toolbarLabelBreakpoint: 1120
    readonly property real searchMaxWidth: 440
    readonly property real macTrafficLightsEnd: 79

    /// The status tone of a connection phase.
    function phaseTone(phase) {
        switch (phase) {
        case "live": return MeridianStatusDot.Success
        case "probing":
        case "installing":
        case "handshaking":
        case "reconnecting": return MeridianStatusDot.Warning
        case "failed": return MeridianStatusDot.Danger
        default: return MeridianStatusDot.Neutral
        }
    }
}
