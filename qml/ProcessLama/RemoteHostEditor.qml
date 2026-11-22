pragma ComponentBehavior: Bound
import QtQuick
import Meridian

// Adds or edits a remote host profile. Only the alias is stored; users,
// ports and keys belong in ~/.ssh/config.
MeridianDialog {
    id: dialog

    readonly property var app: Store.app
    property var profile: null
    property bool openTabAfterSave: false
    property bool nameEdited: false
    property bool showErrors: false
    property bool saving: false
    property bool testing: false
    property bool autoInstall: false
    property bool autoReconnect: true
    property string startup: "remember"
    property string refresh: ""
    property string probeText: ""
    property bool probeReady: false
    property string saveError: ""
    property int request: 0

    readonly property string aliasValue: aliasField.text.trim()
    readonly property string nameValue: nameField.text.trim().length > 0 ? nameField.text.trim() : aliasValue
    readonly property bool aliasValid: /^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$/.test(aliasValue)
    readonly property bool nameValid: nameValue.length > 0 && nameValue.length <= 64 && !/[\x00-\x1F]/.test(nameValue)
    readonly property string defaultMode: (app.remoteHosts ?? {}).defaultBackgroundRefresh ?? "slow"

    title: profile ? L10n.t("remoteHostEditorEditTitle") : L10n.t("remoteHostEditorAddTitle")
    widthClass: MeridianDialog.Workflow
    submitDisabled: saving

    function edit(value, openTab) {
        profile = value
        openTabAfterSave = openTab && value === null
        aliasField.text = value ? value.alias : ""
        nameField.text = value ? value.displayName : ""
        nameEdited = value !== null
        autoInstall = value ? value.autoInstallHelper : false
        autoReconnect = value ? value.autoReconnect : true
        startup = !value || value.openOnStartup === null || value.openOnStartup === undefined ? "remember"
                : value.openOnStartup ? "always" : "never"
        refresh = value && value.backgroundRefresh ? value.backgroundRefresh : ""
        showErrors = false
        saving = false
        testing = false
        probeText = ""
        probeReady = false
        saveError = ""
        request += 1
        open()
    }

    onOpened: if (!profile) aliasField.forceActiveFocus()

    function test() {
        if (!aliasValid) {
            showErrors = true
            return
        }
        request += 1
        testing = true
        probeText = ""
        app.testRemoteHost(request, aliasValue)
    }

    onSubmitted: {
        if (!aliasValid || !nameValid) {
            showErrors = true
            return
        }
        request += 1
        saving = true
        saveError = ""
        app.saveRemoteHost(request, profile ? profile.id : "", aliasValue, nameValue, autoInstall, autoReconnect,
                           startup, refresh)
    }

    Connections {
        target: dialog.app
        function onProbeFinished(request, outcome, platform, compatibility) {
            if (request !== dialog.request)
                return
            dialog.testing = false
            dialog.probeReady = outcome === "Ready"
            dialog.probeText = Labels.probe(outcome, platform, compatibility)
        }
        function onProfileSaved(request, profileId, error) {
            if (request !== dialog.request)
                return
            dialog.saving = false
            if (error.length > 0) {
                dialog.saveError = L10n.t(error)
                return
            }
            dialog.close()
            if (dialog.openTabAfterSave)
                dialog.app.openRemoteTab(profileId)
        }
    }

    Column {
        width: parent ? parent.width : 0
        spacing: Theme.space.s4

        Column {
            width: parent.width
            spacing: Theme.space.s2
            MeridianText { text: L10n.t("remoteHostAlias"); role: MeridianText.Label }
            MeridianTextField {
                id: aliasField
                width: parent.width
                monospace: true
                maximumLength: 128
                inputMethodHints: Qt.ImhNoAutoUppercase | Qt.ImhNoPredictiveText
                error: dialog.showErrors && !dialog.aliasValid
                Accessible.name: L10n.t("remoteHostAlias")
                onTextEdited: {
                    // A different host must be trusted again.
                    dialog.autoInstall = false
                    dialog.probeText = ""
                    dialog.request += 1
                    dialog.testing = false
                    if (!dialog.nameEdited)
                        nameField.text = text.trim()
                }
                onAccepted: dialog.submit()
            }
            MeridianText {
                width: parent.width
                wrapMode: Text.Wrap
                role: MeridianText.Caption
                color: aliasField.error ? Theme.colors.danger : Theme.colors.inkMuted
                text: aliasField.error ? L10n.t("remoteHostAliasInvalid") : L10n.t("remoteHostAliasHelp")
            }
        }

        Column {
            width: parent.width
            spacing: Theme.space.s2
            MeridianText { text: L10n.t("remoteHostDisplayName"); role: MeridianText.Label }
            MeridianTextField {
                id: nameField
                width: parent.width
                maximumLength: 64
                error: dialog.showErrors && !dialog.nameValid
                Accessible.name: L10n.t("remoteHostDisplayName")
                onTextEdited: dialog.nameEdited = true
                onAccepted: dialog.submit()
            }
            MeridianText {
                visible: nameField.error
                role: MeridianText.Caption
                color: Theme.colors.danger
                text: L10n.t("remoteHostDisplayNameInvalid")
            }
        }

        MeridianSettingsGroup {
            width: parent.width
            MeridianSettingsRow {
                width: parent.width
                label: L10n.t("remoteHostConnection")
                MeridianSwitch {
                    text: L10n.t("remoteHostAutoInstall")
                    checked: dialog.autoInstall
                    onToggled: dialog.autoInstall = checked
                }
                MeridianSwitch {
                    text: L10n.t("remoteHostAutoReconnect")
                    checked: dialog.autoReconnect
                    onToggled: dialog.autoReconnect = checked
                }
            }
            MeridianSettingsRow {
                width: parent.width
                label: L10n.t("remoteHostOpenOnStartup")
                MeridianSegmented {
                    label: L10n.t("remoteHostOpenOnStartup")
                    value: dialog.startup
                    segments: [
                        { value: "remember", label: L10n.t("remoteHostOpenOnStartupRemember") },
                        { value: "always", label: L10n.t("remoteHostOpenOnStartupAlways") },
                        { value: "never", label: L10n.t("remoteHostOpenOnStartupNever") }
                    ]
                    onActivated: value => dialog.startup = value
                }
            }
            MeridianSettingsRow {
                width: parent.width
                label: L10n.t("remoteHostBackgroundRefresh")
                MeridianSelect {
                    label: L10n.t("remoteHostBackgroundRefresh")
                    value: dialog.refresh
                    values: ["", "slow", "live", "paused"]
                    valueLabel: mode => mode === ""
                        ? L10n.t("remoteHostBackgroundRefreshDefault") + " (" + Labels.refresh(dialog.defaultMode) + ")"
                        : Labels.refresh(mode)
                    onActivated: value => dialog.refresh = value
                }
            }
        }

        Item {
            width: parent.width
            height: Math.max(testButton.height, probeLabel.implicitHeight)
            MeridianButton {
                id: testButton
                anchors.verticalCenter: parent.verticalCenter
                text: L10n.t("remoteHostTestConnection")
                iconName: "circle-play"
                loading: dialog.testing
                enabled: !dialog.testing
                onClicked: dialog.test()
            }
            MeridianText {
                id: probeLabel
                anchors.left: testButton.right
                anchors.leftMargin: Theme.space.s4
                anchors.right: guideButton.left
                anchors.rightMargin: Theme.space.s4
                anchors.verticalCenter: parent.verticalCenter
                maximumLineCount: 2
                wrapMode: Text.Wrap
                elide: Text.ElideRight
                role: MeridianText.Caption
                color: dialog.probeReady ? Theme.colors.success : Theme.colors.inkMuted
                text: dialog.testing ? L10n.t("remoteHostProbeRunning") : dialog.probeText
            }
            MeridianButton {
                id: guideButton
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                text: L10n.t("remoteHostSetupGuide")
                iconName: "book-open"
                variant: MeridianButton.Quiet
                onClicked: Store.actions.openSetupGuide()
            }
        }

        MeridianBanner {
            visible: dialog.saveError.length > 0
            width: parent.width
            tone: MeridianBanner.Error
            message: dialog.saveError
        }
    }

    actions: [
        MeridianButton {
            text: L10n.t("remoteHostCancel")
            variant: MeridianButton.Quiet
            onClicked: dialog.close()
        },
        MeridianButton {
            text: L10n.t("remoteHostSave")
            variant: MeridianButton.Primary
            loading: dialog.saving
            enabled: !dialog.saving
            onClicked: dialog.submit()
        }
    ]
}
