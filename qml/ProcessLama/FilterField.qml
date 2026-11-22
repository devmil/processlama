pragma ComponentBehavior: Bound
import QtQuick
import Meridian

// The process filter with its search aspect, match-case and whole-word menu.
MeridianTextField {
    id: field

    readonly property var app: Store.app
    readonly property var session: Store.session
    readonly property string aspect: session.searchAspect ?? "all"
    readonly property bool matchCase: session.matchCase ?? false
    readonly property bool wholeWord: session.wholeWord ?? false

    variant: MeridianTextField.Search
    clearLabel: L10n.t("clearSearch")
    placeholderText: aspect === "all" ? L10n.t("searchHint")
                   : aspect === "port" ? L10n.t("searchPortHint")
                   : Labels.aspect(aspect) + "…"
    Accessible.name: placeholderText

    // The session owns the filter. Values we sent come back as echoes (some
    // coalesced away); only a value we did not send replaces the text.
    readonly property string sessionFilter: session.filter ?? ""
    property var _pending: []
    property bool _adopting: false
    onSessionFilterChanged: {
        const index = _pending.indexOf(sessionFilter)
        if (index >= 0) {
            _pending.splice(0, index + 1)
            return
        }
        _pending = []
        if (text !== sessionFilter) {
            _adopting = true
            text = sessionFilter
            _adopting = false
        }
    }
    Component.onCompleted: text = sessionFilter
    onTextChanged: {
        if (_adopting || text === sessionFilter && _pending.length === 0)
            return
        _pending.push(text)
        app.setFilter(text)
    }

    trailingContent: [
        MeridianIconButton {
            id: aspectButton
            anchors.verticalCenter: parent ? parent.verticalCenter : undefined
            text: L10n.t("searchAspect") + ": " + Labels.aspect(field.aspect)
            iconName: "list-filter"
            controlSize: MeridianButton.Small
            active: field.aspect !== "all" || field.matchCase || field.wholeWord
            focusPolicy: Qt.NoFocus
            onClicked: aspectMenu.popup(aspectButton, 0, aspectButton.height)
        }
    ]

    MeridianMenu {
        id: aspectMenu
        Instantiator {
            model: Labels.aspects
            delegate: MeridianMenuItem {
                required property string modelData
                text: Labels.aspect(modelData)
                checked: field.aspect === modelData
                onTriggered: field.app.setSearchAspect(modelData)
            }
            onObjectAdded: (index, object) => aspectMenu.insertItem(index, object)
            onObjectRemoved: (index, object) => aspectMenu.removeItem(object)
        }
        MeridianMenuSeparator { visible: field.aspect !== "port"; height: visible ? implicitHeight : 0 }
        MeridianMenuItem {
            visible: field.aspect !== "port"
            height: visible ? implicitHeight : 0
            text: L10n.t("matchCase")
            iconName: "case-sensitive"
            checked: field.matchCase
            onTriggered: field.app.setSearchMatchCase(!field.matchCase)
        }
        MeridianMenuItem {
            visible: field.aspect !== "port"
            height: visible ? implicitHeight : 0
            text: L10n.t("wholeWord")
            iconName: "whole-word"
            checked: field.wholeWord
            onTriggered: field.app.setSearchWholeWord(!field.wholeWord)
        }
    }
}
