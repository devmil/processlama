import QtQuick
import QtQuick.Templates as T
import Meridian

// The diagnostics page: detailed logging, clearing, and a preview to save.
Column {
    id: page

    readonly property var app: Store.app
    property string preview: ""
    property string status: ""

    spacing: Theme.space.s4

    Flow {
        width: parent.width
        spacing: Theme.space.s4
        MeridianButton {
            text: page.app.diagnosticsDetailed ? L10n.t("diagnosticsDisable") : L10n.t("diagnosticsEnable")
            onClicked: page.app.setDiagnosticsDetailed(!page.app.diagnosticsDetailed)
        }
        MeridianButton {
            text: L10n.t("diagnosticsClear")
            onClicked: {
                page.app.clearDiagnostics()
                page.preview = ""
                page.status = ""
            }
        }
        MeridianButton {
            text: L10n.t("diagnosticsPreview")
            onClicked: {
                page.preview = page.app.diagnosticsSnapshot()
                page.status = ""
            }
        }
    }

    Rectangle {
        visible: page.preview.length > 0
        width: parent.width
        height: Theme.size.toolbar * 6
        radius: Theme.radius.md
        color: Theme.colors.paneAlt
        Flickable {
            id: previewScroll
            anchors.fill: parent
            anchors.margins: Theme.space.s3
            clip: true
            contentHeight: previewText.height
            boundsBehavior: Flickable.StopAtBounds
            MeridianSelectableText {
                id: previewText
                width: previewScroll.width
                text: page.preview
                role: MeridianText.CodeSm
                wrapMode: TextEdit.Wrap
            }
            T.ScrollBar.vertical: MeridianScrollBar {}
        }
    }

    Flow {
        visible: page.preview.length > 0
        width: parent.width
        spacing: Theme.space.s4
        MeridianButton {
            text: L10n.t("diagnosticsSave")
            onClicked: Store.actions.saveDiagnostics(page.preview,
                ok => page.status = ok ? L10n.t("diagnosticsSaved") : L10n.t("diagnosticsFailed"))
        }
        MeridianButton {
            text: L10n.t("diagnosticsCancel")
            onClicked: page.preview = ""
        }
    }

    MeridianText {
        visible: page.status.length > 0
        text: page.status
    }
}
