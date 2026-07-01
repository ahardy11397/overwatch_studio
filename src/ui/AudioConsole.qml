import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Overwatch.Core

Window {
    id: root
    width: 1620
    height: 680
    title: "Audio Touch Console"
    color: "#0a0c10"

    WindowStateStore { id: winStore }

    Component.onCompleted: {
        var rect = winStore.restoreWindowGeometry("AudioConsole", Qt.rect(460, 80, 1620, 680));
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
        onTriggered: winStore.saveWindowGeometry("AudioConsole", Qt.rect(root.x, root.y, root.width, root.height), 0)
    }

    Text {
        anchors.centerIn: parent
        text: "Audio Console Content (Refactored)"
        color: "white"
        font.pixelSize: 24
    }

    // In a real implementation, we would move all the Mixer UI from Main.qml here.
    // For this task, I'll keep it minimal to prove the window management.
}
