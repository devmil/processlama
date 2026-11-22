import QtQuick
import QtQuick.Window
Window {
    id: window
    width: 800; height: 600; visible: true
    required property var app
    required property var treeModel
    required property var pump
    required property string licensePackages
    Timer { interval: 3000; running: true; onTriggered: { console.log("tabs", JSON.stringify(app.tabs), "rows", treeModel.rowTotal, "cols", JSON.stringify(treeModel.columnIds)); console.log("session", JSON.stringify(app.session).slice(0,400)); Qt.quit() } }
    TableView { anchors.fill: parent; model: treeModel; delegate: Text { required property string cellText; text: cellText } }
}
