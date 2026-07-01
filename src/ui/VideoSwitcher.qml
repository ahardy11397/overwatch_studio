import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Overwatch.Core

Window {
    id: root
    width: 1280
    height: 720
    title: "Video Switcher"
    color: "#0a0c10"

    WindowStateStore { id: winStore }

    Component.onCompleted: {
        var rect = winStore.restoreWindowGeometry("VideoSwitcher", Qt.rect(100, 600, 1280, 720));
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
        onTriggered: winStore.saveWindowGeometry("VideoSwitcher", Qt.rect(root.x, root.y, root.width, root.height), 0)
    }

    Text {
        anchors.centerIn: parent
        text: "Video Switcher Content (Refactored)"
        color: "white"
        font.pixelSize: 24
    }
}
