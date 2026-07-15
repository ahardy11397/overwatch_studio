import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Overwatch.Core

Window {
    id: videoWin
    visible: true

    
    WindowStateStore { id: winStore }

    Component.onCompleted: {
        var rect = winStore.restoreWindowGeometry("VideoSwitcher", Qt.rect(100, 640, 1024, 576));
        videoWin.x = rect.x;
        videoWin.y = rect.y;
        videoWin.width = rect.width;
        videoWin.height = rect.height;
    }

    onXChanged: videoSaveTimer.restart()
    onYChanged: videoSaveTimer.restart()
    onWidthChanged: videoSaveTimer.restart()
    onHeightChanged: videoSaveTimer.restart()

    Timer {
        id: videoSaveTimer
        interval: 1000
        onTriggered: winStore.saveWindowGeometry("VideoSwitcher", Qt.rect(videoWin.x, videoWin.y, videoWin.width, videoWin.height), 0)
    }

    // Video state (previously from root scope)
    property int programCameraIdx: 0
    property int previewCameraIdx: 1
    property real transitionPercent: 0.0
    property bool crossfadeActive: false
    property bool fadeToBlack: false

    function logStateBeforeChange() {
        audioCore.captureUndoSnapshot(
            [0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0],
            [false,false,false,false,false,false,false,false,false,false,false,false,false,false,false,false,false,false,false,false,false,false,false,false],
            1.0,
            false,
            programCameraIdx,
            previewCameraIdx,
            audioCore.fadeToBlack
        );
    }

    function cutTransition() {
        var temp = programCameraIdx;
        programCameraIdx = previewCameraIdx;
        previewCameraIdx = temp;
        transitionPercent = 0.0;
    }

    function autoTransition() {
        autoTransAnimation.restart();
    }

    PropertyAnimation {
        id: autoTransAnimation
        target: videoWin
        property: "transitionPercent"
        from: 0.0
        to: 1.0
        duration: 300
        onFinished: {
            cutTransition();
        }
    }

    width: 1024

        height: 576

        title: "Video Switcher Console"

        color: "#0a0c10"

        x: 100

        y: 640



        ColumnLayout {

            anchors.fill: parent

            anchors.margins: 15

            spacing: 15

            RowLayout {

                Layout.fillWidth: true

                Layout.fillHeight: true

                spacing: 15

                // Left Pane (70%): High-FPS 2x2 camera grid

            Rectangle {

                Layout.fillWidth: true

                Layout.fillHeight: true

                Layout.preferredWidth: 7.0

                color: "#161920"

                border.color: "#252b36"

                border.width: 1

                radius: 10



                ColumnLayout {

                    anchors.fill: parent

                    anchors.margins: 15

                    spacing: 10



                    Text {

                        text: "GPU ACCELERATED GENLOCK MULTIVIEW (2x2)"

                        color: "#00a0f0"

                        font.pixelSize: 11

                        font.bold: true

                        font.letterSpacing: 1.5

                    }



                    VideoCanvasMock {

                        id: multiviewCanvas

                        Layout.fillWidth: true

                        Layout.fillHeight: true

                        programCamera: programCameraIdx

                        previewCamera: previewCameraIdx

                        mediaDeck: audioCore.mediaDeck

                    }

                }

            }



            // Right Pane (30%): Switcher Control Deck

            Rectangle {

                Layout.fillHeight: true

                width: 280

                color: "#161920"

                border.color: "#252b36"

                border.width: 1

                radius: 10



                ColumnLayout {

                    anchors.fill: parent

                    anchors.margins: 15

                    spacing: 12



                    Text {

                        text: "SWITCHER PANEL"

                        color: "#00a0f0"

                        font.pixelSize: 11

                        font.bold: true

                        font.letterSpacing: 1.2

                        Layout.alignment: Qt.AlignHCenter

                    }



                    Rectangle {

                        Layout.fillWidth: true

                        height: 1

                        color: "#252b36"

                    }



                    // Active Camera Status Deck

                    ColumnLayout {

                        spacing: 6

                        Layout.fillWidth: true



                        Rectangle {

                            Layout.fillWidth: true

                            height: 38

                            color: "#ff3b30"

                            radius: 6



                            Text {

                                anchors.centerIn: parent

                                text: "PROGRAM [PGM]: " + (programCameraIdx === 4 ? "MEDIA" : "CAM " + (programCameraIdx + 1))

                                color: "#ffffff"

                                font.pixelSize: 11

                                font.bold: true

                            }

                        }



                        Rectangle {

                            Layout.fillWidth: true

                            height: 38

                            color: "#30d158"

                            radius: 6



                            Text {

                                anchors.centerIn: parent

                                text: "PREVIEW [PVW]: " + (previewCameraIdx === 4 ? "MEDIA" : "CAM " + (previewCameraIdx + 1))

                                color: "#ffffff"

                                font.pixelSize: 11

                                font.bold: true

                            }

                        }

                    }



                    // PGM Source Selection Deck (Red border/glow)

                    ColumnLayout {

                        spacing: 4

                        Layout.fillWidth: true



                        Text {

                            text: "PROGRAM BUS (PGM)"

                            color: "#ff3b30"

                            font.pixelSize: 8

                            font.bold: true

                        }



                        RowLayout {

                            spacing: 6

                            Repeater {

                                model: 5

                                delegate: Button {

                                    id: pgmBtn

                                    Layout.fillWidth: true

                                    implicitHeight: 38

                                    checkable: true

                                    checked: programCameraIdx === index



                                    background: Rectangle {

                                        color: pgmBtn.checked ? "#ff3b30" : "#101216"

                                        border.color: "#252b36"

                                        radius: 6

                                    }



                                    contentItem: Text {

                                        text: index === 4 ? "MEDIA" : "CAM " + (index + 1)

                                        color: pgmBtn.checked ? "#ffffff" : "#8a8d98"

                                        font.pixelSize: 10

                                        font.bold: true

                                        horizontalAlignment: Text.AlignHCenter

                                        verticalAlignment: Text.AlignVCenter

                                    }



                                    onClicked: {

                                        programCameraIdx = index;

                                    }

                                }

                            }

                        }

                    }



                    // PVW Source Selection Deck (Green border/glow)

                    ColumnLayout {

                        spacing: 4

                        Layout.fillWidth: true



                        Text {

                            text: "PREVIEW BUS (PVW)"

                            color: "#30d158"

                            font.pixelSize: 8

                            font.bold: true

                        }



                        RowLayout {

                            spacing: 6

                            Repeater {

                                model: 5

                                delegate: Button {

                                    id: pvwBtn

                                    Layout.fillWidth: true

                                    implicitHeight: 38

                                    checkable: true

                                    checked: previewCameraIdx === index



                                    background: Rectangle {

                                        color: pvwBtn.checked ? "#30d158" : "#101216"

                                        border.color: "#252b36"

                                        radius: 6

                                    }



                                    contentItem: Text {

                                        text: index === 4 ? "MEDIA" : "CAM " + (index + 1)

                                        color: pvwBtn.checked ? "#ffffff" : "#8a8d98"

                                        font.pixelSize: 10

                                        font.bold: true

                                        horizontalAlignment: Text.AlignHCenter

                                        verticalAlignment: Text.AlignVCenter

                                    }



                                    onClicked: {

                                        previewCameraIdx = index;

                                    }

                                }

                            }

                        }

                    }



                    // CUT and AUTO Action block

                    RowLayout {

                        Layout.fillWidth: true

                        spacing: 10



                        Button {

                            id: cutButton

                            Layout.fillWidth: true

                            implicitHeight: 44

                            background: Rectangle {

                                color: "#1a1f29"

                                border.color: "#00a0f0"

                                border.width: 1

                                radius: 6

                            }

                            contentItem: Text {

                                text: "CUT"

                                color: "#00a0f0"

                                font.pixelSize: 11

                                font.bold: true

                                horizontalAlignment: Text.AlignHCenter

                                verticalAlignment: Text.AlignVCenter

                            }

                            onClicked: {

                                logStateBeforeChange();

                                cutTransition();

                            }

                        }



                        Button {

                            id: autoButton

                            Layout.fillWidth: true

                            implicitHeight: 44

                            background: Rectangle {

                                color: "#1a1f29"

                                border.color: "#00d084"

                                border.width: 1

                                radius: 6

                            }

                            contentItem: Text {

                                text: "AUTO"

                                color: "#00d084"

                                font.pixelSize: 11

                                font.bold: true

                                horizontalAlignment: Text.AlignHCenter

                                verticalAlignment: Text.AlignVCenter

                            }

                            onClicked: {

                                logStateBeforeChange();

                                autoTransition();

                            }

                        }

                    }



                    Item { Layout.fillHeight: true }



                    // T-Bar Fader Slot & Handle (Smooth 0-100% Transition)

                    ColumnLayout {

                        Layout.fillWidth: true

                        Layout.alignment: Qt.AlignHCenter

                        spacing: 4



                        Text {

                            text: "MANUAL T-BAR: " + Math.round(transitionPercent * 100) + "%"

                            color: "#8a8d98"

                            font.pixelSize: 9

                            font.bold: true

                            Layout.alignment: Qt.AlignHCenter

                        }



                        Item {

                            width: 80

                            height: 140

                            Layout.alignment: Qt.AlignHCenter



                            // Vertical Slider Slot

                            Rectangle {

                                width: 8

                                height: parent.height - 24

                                color: "#0d0f12"

                                radius: 4

                                anchors.horizontalCenter: parent.horizontalCenter

                                anchors.verticalCenter: parent.verticalCenter



                                Rectangle {

                                    width: parent.width

                                    height: transitionPercent * parent.height

                                    color: "#00a0f0"

                                    radius: 4

                                    anchors.bottom: parent.bottom

                                }

                            }



                            // T-bar handle cap

                            Rectangle {

                                id: tbarHandle

                                width: 56

                                height: 18

                                color: "#252b36"

                                border.color: "#ffffff"

                                border.width: 1.5

                                radius: 3

                                anchors.horizontalCenter: parent.horizontalCenter

                                y: (parent.height - height - 24) * (1.0 - transitionPercent) + 12



                                Rectangle {

                                    width: 4

                                    height: 10

                                    color: "#a0a5b0"

                                    anchors.centerIn: parent

                                }

                            }



                            // Touch Safe Drag Target (80px width)

                            MouseArea {

                                anchors.fill: parent

                                preventStealing: true



                                function dragTBar(mouseY) {

                                    var margin = 12;

                                    var range = parent.height - 24;

                                    var clampedY = Math.max(margin, Math.min(mouseY, parent.height - margin));

                                    var val = 1.0 - (clampedY - margin) / range;

                                    

                                    transitionPercent = val;



                                    // Automatic complete switch on full sweep

                                    if (val >= 0.98) {

                                        cutTransition();

                                    }

                                }



                                onPressed: (mouse) => {

                                    logStateBeforeChange();

                                    dragTBar(mouse.y);

                                }

                                onPositionChanged: (mouse) => dragTBar(mouse.y)

                            }

                        }

                    }

                }

            }

        }

        // --- LOCAL MEDIA DECK CONTROL PANEL ---
        Rectangle {
            id: mediaDeckPanel
            Layout.fillWidth: true
            height: 90
            color: "#161920"
            border.color: "#252b36"
            border.width: 1
            radius: 8
            
            RowLayout {
                anchors.fill: parent
                anchors.margins: 12
                spacing: 15
                
                // Playback Status Indicator
                ColumnLayout {
                    spacing: 2
                    Text {
                        text: "LOCAL MEDIA DECK"
                        color: "#00bdd6"
                        font.pixelSize: 10
                        font.bold: true
                        font.letterSpacing: 1.0
                    }
                    Text {
                        text: audioCore.mediaDeck.playing ? "STATE: PLAYING" : "STATE: PAUSED"
                        color: audioCore.mediaDeck.playing ? "#30d158" : "#8a8d98"
                        font.pixelSize: 9
                        font.bold: true
                    }
                }
                
                // Load / File selection
                ColumnLayout {
                    Layout.preferredWidth: 200
                    spacing: 4
                    Text {
                        text: audioCore.mediaDeck.filePath === "" ? "No file loaded" : audioCore.mediaDeck.filePath
                        color: "#ffffff"
                        font.pixelSize: 10
                        elide: Text.ElideMiddle
                    }
                    RowLayout {
                        spacing: 6
                        Button {
                            implicitHeight: 24
                            text: "Load Clip"
                            onClicked: {
                                audioCore.mediaDeck.load("clip_show_intro_1080p.mp4");
                            }
                        }
                        Button {
                            implicitHeight: 24
                            text: "Load Audio"
                            onClicked: {
                                audioCore.mediaDeck.load("bg_music_track.wav");
                            }
                        }
                    }
                }
                
                // Playback Controls
                RowLayout {
                    spacing: 8
                    Button {
                        text: "▶"
                        implicitWidth: 32
                        implicitHeight: 32
                        onClicked: audioCore.mediaDeck.play()
                    }
                    Button {
                        text: "▮▮"
                        implicitWidth: 32
                        implicitHeight: 32
                        onClicked: audioCore.mediaDeck.pause()
                    }
                    Button {
                        text: "■"
                        implicitWidth: 32
                        implicitHeight: 32
                        onClicked: audioCore.mediaDeck.stop()
                    }
                }
                
                // Progress Slider & Timecode
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 2
                    RowLayout {
                        Text {
                            function formatTC(secs) {
                                var m = Math.floor(secs / 60);
                                var s = secs % 60;
                                return (m < 10 ? "0" + m : m) + ":" + (s < 10 ? "0" + s : s);
                            }
                            text: formatTC(audioCore.mediaDeck.position) + " / " + formatTC(audioCore.mediaDeck.duration)
                            color: "#a1a1aa"
                            font.pixelSize: 9
                            font.bold: true
                        }
                        Item { Layout.fillWidth: true }
                        CheckBox {
                            text: "Loop"
                            checked: audioCore.mediaDeck.loop
                            onCheckedChanged: audioCore.mediaDeck.loop = checked
                        }
                    }
                    Slider {
                        Layout.fillWidth: true
                        from: 0
                        to: audioCore.mediaDeck.duration
                        value: audioCore.mediaDeck.position
                        onMoved: audioCore.mediaDeck.position = value
                    }
                }
            }
        }

    }

}
