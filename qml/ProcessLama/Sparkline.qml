import QtQuick
import QtQuick.Shapes

// A row's recent CPU as a line with its latest sample marked. A gap (NaN)
// lifts the pen: the line never crosses an outage.
Item {
    id: root

    property var samples: []
    property real maxValue: 0
    property color lineColor: AppTheme.chartLine
    property color endpointColor: "transparent"
    readonly property real endpointRadius: 1.6

    readonly property real effectiveMax: {
        let max = maxValue
        if (!(max > 0)) {
            for (const sample of samples)
                if (isFinite(sample) && sample > max)
                    max = sample
        }
        return Math.max(0.1, max)
    }
    readonly property var lines: {
        const result = []
        const count = samples ? samples.length : 0
        if (count < 2)
            return result
        const step = width / (count - 1)
        let current = null
        for (let index = 0; index < count; ++index) {
            const sample = samples[index]
            if (!isFinite(sample)) {
                current = null
                continue
            }
            if (current === null) {
                current = []
                result.push(current)
            }
            current.push(Qt.point(index * step, height * (1 - sample / effectiveMax)))
        }
        return result
    }
    readonly property real last: samples && samples.length >= 2 ? samples[samples.length - 1] : NaN

    implicitWidth: 52
    implicitHeight: 14
    width: implicitWidth
    height: implicitHeight

    Shape {
        anchors.fill: parent
        preferredRendererType: Shape.CurveRenderer
        ShapePath {
            strokeColor: root.lineColor
            strokeWidth: 1
            fillColor: "transparent"
            capStyle: ShapePath.RoundCap
            joinStyle: ShapePath.RoundJoin
            PathMultiline { paths: root.lines }
        }
    }

    Rectangle {
        visible: isFinite(root.last)
        width: 2 * root.endpointRadius
        height: width
        radius: root.endpointRadius
        x: root.width - root.endpointRadius
        y: root.height * (1 - root.last / root.effectiveMax) - root.endpointRadius
        color: root.endpointColor
    }
}
