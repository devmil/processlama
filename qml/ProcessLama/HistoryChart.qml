pragma ComponentBehavior: Bound
import QtQuick
import Meridian

// A history chart on a pane-alt inset: the metric's name and current value
// over 60 right-aligned bars, its scale on the left. `diverging` draws the
// upper series up and the lower series down from a centre axis. The bar
// under the pointer takes the highlight from the latest and shows its value.
Rectangle {
    id: root

    property string label
    property string detail
    property string value
    property var samples: []
    property var lowerSamples: []
    property bool diverging: false
    property real scaleMax: 0.1
    property var formatValue: v => String(v)
    readonly property int slots: 60
    readonly property real chartHeight: diverging ? 56 : 44
    readonly property int sampleCount: diverging ? Math.max(samples.length, lowerSamples.length) : samples.length
    readonly property int leading: Math.max(0, slots - sampleCount)
    property int hovered: -1
    readonly property int highlighted: hovered >= 0 && hovered < sampleCount ? hovered : sampleCount - 1
    readonly property var scaleLabels: diverging
        ? [Format.rate(scaleMax), "0", Format.rate(scaleMax)]
        : [formatValue(scaleMax), formatValue(scaleMax / 2), formatValue(0)]

    function sampleAt(list, index) {
        return index < list.length ? list[index] : 0
    }
    function hoverLabel(index) {
        if (!diverging) {
            const sample = samples[index]
            return isFinite(sample) ? formatValue(sample) : "–"
        }
        const upper = sampleAt(samples, index)
        const lower = sampleAt(lowerSamples, index)
        if (!isFinite(upper) && !isFinite(lower))
            return "–"
        const rate = v => isFinite(v) ? Format.rate(v) : "–"
        return rate(upper) + " / " + rate(lower)
    }

    width: parent ? parent.width : 0
    height: content.height + 2 * Theme.space.s4
    radius: Theme.radius.md
    color: Theme.colors.paneAlt

    Column {
        id: content
        x: Theme.space.s5
        y: Theme.space.s4
        width: parent.width - 2 * Theme.space.s5
        spacing: Theme.space.s3

        Item {
            width: parent.width
            height: Math.max(titles.height, valueText.height)
            Column {
                id: titles
                anchors.left: parent.left
                anchors.right: valueText.left
                anchors.rightMargin: Theme.space.s4
                anchors.bottom: parent.bottom
                MeridianText { width: parent.width; text: root.label; role: MeridianText.Label; elide: Text.ElideRight }
                MeridianText {
                    visible: root.detail.length > 0
                    width: parent.width
                    text: root.detail
                    role: MeridianText.Caption
                    color: Theme.colors.inkMuted
                    elide: Text.ElideRight
                }
            }
            MeridianText {
                id: valueText
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                text: root.value
                role: MeridianText.Code
                tabular: true
                fontWeight: Font.DemiBold
            }
        }

        Item {
            width: parent.width
            height: root.chartHeight

            Column {
                id: scaleColumn
                width: 64
                height: parent.height
                spacing: (height - 3 * Theme.type.codeSm.pixelSize) / 2
                // Counted, not the label array: a new array each poll would
                // recreate the labels.
                Repeater {
                    model: root.scaleLabels.length
                    MeridianText {
                        required property int index
                        width: scaleColumn.width
                        height: Theme.type.codeSm.pixelSize
                        horizontalAlignment: Text.AlignRight
                        verticalAlignment: Text.AlignVCenter
                        fontSizeMode: Text.HorizontalFit
                        minimumPixelSize: 6
                        role: MeridianText.CodeSm
                        tabular: true
                        color: Theme.colors.inkMuted
                        lineHeight: 1
                        text: root.scaleLabels[index] ?? ""
                    }
                }
            }

            Item {
                id: chart
                anchors.left: scaleColumn.right
                anchors.leftMargin: Theme.space.s3
                anchors.right: parent.right
                height: parent.height
                readonly property real slotWidth: width / root.slots
                readonly property real zeroY: root.diverging ? height / 2 : height
                readonly property real span: root.diverging ? height / 2 : height
                readonly property real effectiveMax: Math.max(0.1, root.scaleMax)

                Rectangle {
                    visible: root.diverging
                    y: chart.zeroY - 0.5
                    width: parent.width
                    height: 1
                    color: Theme.colors.lineStrong
                }

                Repeater {
                    objectName: "bars"
                    model: root.sampleCount
                    Item {
                        id: bar
                        required property int index
                        readonly property bool latest: index === root.highlighted
                        // Bars fill their slots edge to edge on whole pixels, so
                        // no uneven gaps appear between them.
                        readonly property real x0: Math.round((root.leading + index) * chart.slotWidth)
                        readonly property real x1: Math.round((root.leading + index + 1) * chart.slotWidth)
                        readonly property real upper: root.sampleAt(root.samples, index)
                        readonly property real lower: root.diverging ? root.sampleAt(root.lowerSamples, index) : 0
                        readonly property real upperHeight: isFinite(upper) ? chart.span * Math.max(0, Math.min(1, upper / chart.effectiveMax)) : 0
                        readonly property real lowerHeight: isFinite(lower) ? chart.span * Math.max(0, Math.min(1, lower / chart.effectiveMax)) : 0
                        Rectangle {
                            visible: bar.upperHeight > 0
                            x: bar.x0
                            y: chart.zeroY - bar.upperHeight
                            width: Math.max(1, bar.x1 - bar.x0)
                            height: bar.upperHeight
                            color: root.diverging
                                ? (bar.latest ? AppTheme.chartUpper : Qt.alpha(AppTheme.chartUpper, AppTheme.chartHistoryOpacity))
                                : (bar.latest ? Theme.colors.accent : Qt.alpha(AppTheme.chartLine, AppTheme.chartHistoryOpacity))
                        }
                        Rectangle {
                            visible: root.diverging && bar.lowerHeight > 0
                            x: bar.x0
                            y: chart.zeroY
                            width: Math.max(1, bar.x1 - bar.x0)
                            height: bar.lowerHeight
                            color: bar.latest ? AppTheme.chartLower : Qt.alpha(AppTheme.chartLower, AppTheme.chartHistoryOpacity)
                        }
                    }
                }

                HoverHandler {
                    id: hover
                    onPointChanged: {
                        if (!hovered)
                            return
                        const slot = Math.floor(point.position.x / chart.slotWidth)
                        const index = slot - root.leading
                        root.hovered = index >= 0 && index < root.sampleCount ? index : -1
                    }
                    onHoveredChanged: if (!hovered) root.hovered = -1
                }

                // The hovered value, kept inside the chart at both ends.
                Rectangle {
                    visible: root.hovered >= 0 && root.hovered < root.sampleCount
                    readonly property real center: (root.leading + root.hovered + 0.5) * chart.slotWidth
                    x: Math.max(0, Math.min(chart.width - width, center - width / 2))
                    y: 0
                    width: hoverText.implicitWidth + 2 * Theme.space.s2
                    height: hoverText.implicitHeight + 2 * Theme.space.s1
                    radius: Theme.radius.xs
                    color: Theme.colors.raised
                    MeridianShadow { anchors.fill: parent; z: -1; layers: Theme.shadows.float; radius: Theme.radius.xs }
                    MeridianText {
                        id: hoverText
                        anchors.centerIn: parent
                        role: MeridianText.CodeSm
                        tabular: true
                        text: root.hovered >= 0 ? root.hoverLabel(root.hovered) : ""
                    }
                }
            }
        }
    }
}
