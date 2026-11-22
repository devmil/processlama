import QtQuick
import Meridian

// The window's status strip: whether the tree is live, and the totals. A
// remote tab adds its host, how long it has been connected or when it last
// updated, and its refresh.
MeridianStatusBar {
    id: bar

    readonly property var session: Store.session
    readonly property var remote: session.remote ?? null
    readonly property int interval: Store.settings.pollingIntervalMs ?? 1000
    readonly property bool remoteLive: remote !== null && remote.phase === "live" && remote.sourcePhase === "live"
    readonly property string queued: session.hasQueued ? L10n.t("queuedCount", [session.queuedCount]) : ""
    readonly property string hostLine: {
        if (!remote)
            return ""
        if (remoteLive && remote.connectedSince)
            return L10n.t("remoteStatusConnected", [remote.host, Format.duration(Date.now() - remote.connectedSince)])
        if (remote.lastSampleAt)
            return L10n.t("remoteStatusLastUpdated", [remote.host, Format.clock(remote.lastSampleAt)])
        return remote.host
    }

    // Static on purpose: a pulsing dot would keep the scene drawing every
    // frame between refreshes.
    MeridianStatusDot {
        anchors.verticalCenter: parent ? parent.verticalCenter : undefined
        tone: bar.session.frozen ? MeridianStatusDot.Neutral
            : bar.remote && !bar.remoteLive ? AppTheme.phaseTone(bar.remote.phase)
            : MeridianStatusDot.Success
        halo: !bar.session.frozen && (!bar.remote || bar.remoteLive)
        label: bar.session.frozen ? L10n.t("statusTreeLocked")
             : bar.remote ? (bar.remoteLive ? L10n.t("remoteStatusRefreshLive", [(bar.interval / 1000).toFixed(1) + " s"])
                                            : Labels.phase(bar.remote.phase))
             : L10n.t("pollingStatus", [bar.interval])
    }
    MeridianStatusBarText {
        anchors.verticalCenter: parent ? parent.verticalCenter : undefined
        visible: bar.remote !== null
        animated: false
        text: bar.hostLine
    }
    MeridianStatusBarText {
        id: orderHint
        anchors.verticalCenter: parent ? parent.verticalCenter : undefined
        visible: bar.session.orderLocked ?? false
        iconName: "pause"
        text: L10n.t("liveOrderingPaused")
        HoverHandler { id: orderHover }
        MeridianTooltip {
            text: L10n.t("liveOrderingPausedTooltip")
            shown: orderHover.hovered
        }
    }

    trailing: [
        MeridianStatusBarText {
            anchors.verticalCenter: parent ? parent.verticalCenter : undefined
            // Changes on most polls; a swap would redraw the window for its
            // whole duration every time.
            animated: false
            text: L10n.t("processCount", [bar.session.processCount ?? 0]) + bar.queued
        }
    ]
}
