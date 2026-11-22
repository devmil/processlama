pragma ComponentBehavior: Bound
import QtQuick
import Meridian

// The Remote hosts page of the preferences: the profiles with their actions,
// the default background refresh and the remote icon cache.
MeridianSettingsGroup {
    id: page

    readonly property var app: Store.app
    readonly property var hosts: app.remoteHosts ?? ({})
    readonly property var profiles: hosts.profiles ?? []
    readonly property int limitMiB: Math.round((hosts.iconCacheBytes ?? 0) / (1024 * 1024))
    readonly property var cacheChoices: {
        const values = [16, 32, 64, 128, 256]
        if (values.indexOf(limitMiB) < 0)
            values.push(limitMiB)
        return values.sort((a, b) => a - b)
    }
    property var menuProfile: null

    MeridianSettingsRow {
        width: parent.width
        label: L10n.t("remoteHostsProfiles")

        MeridianText {
            visible: page.profiles.length === 0
            text: L10n.t("remoteHostsEmpty")
            role: MeridianText.Caption
            color: Theme.colors.inkMuted
        }
        Repeater {
            model: page.profiles
            Item {
                id: profileRow
                required property var modelData
                readonly property var profile: modelData
                width: parent.width
                height: Math.max(actionsButton.height, info.implicitHeight)
                readonly property string details: {
                    const parts = [profile.alias]
                    parts.push(profile.lastKnownPlatform
                        ? L10n.t("remoteHostLastSeen", [profile.lastKnownPlatform, String(profile.lastKnownCompatibility)])
                        : L10n.t("remoteHostNeverConnected"))
                    if (profile.autoInstallHelper)
                        parts.push(L10n.t("remoteHostAutoInstallOn"))
                    return parts.join(" · ")
                }

                MeridianStatusDot {
                    id: dot
                    anchors.verticalCenter: parent.verticalCenter
                    tone: AppTheme.phaseTone(profileRow.profile.phase)
                    semanticLabel: Labels.phase(profileRow.profile.phase)
                }
                Column {
                    id: info
                    anchors.left: dot.right
                    anchors.leftMargin: Theme.space.s3
                    anchors.right: actionsButton.left
                    anchors.verticalCenter: parent.verticalCenter
                    MeridianText {
                        width: parent.width
                        text: profileRow.profile.displayName
                        role: MeridianText.Label
                        elide: Text.ElideRight
                    }
                    MeridianText {
                        width: parent.width
                        text: profileRow.details
                        role: MeridianText.Caption
                        color: Theme.colors.inkMuted
                        elide: Text.ElideRight
                    }
                }
                MeridianIconButton {
                    id: actionsButton
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    text: L10n.t("remoteHostActions", [profileRow.profile.displayName])
                    iconName: "ellipsis"
                    controlSize: MeridianButton.Small
                    onClicked: {
                        page.menuProfile = profileRow.profile
                        profileMenu.popup(actionsButton, 0, actionsButton.height)
                    }
                }
            }
        }
        MeridianButton {
            text: L10n.t("remoteHostAdd")
            iconName: "circle-plus"
            controlSize: MeridianButton.Small
            onClicked: Store.actions.showRemoteHostEditor(null)
        }
    }

    MeridianSettingsRow {
        width: parent.width
        label: L10n.t("remoteHostsDefaultRefresh")
        MeridianSegmented {
            label: L10n.t("remoteHostsDefaultRefresh")
            value: page.hosts.defaultBackgroundRefresh
            segments: ["slow", "live", "paused"].map(mode => ({ value: mode, label: Labels.refresh(mode) }))
            onActivated: value => page.app.setDefaultBackgroundRefresh(value)
        }
    }

    MeridianSettingsRow {
        width: parent.width
        label: L10n.t("remoteIconCache")
        help: L10n.t("remoteIconCacheUsage", [Format.remoteBytes(page.hosts.iconCacheUsed ?? 0),
                                               Format.remoteBytes(page.hosts.iconCacheBytes ?? 0)])
        Flow {
            width: parent.width
            spacing: Theme.space.s3
            MeridianSelect {
                label: L10n.t("remoteIconCache")
                value: page.limitMiB
                values: page.cacheChoices
                valueLabel: mib => Format.remoteBytes(mib * 1024 * 1024)
                onActivated: value => page.app.setRemoteIconCacheBytes(value * 1024 * 1024)
            }
            MeridianButton {
                text: L10n.t("remoteIconCacheClear")
                controlSize: MeridianButton.Small
                onClicked: {
                    page.app.clearRemoteIconCache()
                    Store.actions.toast(L10n.t("remoteIconCacheCleared"), "success")
                }
            }
        }
    }

    MeridianMenu {
        id: profileMenu
        readonly property bool connected: page.menuProfile !== null
            && (page.menuProfile.phase === "live" || page.menuProfile.phase === "reconnecting")
        MeridianMenuItem {
            text: L10n.t("remoteHostEdit")
            iconName: "pencil"
            onTriggered: Store.actions.showRemoteHostEditor(page.menuProfile)
        }
        MeridianMenuItem {
            text: profileMenu.connected ? L10n.t("remoteHostDisconnect") : L10n.t("remoteHostConnect")
            iconName: profileMenu.connected ? "cloud-off" : "cloud"
            onTriggered: profileMenu.connected ? page.app.disconnectRemoteHost(page.menuProfile.id)
                                               : page.app.connectRemoteHost(page.menuProfile.id)
        }
        MeridianMenuItem {
            text: L10n.t("remoteHostDuplicate")
            iconName: "copy"
            onTriggered: page.app.duplicateRemoteHost(page.menuProfile.id)
        }
        MeridianMenuItem {
            text: L10n.t("remoteHostRemove")
            iconName: "trash-2"
            danger: true
            onTriggered: Store.actions.removeHost(page.menuProfile.id)
        }
        MeridianMenuSeparator {}
        MeridianMenuItem {
            text: L10n.t("remoteHelperRemoveMenu")
            iconName: "trash"
            danger: true
            onTriggered: Store.actions.removeHelper(page.menuProfile.id)
        }
    }
}
