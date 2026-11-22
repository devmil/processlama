pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Dialogs
import QtCore
import Meridian

// The window's dialogs, confirmations, file pickers, clipboard and toasts.
// Components reach it as `Store.actions`. While any dialog is open the tree
// keeps its row order (setModalOverlayOpen).
Item {
    id: dialogs

    required property var window
    required property string licensePackages

    readonly property var app: Store.app
    readonly property int openDialogs: [confirmDialog, renameDialog, updateDialog, networkDialog, aboutDialog,
        licenseDialog, preferences, remoteEditor, helperInstall].filter(dialog => dialog.visible).length
    readonly property string releasesUrl: "https://devmil.de/processlama/releases.html"
    readonly property string remoteHostsGuideUrl: "https://devmil.de/processlama/remote-hosts.html"

    anchors.fill: parent
    z: 900

    onOpenDialogsChanged: if (app) app.setModalOverlayOpen(openDialogs > 0)


    // Toasts and the clipboard

    function toast(message, tone) {
        window.showToast(message.trim(), tone)
    }

    function copy(text, toastKey) {
        clipboard.text = text
        clipboard.selectAll()
        clipboard.copy()
        clipboard.text = ""
        if (toastKey && toastKey.length > 0)
            toast(L10n.t(toastKey), "success")
    }

    TextEdit { id: clipboard; visible: false }

    function openUrl(url, failureKey) {
        if (!Qt.openUrlExternally(url) && failureKey)
            toast(L10n.t(failureKey), "error")
    }

    function openSetupGuide() { openUrl(remoteHostsGuideUrl) }

    // Confirmations

    property var _onConfirm: null

    function confirm(title, description, confirmLabel, destructive, onConfirm, cancelLabel) {
        _onConfirm = onConfirm
        confirmDialog.title = title
        confirmDialog.description = description
        confirmDialog.confirmLabel = confirmLabel
        confirmDialog.cancelLabel = cancelLabel ?? L10n.t("processActionConfirmCancel")
        confirmDialog.destructive = destructive
        confirmDialog.open()
    }

    MeridianConfirm {
        id: confirmDialog
        onConfirmed: {
            const run = dialogs._onConfirm
            dialogs._onConfirm = null
            close()
            if (run)
                run()
        }
        onCancelled: {
            dialogs._onConfirm = null
            close()
        }
    }

    /// Terminate, kill and suspend ask first; resume runs directly. On a
    /// remote tab the question names the host.
    function signalProcess(key, signal, name, pid) {
        if (signal === "resume") {
            app.sendSignal(key, signal)
            return
        }
        const host = Store.remote && Store.session.remote ? Store.session.remote.host : ""
        const args = host.length > 0 ? [name, pid, host] : [name, pid]
        const prefix = host.length > 0 ? "remote" : ""
        const body = (verb) => host.length > 0 ? prefix + verb + "ConfirmBody" : verb.charAt(0).toLowerCase() + verb.slice(1) + "ConfirmBody"
        switch (signal) {
        case "terminate":
            confirm(L10n.t("terminateConfirmTitle"), L10n.t(body("Terminate"), args), L10n.t("terminateProcessMenu"), false,
                    () => app.sendSignal(key, signal))
            break
        case "kill":
            confirm(L10n.t("killConfirmTitle"), L10n.t(body("Kill"), args), L10n.t("killProcessMenu"), true,
                    () => app.sendSignal(key, signal))
            break
        case "suspend":
            confirm(L10n.t("suspendConfirmTitle"), L10n.t(body("Suspend"), args), L10n.t("suspendProcessMenu"), false,
                    () => app.sendSignal(key, signal))
            break
        }
    }

    // Snapshots

    function takeSnapshot() { app.takeSnapshot() }
    function loadSnapshot(path) { app.openSnapshot(path) }
    function openSnapshot() { openDialog.open() }
    function deleteSnapshot(entry) { app.deleteSnapshot(entry.path) }

    property var _exporting: null
    function exportSnapshot(entry) {
        _exporting = entry
        exportDialog.selectedFile = exportDialog.currentFolder + "/" + snapshotExportFileName(entry)
        exportDialog.open()
    }

    function renameSnapshot(entry) {
        renameDialog.path = entry.path
        renameField.text = entry.name ?? ""
        renameDialog.open()
    }

    /// `<name>.processlama-snapshot.json`, or the snapshot time without a name.
    function snapshotExportFileName(entry) {
        let base = (entry.name ?? "").trim()
            .replace(/\.processlama-snapshot\.json$/i, "")
            .replace(/\.json$/i, "")
        base = base.replace(/[<>:"/\\|?*\x00-\x1F]/g, "-").replace(/\s+/g, " ").replace(/-+/g, "-").trim()
        return (base.length > 0 ? base : "snapshot-" + entry.generatedAt) + ".processlama-snapshot.json"
    }

    FileDialog {
        id: openDialog
        title: L10n.t("openSnapshot")
        fileMode: FileDialog.OpenFile
        nameFilters: ["JSON (*.json)"]
        currentFolder: StandardPaths.writableLocation(StandardPaths.DocumentsLocation)
        onAccepted: dialogs.app.openSnapshot(dialogs.app.localFile(selectedFile.toString()))
    }

    FileDialog {
        id: exportDialog
        title: L10n.t("exportSnapshot")
        fileMode: FileDialog.SaveFile
        nameFilters: ["JSON (*.json)"]
        defaultSuffix: "json"
        currentFolder: StandardPaths.writableLocation(StandardPaths.DocumentsLocation)
        onAccepted: {
            if (dialogs._exporting)
                dialogs.app.exportSnapshot(dialogs._exporting.path, dialogs.app.localFile(selectedFile.toString()))
            dialogs._exporting = null
        }
        onRejected: dialogs._exporting = null
    }

    MeridianDialog {
        id: renameDialog
        property string path
        title: L10n.t("renameSnapshotTitle")
        widthClass: MeridianDialog.Form
        onOpened: {
            renameField.forceActiveFocus()
            renameField.selectAll()
        }
        onSubmitted: {
            const name = renameField.text.trim()
            close()
            if (name.length > 0)
                dialogs.app.renameSnapshot(path, name)
        }

        Column {
            width: parent ? parent.width : 0
            spacing: Theme.space.s2
            MeridianText { text: L10n.t("snapshotName"); role: MeridianText.Label }
            MeridianTextField {
                id: renameField
                width: parent.width
                Accessible.name: L10n.t("snapshotName")
                onAccepted: renameDialog.submit()
            }
        }

        actions: [
            MeridianButton {
                text: L10n.t("processActionConfirmCancel")
                variant: MeridianButton.Quiet
                onClicked: renameDialog.close()
            },
            MeridianButton {
                text: L10n.t("renameSnapshotTitle")
                variant: MeridianButton.Primary
                onClicked: renameDialog.submit()
            }
        ]
    }

    // Updates and network telemetry

    function checkForUpdates() { app.checkForUpdates() }

    function showUpdateAvailable(installedVersion, installedBuild, version, build) {
        updateDialog.title = L10n.t("updateAvailableTitle", [version])
        updateDialog.description = L10n.t("updateAvailableBody", [installedVersion, installedBuild, build])
        updateDialog.open()
    }

    MeridianDialog {
        id: updateDialog
        onOpened: openDownloads.forceActiveFocus()
        onSubmitted: openDownloads.clicked()
        actions: [
            MeridianButton {
                text: L10n.t("later")
                variant: MeridianButton.Quiet
                onClicked: updateDialog.close()
            },
            MeridianButton {
                id: openDownloads
                text: L10n.t("openDownloads")
                iconName: "external-link"
                variant: MeridianButton.Primary
                onClicked: {
                    updateDialog.close()
                    dialogs.openUrl(dialogs.releasesUrl, "updateDownloadOpenFailed")
                }
            }
        ]
    }

    function installNetworkTelemetry() { networkDialog.open() }

    MeridianDialog {
        id: networkDialog
        title: L10n.t("installNetworkTelemetry")
        description: L10n.t("networkTelemetryInstallDescription")
        onSubmitted: {
            close()
            dialogs.app.installNetworkTelemetry()
        }
        actions: [
            MeridianButton {
                text: L10n.t("later")
                variant: MeridianButton.Quiet
                onClicked: networkDialog.close()
            },
            MeridianButton {
                text: L10n.t("installNetworkTelemetry")
                variant: MeridianButton.Primary
                onClicked: networkDialog.submit()
            }
        ]
    }

    // About and licenses

    function showAbout() { aboutDialog.open() }
    function showLicenses() { licenseDialog.open() }

    readonly property string versionLabel: Store.platform.version
        ? L10n.t("aboutVersion", [Store.platform.version, Store.platform.build]) : ""

    MeridianDialog {
        id: aboutDialog
        title: L10n.t("aboutApp")
        onOpened: closeAbout.forceActiveFocus()
        onSubmitted: close()

        Column {
            width: parent ? parent.width : 0
            Image {
                source: "qrc:/ProcessLama/brand/tile-mimameidr.svg"
                width: AppTheme.aboutTileSize
                height: AppTheme.aboutTileSize
                sourceSize: Qt.size(width * 2, height * 2)
                Accessible.ignored: true
            }
            Item { width: 1; height: Theme.space.s4 }
            MeridianText { text: L10n.t("aboutProductName"); role: MeridianText.BodyStrong }
            MeridianText { text: L10n.t("makerLine") }
            MeridianText { text: dialogs.versionLabel; role: MeridianText.Caption; visible: text.length > 0 }
            Item { width: 1; height: Theme.space.s4 }
            MeridianText { text: L10n.t("lamaFamily"); role: MeridianText.BodyStrong }
            MeridianText {
                width: parent.width
                wrapMode: Text.Wrap
                text: "ProcessLama · GitLama · MailLama · ShotLama · NoteLama"
            }
        }

        actions: [
            MeridianButton {
                text: L10n.t("aboutLicenses")
                onClicked: licenseDialog.open()
            },
            MeridianButton {
                id: closeAbout
                text: L10n.t("closeAbout")
                onClicked: aboutDialog.close()
            }
        ]
    }

    MeridianLicenseDialog {
        id: licenseDialog
        packages: JSON.parse(dialogs.licensePackages)
        applicationName: L10n.t("aboutProductName")
        applicationVersion: dialogs.versionLabel
        applicationIcon: "qrc:/ProcessLama/brand/tile-mimameidr.svg"
        closeLabel: L10n.t("close")
    }

    // Preferences

    function showPreferences(page) {
        preferences.currentPage = page ?? 0
        preferences.open()
    }

    PreferencesDialog {
        id: preferences
    }

    // Remote hosts

    /// `openTab`: a host added from the tab strip opens in a tab once saved.
    function showRemoteHostEditor(profile, openTab) {
        remoteEditor.edit(profile ?? null, openTab ?? false)
    }

    RemoteHostEditor {
        id: remoteEditor
    }

    function showHelperInstall(prompt) {
        helperInstall.prompt = prompt
        helperInstall.open()
    }

    HelperInstallDialog {
        id: helperInstall
    }

    function hostName(profileId) {
        const profiles = (Store.app.remoteHosts ?? {}).profiles ?? []
        const profile = profiles.find(p => p.id === profileId)
        return profile ? profile.displayName : ""
    }

    function removeHelper(profileId) {
        confirm(L10n.t("remoteHelperRemoveTitle", [hostName(profileId)]), L10n.t("remoteHelperRemoveBody"),
                L10n.t("remoteHelperRemoveAction"), true, () => app.removeRemoteHelper(profileId),
                L10n.t("remoteHostCancel"))
    }

    function removeHost(profileId) {
        confirm(L10n.t("remoteHostRemoveTitle", [hostName(profileId)]), L10n.t("remoteHostRemoveBody"),
                L10n.t("remoteHostRemove"), true, () => app.removeRemoteHost(profileId), L10n.t("remoteHostCancel"))
    }

    // Diagnostics

    function saveDiagnostics(text, onDone) {
        diagnosticsDialog.text = text
        diagnosticsDialog.onDone = onDone
        diagnosticsDialog.selectedFile = diagnosticsDialog.currentFolder + "/processlama-diagnostics.txt"
        diagnosticsDialog.open()
    }

    FileDialog {
        id: diagnosticsDialog
        property string text
        property var onDone: null
        title: L10n.t("diagnosticsSave")
        fileMode: FileDialog.SaveFile
        nameFilters: ["Text (*.txt)"]
        defaultSuffix: "txt"
        currentFolder: StandardPaths.writableLocation(StandardPaths.DocumentsLocation)
        onAccepted: {
            const ok = dialogs.app.writeTextFile(selectedFile.toString(), text)
            if (onDone)
                onDone(ok)
        }
    }
}
