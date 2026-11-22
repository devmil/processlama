pragma ComponentBehavior: Bound
import QtQuick
import Meridian

// A process's own icon, or its initial on a categorical colour when it has
// none or the file fails to load. No fade: table cells are recycled.
Item {
    id: root

    property string name
    property string iconUrl
    property int avatarSize: MeridianAvatar.Small
    readonly property real dimension: [Metrics.avatarSmall, Metrics.avatarMedium, Metrics.avatarLarge,
        Metrics.avatarXLarge][avatarSize]

    implicitWidth: dimension
    implicitHeight: dimension

    Image {
        id: picture
        anchors.fill: parent
        visible: root.iconUrl.length > 0 && status === Image.Ready
        source: root.iconUrl
        fillMode: Image.PreserveAspectFit
        smooth: true
        mipmap: true
        readonly property real decoded: Math.min(96, Math.max(16, Math.ceil(root.dimension * Screen.devicePixelRatio)))
        sourceSize: Qt.size(decoded, decoded)
    }

    Loader {
        anchors.fill: parent
        active: !picture.visible
        sourceComponent: MeridianAvatar {
            name: root.name.length > 0 ? root.name : "?"
            avatarSize: root.avatarSize
        }
    }
}
