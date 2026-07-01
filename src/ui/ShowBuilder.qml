import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Overwatch.Core

Window {
    id: root
    width: 1000
    height: 800
    title: "Show Builder"
    color: "#0a0c10"

    WindowStateStore { id: winStore }

    Component.onCompleted: {
        var rect = winStore.restoreWindowGeometry("ShowBuilder", Qt.rect(1200, 100, 1000, 800));
        root.x = rect.x;
        root.y = rect.y;
        root.width = rect.width;
        root.height = rect.height;
    }

    onXChanged: saveTimer.restart()
    onYChanged: saveTimer.restart()
    onWidthChanged: saveTimer.restart()
    onHeightChanged: saveTimer.restart()

    Timer {
        id: saveTimer
        interval: 1000
        onTriggered: winStore.saveWindowGeometry("ShowBuilder", Qt.rect(root.x, root.y, root.width, root.height), 0)
    }

    Text {
        anchors.centerIn: parent
        text: "Show Builder Content (Refactored)"
        color: "white"
        font.pixelSize: 24
    }
}
