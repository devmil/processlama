import QtQuick
import Meridian

// Asks before copying the helper to a host: the host, path, version, size
// and checksum prefix.
MeridianDialog {
    id: dialog

    property var prompt: ({})
    property bool answered: false
    readonly property bool update: prompt.isUpdate ?? false

    title: update ? L10n.t("remoteHelperUpdateTitle", [prompt.host ?? ""])
                  : L10n.t("remoteHelperInstallTitle", [prompt.host ?? ""])
    description: L10n.t("remoteHelperInstallBody")
    widthClass: MeridianDialog.Workflow

    function choose(choice) {
        answered = true
        Store.app.answerHelperInstall(prompt.profileId ?? "", choice)
        close()
    }

    onOpened: {
        answered = false
        installButton.forceActiveFocus()
    }
    onClosed: if (!answered) Store.app.answerHelperInstall(prompt.profileId ?? "", "cancel")
    onSubmitted: choose("install")

    MeridianPropertyList {
        width: parent ? parent.width : 0
        properties: [
            { label: L10n.t("remoteHelperInstallPath"), value: dialog.prompt.installPath ?? "" },
            { label: L10n.t("remoteHelperInstallVersion"), value: (dialog.prompt.platform ?? "–") + " · " + (dialog.prompt.build ?? "") },
            { label: L10n.t("remoteHelperInstallSize"), value: Format.remoteBytes(dialog.prompt.size ?? 0) },
            { label: L10n.t("remoteHelperInstallChecksum"), value: dialog.prompt.sha256 ?? "" }
        ]
    }

    actions: [
        MeridianButton {
            text: L10n.t("remoteHostCancel")
            variant: MeridianButton.Quiet
            onClicked: dialog.choose("cancel")
        },
        MeridianButton {
            text: dialog.update ? L10n.t("remoteHelperUpdateAlways") : L10n.t("remoteHelperInstallAlways")
            onClicked: dialog.choose("installAlways")
        },
        MeridianButton {
            id: installButton
            text: dialog.update ? L10n.t("remoteHelperUpdateAction") : L10n.t("remoteHelperInstallAction")
            variant: MeridianButton.Primary
            onClicked: dialog.choose("install")
        }
    ]
}
