pragma Singleton
import QtQuick

// The localized text of columns, search aspects, remote states and failures.
QtObject {
    readonly property var columnKeys: ({
        pid: "columnPid", name: "columnName", cpu: "columnCpu", treeCpu: "columnTreeCpu",
        gpu: "columnGpu", treeGpu: "columnTreeGpu", memory: "columnRss", treeMemory: "columnTreeRss",
        networkIn: "columnNetIn", networkOut: "columnNetOut", treeNetworkIn: "columnTreeNetIn",
        treeNetworkOut: "columnTreeNetOut", storageRead: "columnStorageRead", storageWrite: "columnStorageWrite",
        treeStorageRead: "columnTreeStorageRead", treeStorageWrite: "columnTreeStorageWrite",
        startTime: "columnStarted", status: "columnState", uid: "columnUid", ports: "columnPorts"
    })
    readonly property var availableColumns: ["name", "pid", "cpu", "treeCpu", "gpu", "treeGpu", "memory",
        "treeMemory", "networkIn", "networkOut", "treeNetworkIn", "treeNetworkOut", "storageRead",
        "storageWrite", "treeStorageRead", "treeStorageWrite", "startTime", "status", "uid", "ports"]
    /// Default widths of the fixed columns; `name` flexes.
    readonly property var columnWidths: ({
        pid: 86, cpu: 82, treeCpu: 96, gpu: 72, treeGpu: 96, memory: 112, treeMemory: 112,
        networkIn: 94, networkOut: 94, treeNetworkIn: 118, treeNetworkOut: 126, storageRead: 104,
        storageWrite: 104, treeStorageRead: 132, treeStorageWrite: 132, startTime: 96, status: 98,
        uid: 76, ports: 120
    })
    readonly property var aspects: ["all", "name", "pid", "user", "command", "path", "port"]

    function column(id) {
        const key = columnKeys[id]
        return key ? L10n.t(key) : id
    }

    function aspect(id) {
        switch (id) {
        case "name": return L10n.t("searchName")
        case "pid": return L10n.t("searchPid")
        case "user": return L10n.t("searchUser")
        case "command": return L10n.t("searchCommand")
        case "path": return L10n.t("searchPath")
        case "port": return L10n.t("searchPort")
        default: return L10n.t("searchAll")
        }
    }

    function phase(id) {
        switch (id) {
        case "idle": return L10n.t("remotePhaseIdle")
        case "probing":
        case "handshaking": return L10n.t("remotePhaseConnecting")
        case "installing": return L10n.t("remotePhaseInstalling")
        case "live": return L10n.t("remotePhaseLive")
        case "reconnecting": return L10n.t("remotePhaseReconnecting")
        case "disconnected": return L10n.t("remotePhaseDisconnected")
        default: return L10n.t("remotePhaseFailed")
        }
    }

    function failure(code) {
        if (!code)
            return ""
        const key = "remoteFailure" + code.charAt(0).toUpperCase() + code.slice(1)
        const text = L10n.t(key)
        return text === key ? L10n.t("remoteFailureInternal") : text
    }

    function refresh(mode) {
        switch (mode) {
        case "slow": return L10n.t("remoteRefreshSlow")
        case "paused": return L10n.t("remoteRefreshPaused")
        default: return L10n.t("remoteRefreshLive")
        }
    }

    function probe(outcome, platform, compatibility) {
        switch (outcome) {
        case "SshUnreachable": return L10n.t("remoteHostProbeSshUnreachable")
        case "HostKeyUntrusted": return L10n.t("remoteHostProbeHostKeyUntrusted")
        case "AuthenticationInteractive": return L10n.t("remoteHostProbeAuthenticationInteractive")
        case "UnsupportedPlatform": return L10n.t("remoteHostProbeUnsupportedPlatform")
        case "HelperMissing": return L10n.t("remoteHostProbeHelperMissing")
        case "HelperOutdated": return L10n.t("remoteHostProbeHelperOutdated")
        default: return L10n.t("remoteHostProbeReady", [platform || "–", compatibility || "–"])
        }
    }

    /// A toast's text. Arguments starting with "@failure:" name a failure
    /// code the core passes untranslated.
    function toast(key, args) {
        const values = (args || []).map(value => {
            const text = String(value)
            return text.startsWith("@failure:") ? failure(text.slice(9)) : text
        })
        return L10n.t(key, values)
    }
}
