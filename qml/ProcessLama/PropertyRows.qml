pragma ComponentBehavior: Bound
import QtQuick
import Meridian

// MeridianPropertyList for values that change every sample: rows are kept
// while the count holds, so selections survive and nothing is rebuilt.
// `properties` is an array of { label, value, monospace }.
Column {
    id: root

    property var properties: []
    property real labelWidth: Metrics.propertyLabelColumn
    readonly property bool stacked: Theme.touch || width < labelWidth * Metrics.propertyStackFactor

    spacing: Theme.space.s3

    Repeater {
        model: root.properties.length
        delegate: Item {
            id: row
            required property int index
            readonly property var entry: root.properties[index] ?? ({ label: "", value: "" })
            width: root.width
            height: root.stacked ? label.height + Theme.space.s1 + value.height : Math.max(label.height, value.height)
            Accessible.role: Accessible.StaticText
            Accessible.name: entry.label + ": " + entry.value

            MeridianText {
                id: label
                width: root.stacked ? row.width : root.labelWidth
                role: MeridianText.Caption
                color: Theme.colors.inkMuted
                text: row.entry.label
                wrapMode: Text.Wrap
                elide: Text.ElideNone
                y: root.stacked ? 0 : Math.max(0, (value.firstLineHeight - Theme.type.captionLineHeight) / 2)
                Accessible.ignored: true
            }
            MeridianSelectableText {
                id: value
                x: root.stacked ? 0 : root.labelWidth + Theme.space.s4
                y: root.stacked ? label.height + Theme.space.s1 : 0
                width: row.width - x
                role: row.entry.monospace ? MeridianText.Code : MeridianText.Body
                tabular: row.entry.monospace === true
                text: row.entry.value
                Accessible.ignored: true
            }
        }
    }
}
