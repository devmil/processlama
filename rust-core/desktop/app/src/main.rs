use qtbridge::QApp;

const QML: &str = r#"
import QtQuick
Window { visible: true; width: 200; height: 100; Component.onCompleted: Qt.callLater(Qt.quit) }
"#;

fn main() {
    QApp::new().load_qml(QML.as_bytes()).run();
}
