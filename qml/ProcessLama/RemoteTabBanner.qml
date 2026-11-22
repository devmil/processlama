import QtQuick
import Meridian

// The state line of a remote tab: connecting, reconnecting or stale with the
// time of the last sample and the reason, or failed; and the hidepid notice
// while live. Nothing for the local tab or a loaded snapshot.
Item {
    id: root

    readonly property var session: Store.session
    readonly property var remote: session.remote ?? null
    readonly property string phase: remote ? remote.phase : ""
    readonly property string host: remote ? remote.host : ""
    readonly property string reason: remote && remote.failure ? Labels.failure(remote.failure) : ""
    readonly property var lastSample: remote ? remote.lastSampleAt : null
    readonly property bool hasSample: lastSample !== null && lastSample !== undefined
    readonly property bool failing: phase === "reconnecting" || phase === "disconnected" || phase === "failed"

    // kind: "" (none), "hidepid", "connecting", "installing", "lost", "stale"
    readonly property string kind: {
        if (!remote || !Store.live)
            return ""
        switch (phase) {
        case "live":
            if (session.hidepid && remote.sourcePhase === "live")
                return "hidepid"
            return hasSample ? "" : "connecting"
        case "installing":
            return "installing"
        case "idle":
        case "probing":
        case "handshaking":
            return "connecting"
        default:
            return hasSample ? "stale" : "lost"
        }
    }

    height: kind.length > 0 ? banner.height + Theme.space.s3 : 0
    visible: kind.length > 0

    MeridianBanner {
        id: banner
        x: Theme.space.s3
        width: parent.width - 2 * Theme.space.s3
        tone: {
            switch (root.kind) {
            case "lost": return root.phase === "reconnecting" ? MeridianBanner.Warning : MeridianBanner.Error
            case "stale": return MeridianBanner.Warning
            default: return MeridianBanner.Info
            }
        }
        iconName: {
            switch (root.kind) {
            case "hidepid": return "info"
            case "lost": return "cloud-off"
            case "stale": return "wifi-off"
            default: return "loader-circle"
            }
        }
        title: {
            switch (root.kind) {
            case "lost":
                return root.phase === "reconnecting" ? L10n.t("remoteTabReconnectingTitle", [root.host])
                                                     : L10n.t("remoteTabFailedTitle", [root.host])
            case "stale":
                return root.phase === "reconnecting" ? L10n.t("remoteTabReconnectingTitle", [root.host])
                                                     : L10n.t("remoteTabStaleTitle", [root.host])
            default:
                return ""
            }
        }
        message: {
            switch (root.kind) {
            case "hidepid": return L10n.t("remoteTabHidepid")
            case "installing": return L10n.t("remotePhaseInstalling")
            case "connecting": return L10n.t("remoteTabConnecting", [root.host])
            case "lost": return root.reason
            case "stale": return L10n.t("remoteTabStaleMessage", [Format.clock(root.lastSample), root.reason]).trim()
            default: return ""
            }
        }

        MeridianButton {
            visible: root.kind === "lost" || root.kind === "stale"
            text: root.remote && root.remote.needsHelper ? L10n.t("remoteTabInstallHelper") : L10n.t("remoteTabReconnect")
            controlSize: MeridianButton.Small
            onClicked: Store.app.connectRemoteHost(root.remote.profileId)
        }
    }
}
