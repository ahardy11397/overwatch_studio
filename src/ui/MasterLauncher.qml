import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Overwatch.Core

Window {
    id: root
    visible: true
    width: 360
    height: 520
    title: "Overwatch Launcher"
    color: "#0a0c10"

    // Engine bridges shared via main.cpp context are expected here
    // but if not, we can instantiate them here if they are singletons/globally accessible.
    // For now, assume they are registered types.

    WindowStateStore { id: winStore }

    Component.onCompleted: {
        var rect = winStore.restoreWindowGeometry("MasterLauncher", Qt.rect(100, 100, 360, 520));
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
        onTriggered: winStore.saveWindowGeometry("MasterLauncher", Qt.rect(root.x, root.y, root.width, root.height), 0)
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 20
        spacing: 16

        ColumnLayout {
            spacing: 2
            Layout.fillWidth: true
            Text {
                text: "OVERWATCH STUDIO"
                color: "#00d084"
                font.pixelSize: 18
                font.bold: true
                font.letterSpacing: 2
                Layout.alignment: Qt.AlignHCenter
            }
            Text {
                text: "MASTER LAUNCHER"
                color: "#8a8d98"
                font.pixelSize: 8
                font.letterSpacing: 1.5
                Layout.alignment: Qt.AlignHCenter
            }
        }

        Rectangle { Layout.fillWidth: true; height: 1; color: "#252b36" }

        Text {
            text: "SYSTEM MODULES"
            color: "#8a8d98"
            font.pixelSize: 9
            font.bold: true
            font.letterSpacing: 1
        }

        ColumnLayout {
            spacing: 10
            Layout.fillWidth: true

            ModuleToggle {
                title: "Audio Touch Console"
                subtitle: "24-Channel Fader Bay"
                icon: "🔊"
                activeColor: "#00d084"
                isOpen: false
                onToggled: audioCore.toggleWindow("Audio Touch Console")
            }

            ModuleToggle {
                title: "GPU Video Switcher"
                subtitle: "Widescreen 4-Cam Switch"
                icon: "📹"
                activeColor: "#00a0f0"
                isOpen: false
                onToggled: audioCore.toggleWindow("Video Switcher Console")
            }

            ModuleToggle {
                title: "Show Builder Sandbox"
                subtitle: "Diagnostics & WAL Files"
                icon: "🛠️"
                activeColor: "#f0b000"
                isOpen: false
                onToggled: audioCore.toggleWindow("Show Control Sandbox")
            }
        }

        Item { Layout.fillHeight: true }

        Button {
            id: panicButton
            Layout.fillWidth: true
            implicitHeight: 64
            background: Rectangle {
                color: audioCore.fadeToBlack ? "#ff3b30" : "#1a1012"
                border.color: "#ff3b30"
                border.width: 2
                radius: 8
            }
            contentItem: Text {
                text: audioCore.fadeToBlack ? "🚨 FTB ACTIVE 🚨" : "EMERGENCY PANIC (FTB)"
                color: "white"
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
                font.bold: true
            }
            onClicked: audioCore.fadeToBlack = !audioCore.fadeToBlack
        }
    }

    // Child component for toggles
    component ModuleToggle: Rectangle {
        property string title
        property string subtitle
        property string icon
        property color activeColor
        property bool isOpen
        signal toggled()

        Layout.fillWidth: true
        height: 54
        color: "#161920"
        border.color: isOpen ? activeColor : "#252b36"
        border.width: 1
        radius: 8

        RowLayout {
            anchors.fill: parent
            anchors.margins: 12
            spacing: 12
            Text { text: icon; font.pixelSize: 16 }
            ColumnLayout {
                spacing: 1
                Text { text: title; color: "#ffffff"; font.pixelSize: 12; font.bold: true }
                Text { text: subtitle; color: "#8a8d98"; font.pixelSize: 9 }
            }
            Item { Layout.fillWidth: true }
            Rectangle {
                width: 48; height: 24; radius: 12
                color: isOpen ? activeColor : "#101216"
                Rectangle {
                    width: 20; height: 20; radius: 10; color: "#ffffff"
                    x: isOpen ? 26 : 2; y: 2
                    Behavior on x { NumberAnimation { duration: 150 } }
                }
                MouseArea { anchors.fill: parent; onClicked: parent.parent.parent.toggled() }
            }
        }
    }
}
