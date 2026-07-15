import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Overwatch.Core

Window {
    id: sandboxWin
    visible: true

    component PremiumSlider: Slider {
        id: control
        property color accentColor: "#00d084"

        background: Rectangle {
            x: control.leftPadding
            y: control.topPadding + control.availableHeight / 2 - height / 2
            implicitWidth: 120
            implicitHeight: 4
            width: control.availableWidth
            height: implicitHeight
            radius: 2
            color: "#080a0d"

            Rectangle {
                width: control.visualPosition * parent.width
                height: parent.height
                color: control.enabled ? control.accentColor : "#4a4d55"
                radius: 2
            }
        }

        handle: Rectangle {
            x: control.leftPadding + control.visualPosition * (control.availableWidth - width)
            y: control.topPadding + control.availableHeight / 2 - height / 2
            implicitWidth: 12
            implicitHeight: 12
            radius: 6
            color: control.pressed ? "#3b4252" : "#252b36"
            border.color: control.hovered ? control.accentColor : "#8a8d98"
            border.width: control.pressed ? 2.0 : 1.5

            Rectangle {
                width: 4
                height: 4
                radius: 2
                color: control.accentColor
                anchors.centerIn: parent
                visible: control.hovered || control.pressed
            }
        }
    }

    function getBandMinFreq(band) {
        if (band === 0) return 20.0;
        if (band === 1) return 100.0;
        if (band === 2) return 500.0;
        return 2000.0;
    }

    function getBandMaxFreq(band) {
        if (band === 0) return 500.0;
        if (band === 1) return 2000.0;
        if (band === 2) return 10000.0;
        return 20000.0;
    }

    function getEQFreq(band, ch) {
        if (band === 0) return audioCore.channelEQBand0Freqs[ch];
        if (band === 1) return audioCore.channelEQBand1Freqs[ch];
        if (band === 2) return audioCore.channelEQBand2Freqs[ch];
        return audioCore.channelEQBand3Freqs[ch];
    }

    function getEQQ(band, ch) {
        if (band === 0) return audioCore.channelEQBand0Qs[ch];
        if (band === 1) return audioCore.channelEQBand1Qs[ch];
        if (band === 2) return audioCore.channelEQBand2Qs[ch];
        return audioCore.channelEQBand3Qs[ch];
    }

    function getEQFreqSliderVal(band, ch) {
        var f = getEQFreq(band, ch);
        var min = getBandMinFreq(band);
        var max = getBandMaxFreq(band);
        return Math.log(f / min) / Math.log(max / min);
    }

    
    WindowStateStore { id: winStore }

    Component.onCompleted: {
        var rect = winStore.restoreWindowGeometry("ShowBuilder", Qt.rect(1140, 640, 960, 480));
        sandboxWin.x = rect.x;
        sandboxWin.y = rect.y;
        sandboxWin.width = rect.width;
        sandboxWin.height = rect.height;
    }

    onXChanged: sandboxSaveTimer.restart()
    onYChanged: sandboxSaveTimer.restart()
    onWidthChanged: sandboxSaveTimer.restart()
    onHeightChanged: sandboxSaveTimer.restart()

    Timer {
        id: sandboxSaveTimer
        interval: 1000
        onTriggered: winStore.saveWindowGeometry("ShowBuilder", Qt.rect(sandboxWin.x, sandboxWin.y, sandboxWin.width, sandboxWin.height), 0)
    }

    // Shared state (moved from root)
    property variant channelVolumes: [
        1.0, 1.0, 1.0, 1.0,   1.0, 1.0, 1.0, 1.0,
        1.0, 1.0, 1.0, 1.0,   1.0, 1.0, 1.0, 1.0,
        1.0, 1.0, 1.0, 1.0,   1.0, 1.0, 1.0, 1.0
    ]
    property variant channelMutes: [
        false, false, false, false,   false, false, false, false,
        false, false, false, false,   false, false, false, false,
        false, false, false, false,   false, false, false, false
    ]
    property double masterVolume: 1.0
    property bool masterMute: false
    property int uiInputsCount: 8
    property int uiBusesCount: 2
    property int uiAuxesCount: 0
    property int uiDCAsCount: 8

    // Route helpers (moved from root scope)
    function checkRouteActive(src, dest) {
        var patches = audioCore.getActivePatches();
        for (var i = 0; i < patches.length; ++i) {
            var p = patches[i];
            if (p.routeSrc === src && p.routeDest === dest) return true;
        }
        return false;
    }
    function getRouteTap(src, dest) {
        var patches = audioCore.getActivePatches();
        for (var i = 0; i < patches.length; ++i) {
            var p = patches[i];
            if (p.routeSrc === src && p.routeDest === dest) return p.routeTap;
        }
        return 0;
    }
    function toggleRoute(src, dest) {
        if (checkRouteActive(src, dest)) {
            audioCore.unpatchRoute(src, dest);
        } else {
            audioCore.patchRoute(src, dest, 1.0, 0);
        }
    }
    function openRouteEditor(src, dest) {
        // Route editor popup is in Main.qml — no-op in ShowBuilder
    }
    width: 960

        height: 480

        title: "Show Control Sandbox"

        color: "#0a0c10"

        x: 1140

        y: 640



        ColumnLayout {

            anchors.fill: parent

            anchors.margins: 20

            spacing: 15



            Text {

                text: "SYSTEM DIAGNOSTICS SANDBOX"

                color: "#f0b000"

                font.pixelSize: 14

                font.bold: true

                font.letterSpacing: 2

            }



            Rectangle {

                Layout.fillWidth: true

                height: 1

                color: "#252b36"

            }



            RowLayout {

                Layout.fillWidth: true

                Layout.fillHeight: true

                spacing: 15



                // Left Panel: SDS database archive & State History Console

                Rectangle {

                    Layout.fillWidth: true

                    Layout.fillHeight: true

                    color: "#161920"

                    border.color: "#252b36"

                    border.width: 1

                    radius: 8



                    ColumnLayout {

                        anchors.fill: parent

                        anchors.margins: 15

                        spacing: 12



                        Text {

                            text: "SDS CONTAINER ARCHIVE"

                            color: "#8a8d98"

                            font.pixelSize: 9

                            font.bold: true

                        }



                        RowLayout {

                            spacing: 8

                            Layout.fillWidth: true

                            Button {

                                text: "Load .sds"

                                Layout.fillWidth: true

                                implicitHeight: 32

                                onClicked: {

                                    showBuilder.loadShowArchive("test_show.sds")
                                    sandboxWin.uiInputsCount = 16
                                    sandboxWin.uiBusesCount = 4
                                    sandboxWin.uiAuxesCount = 4
                                    sandboxWin.uiDCAsCount = 4
                                    audioCore.configureShowChannels(16, 4, 4, 4)

                                }

                            }

                            Button {

                                text: "Save Delta"

                                Layout.fillWidth: true

                                implicitHeight: 32

                                onClicked: {

                                    showBuilder.saveDelta()

                                }

                            }

                        }



                        Rectangle {

                            Layout.fillWidth: true

                            height: 1

                            color: "#252b36"

                        }



                        // State History Delta Recovery Section

                        ColumnLayout {

                            spacing: 8

                            Layout.fillWidth: true

                            Text {

                                text: "STATE HISTORY UNDO (" + audioCore.historySize + " / 10 BACKUPS)"

                                color: "#00d084"

                                font.pixelSize: 8

                                font.bold: true

                            }

                            

                            RowLayout {

                                spacing: 4

                                Layout.fillWidth: true

                                Repeater {

                                    model: 10

                                    delegate: Rectangle {

                                        Layout.fillWidth: true

                                        height: 6

                                        radius: 3

                                        color: index < audioCore.historySize ? (audioCore.undoActive ? "#f0b000" : "#00d084") : "#252b36"

                                    }

                                }

                            }

                            

                            RowLayout {

                                spacing: 4

                                Layout.fillWidth: true

                                Button {

                                    text: "Instant"

                                    Layout.fillWidth: true

                                    implicitHeight: 32

                                    enabled: audioCore.historySize > 0 && !audioCore.undoActive

                                    onClicked: audioCore.triggerUndo(0, channelVolumes, masterVolume)

                                }

                                Button {

                                    text: "Match"

                                    Layout.fillWidth: true

                                    implicitHeight: 32

                                    enabled: audioCore.historySize > 0 && !audioCore.undoActive

                                    onClicked: audioCore.triggerUndo(1, channelVolumes, masterVolume)

                                }

                                Button {

                                    text: "Escape"

                                    Layout.fillWidth: true

                                    implicitHeight: 32

                                    enabled: audioCore.historySize > 0 && !audioCore.undoActive

                                    onClicked: audioCore.triggerUndo(2, channelVolumes, masterVolume)

                                }

                            }

                        }



                        Rectangle {
                            Layout.fillWidth: true
                            height: 1
                            color: "#252b36"
                        }

                        // DAW MULTITRACK RECORDING
                        ColumnLayout {
                            spacing: 8
                            Layout.fillWidth: true

                            Text {
                                text: "DAW MULTITRACK RECORDING"
                                color: "#ff4d4d"
                                font.pixelSize: 8
                                font.bold: true
                            }

                            RowLayout {
                                spacing: 8
                                Layout.fillWidth: true

                                Button {
                                    id: recordArmBtn
                                    text: audioCore.recordArmed ? "🔴 ARMED" : "⚪ ARM REC"
                                    Layout.fillWidth: true
                                    implicitHeight: 32
                                    checkable: true
                                    checked: audioCore.recordArmed
                                    
                                    background: Rectangle {
                                        color: recordArmBtn.checked ? "#4d0000" : "#1a1f29"
                                        border.color: recordArmBtn.checked ? "#ff4d4d" : "#252b36"
                                        border.width: 1.5
                                        radius: 6
                                    }
                                    contentItem: Text {
                                        text: recordArmBtn.text
                                        color: recordArmBtn.checked ? "#ff4d4d" : "#8a8d98"
                                        font.pixelSize: 9
                                        font.bold: true
                                        horizontalAlignment: Text.AlignHCenter
                                        verticalAlignment: Text.AlignVCenter
                                    }
                                    onClicked: {
                                        audioCore.armRecording(!audioCore.recordArmed);
                                    }
                                }

                                Button {
                                    id: recordTriggerBtn
                                    text: audioCore.recordingActive ? "⏹ STOP" : "⏺ RECORD"
                                    Layout.fillWidth: true
                                    implicitHeight: 32
                                    checkable: true
                                    checked: audioCore.recordingActive
                                    enabled: audioCore.recordArmed
                                    
                                    background: Rectangle {
                                        color: recordTriggerBtn.checked ? "#ff4d4d" : (recordTriggerBtn.enabled ? "#1a1f29" : "#0d1015")
                                        border.color: recordTriggerBtn.checked ? "#ff4d4d" : "#252b36"
                                        border.width: 1.5
                                        radius: 6
                                    }
                                    contentItem: Text {
                                        text: recordTriggerBtn.text
                                        color: recordTriggerBtn.checked ? "#0a0c10" : (recordTriggerBtn.enabled ? "#ff4d4d" : "#404040")
                                        font.pixelSize: 9
                                        font.bold: true
                                        horizontalAlignment: Text.AlignHCenter
                                        verticalAlignment: Text.AlignVCenter
                                    }
                                    onClicked: {
                                        audioCore.triggerRecording(!audioCore.recordingActive);
                                    }
                                }
                            }
                        }

                        Rectangle {
                            Layout.fillWidth: true
                            height: 1
                            color: "#252b36"
                        }

                        // DYNAMIC SHOW ENGINE SCALING
                        ColumnLayout {
                            spacing: 8
                            Layout.fillWidth: true

                            Text {
                                text: "DYNAMIC ENGINE SCALING"
                                color: "#00d084"
                                font.pixelSize: 8
                                font.bold: true
                            }

                            RowLayout {
                                spacing: 10
                                Layout.fillWidth: true

                                ColumnLayout {
                                    spacing: 4
                                    Text { text: "INPUTS"; color: "#6e727d"; font.pixelSize: 8; font.bold: true }
                                    RowLayout {
                                        spacing: 4
                                        Button {
                                            id: decInputs
                                            text: "-"
                                            implicitWidth: 20
                                            implicitHeight: 20
                                            background: Rectangle { color: "#1a1f29"; radius: 4; border.color: "#252b36" }
                                            contentItem: Text { text: "-"; color: "#8a8d98"; font.pixelSize: 10; font.bold: true; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter }
                                            onClicked: if (sandboxWin.uiInputsCount > 1) sandboxWin.uiInputsCount--
                                        }
                                        Text {
                                            text: sandboxWin.uiInputsCount
                                            color: "#ffffff"
                                            font.pixelSize: 10
                                            font.bold: true
                                            Layout.preferredWidth: 18
                                            horizontalAlignment: Text.AlignHCenter
                                        }
                                        Button {
                                            id: incInputs
                                            text: "+"
                                            implicitWidth: 20
                                            implicitHeight: 20
                                            background: Rectangle { color: "#1a1f29"; radius: 4; border.color: "#252b36" }
                                            contentItem: Text { text: "+"; color: "#8a8d98"; font.pixelSize: 10; font.bold: true; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter }
                                            onClicked: if (sandboxWin.uiInputsCount < 24) sandboxWin.uiInputsCount++
                                        }
                                    }
                                }

                                ColumnLayout {
                                    spacing: 4
                                    Text { text: "BUSES"; color: "#6e727d"; font.pixelSize: 8; font.bold: true }
                                    RowLayout {
                                        spacing: 4
                                        Button {
                                            id: decBuses
                                            text: "-"
                                            implicitWidth: 20
                                            implicitHeight: 20
                                            background: Rectangle { color: "#1a1f29"; radius: 4; border.color: "#252b36" }
                                            contentItem: Text { text: "-"; color: "#8a8d98"; font.pixelSize: 10; font.bold: true; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter }
                                            onClicked: if (sandboxWin.uiBusesCount > 0) sandboxWin.uiBusesCount--
                                        }
                                        Text {
                                            text: sandboxWin.uiBusesCount
                                            color: "#ffffff"
                                            font.pixelSize: 10
                                            font.bold: true
                                            Layout.preferredWidth: 18
                                            horizontalAlignment: Text.AlignHCenter
                                        }
                                        Button {
                                            id: incBuses
                                            text: "+"
                                            implicitWidth: 20
                                            implicitHeight: 20
                                            background: Rectangle { color: "#1a1f29"; radius: 4; border.color: "#252b36" }
                                            contentItem: Text { text: "+"; color: "#8a8d98"; font.pixelSize: 10; font.bold: true; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter }
                                            onClicked: if (sandboxWin.uiBusesCount < 8) sandboxWin.uiBusesCount++
                                        }
                                    }
                                }

                                ColumnLayout {
                                    spacing: 4
                                    Text { text: "AUXES"; color: "#6e727d"; font.pixelSize: 8; font.bold: true }
                                    RowLayout {
                                        spacing: 4
                                        Button {
                                            id: decAuxes
                                            text: "-"
                                            implicitWidth: 20
                                            implicitHeight: 20
                                            background: Rectangle { color: "#1a1f29"; radius: 4; border.color: "#252b36" }
                                            contentItem: Text { text: "-"; color: "#8a8d98"; font.pixelSize: 10; font.bold: true; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter }
                                            onClicked: if (sandboxWin.uiAuxesCount > 0) sandboxWin.uiAuxesCount--
                                        }
                                        Text {
                                            text: sandboxWin.uiAuxesCount
                                            color: "#ffffff"
                                            font.pixelSize: 10
                                            font.bold: true
                                            Layout.preferredWidth: 18
                                            horizontalAlignment: Text.AlignHCenter
                                        }
                                        Button {
                                            id: incAuxes
                                            text: "+"
                                            implicitWidth: 20
                                            implicitHeight: 20
                                            background: Rectangle { color: "#1a1f29"; radius: 4; border.color: "#252b36" }
                                            contentItem: Text { text: "+"; color: "#8a8d98"; font.pixelSize: 10; font.bold: true; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter }
                                            onClicked: if (sandboxWin.uiAuxesCount < 8) sandboxWin.uiAuxesCount++
                                        }
                                    }
                                }

                                ColumnLayout {
                                    spacing: 4
                                    Text { text: "DCAS"; color: "#6e727d"; font.pixelSize: 8; font.bold: true }
                                    RowLayout {
                                        spacing: 4
                                        Button {
                                            id: decDCAs
                                            text: "-"
                                            implicitWidth: 20
                                            implicitHeight: 20
                                            background: Rectangle { color: "#1a1f29"; radius: 4; border.color: "#252b36" }
                                            contentItem: Text { text: "-"; color: "#8a8d98"; font.pixelSize: 10; font.bold: true; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter }
                                            onClicked: if (sandboxWin.uiDCAsCount > 0) sandboxWin.uiDCAsCount--
                                        }
                                        Text {
                                            text: sandboxWin.uiDCAsCount
                                            color: "#ffffff"
                                            font.pixelSize: 10
                                            font.bold: true
                                            Layout.preferredWidth: 18
                                            horizontalAlignment: Text.AlignHCenter
                                        }
                                        Button {
                                            id: incDCAs
                                            text: "+"
                                            implicitWidth: 20
                                            implicitHeight: 20
                                            background: Rectangle { color: "#1a1f29"; radius: 4; border.color: "#252b36" }
                                            contentItem: Text { text: "+"; color: "#8a8d98"; font.pixelSize: 10; font.bold: true; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter }
                                            onClicked: if (sandboxWin.uiDCAsCount < 8) sandboxWin.uiDCAsCount++
                                        }
                                    }
                                }
                            }

                            Button {
                                id: applyScalingBtn
                                text: "RECONFIGURE SHOW ENGINE"
                                Layout.fillWidth: true
                                implicitHeight: 28
                                
                                background: Rectangle {
                                    color: "#1a1f29"
                                    border.color: "#00d084"
                                    border.width: 1
                                    radius: 6
                                }
                                contentItem: Text {
                                    text: applyScalingBtn.text
                                    color: "#00d084"
                                    font.pixelSize: 8
                                    font.bold: true
                                    horizontalAlignment: Text.AlignHCenter
                                    verticalAlignment: Text.AlignVCenter
                                }
                                onClicked: {
                                    audioCore.configureShowChannels(sandboxWin.uiInputsCount, sandboxWin.uiBusesCount, sandboxWin.uiAuxesCount, sandboxWin.uiDCAsCount);
                                }
                            }
                        }

                        Item { Layout.fillHeight: true }



                        Text {

                            text: "Interactive undo states and high-efficiency ZIP delta-saving checkpoints."

                            color: "#6e727d"

                            font.pixelSize: 8

                            Layout.fillWidth: true

                            wrapMode: Text.Wrap

                        }

                    }

                }



                // Middle Panel: Universal Control Surface Console

                Rectangle {

                    Layout.fillWidth: true

                    Layout.fillHeight: true

                    color: "#161920"

                    border.color: "#252b36"

                    border.width: 1

                    radius: 8



                    ColumnLayout {

                        anchors.fill: parent

                        anchors.margins: 15

                        spacing: 12



                        Text {

                            text: "CONTROL SURFACE ENGINE"

                            color: "#8a8d98"

                            font.pixelSize: 9

                            font.bold: true

                        }



                        // Telemetry Stats

                        RowLayout {

                            spacing: 6

                            Layout.fillWidth: true

                            

                            Rectangle {

                                Layout.fillWidth: true

                                height: 32

                                color: "#11261d"

                                radius: 4

                                border.color: "#00d084"

                                Text {

                                    anchors.centerIn: parent

                                    text: "OSC UDP: 8000"

                                    color: "#00d084"

                                    font.pixelSize: 8

                                    font.bold: true

                                }

                            }

                            

                            Rectangle {

                                Layout.fillWidth: true

                                height: 32

                                color: "#11261d"

                                radius: 4

                                border.color: "#00d084"

                                Text {

                                    anchors.centerIn: parent

                                    text: "MIDI MCU: ON"

                                    color: "#00d084"

                                    font.pixelSize: 8

                                    font.bold: true

                                }

                            }



                            Rectangle {

                                Layout.fillWidth: true

                                height: 32

                                color: "#11261d"

                                radius: 4

                                border.color: "#00d084"

                                Text {

                                    anchors.centerIn: parent

                                    text: "SD CLIENTS: " + audioCore.streamDeckClients

                                    color: "#00d084"

                                    font.pixelSize: 8

                                    font.bold: true

                                }

                            }

                        }



                        Rectangle {

                            Layout.fillWidth: true

                            height: 1

                            color: "#252b36"

                        }



                        // Hardware Command Simulators

                        ColumnLayout {

                            spacing: 4

                            Layout.fillWidth: true

                            Text {

                                text: "SIMULATE HARDWARE INPUTS"

                                color: "#00d084"

                                font.pixelSize: 8

                                font.bold: true

                            }

                            

                            RowLayout {

                                spacing: 4

                                Layout.fillWidth: true

                                Button {

                                    text: "OSC Ch 9 (75%)"

                                    Layout.fillWidth: true

                                    implicitHeight: 28

                                    onClicked: audioCore.simulateOSCFader(8, 0.75)

                                }

                                Button {

                                    text: "OSC Master (100%)"

                                    Layout.fillWidth: true

                                    implicitHeight: 28

                                    onClicked: audioCore.simulateOSCFader(24, 1.0)

                                }

                            }

                            

                            RowLayout {

                                spacing: 4

                                Layout.fillWidth: true

                                Button {

                                    text: "MIDI Ch 1 (50%)"

                                    Layout.fillWidth: true

                                    implicitHeight: 28

                                    onClicked: audioCore.simulateMIDIFader(0, 0.5)

                                }

                                Button {

                                    text: "Stream Deck GO"

                                    Layout.fillWidth: true

                                    implicitHeight: 28

                                    onClicked: audioCore.simulateStreamDeckCue(1)

                                }

                            }



                            RowLayout {

                                spacing: 4

                                Layout.fillWidth: true

                                Button {

                                    text: "Add Stream Deck"

                                    Layout.fillWidth: true

                                    implicitHeight: 28

                                    onClicked: audioCore.adjustStreamDeckClients(1)

                                }

                                Button {

                                    text: "Remove Stream Deck"

                                    Layout.fillWidth: true

                                    implicitHeight: 28

                                    onClicked: audioCore.adjustStreamDeckClients(-1)

                                }

                            }

                        }



                        Rectangle {

                            Layout.fillWidth: true

                            height: 1

                            color: "#252b36"

                        }



                        // Motor-Fader feedback log terminal

                        ColumnLayout {

                            spacing: 4

                            Layout.fillWidth: true

                            Text {

                                text: "MOTOR-FADER SYNC FEEDBACK"

                                color: "#8a8d98"

                                font.pixelSize: 8

                                font.bold: true

                            }

                            

                            Rectangle {

                                Layout.fillWidth: true

                                height: 50

                                color: "#0a0c10"

                                border.color: "#252b36"

                                border.width: 1

                                radius: 6

                                

                                Text {

                                    anchors.fill: parent

                                    anchors.margins: 6

                                    text: audioCore.lastControlSurfaceMsg

                                    color: "#00d084"

                                    font.family: "Courier New"

                                    font.pixelSize: 8

                                    font.bold: true

                                    wrapMode: Text.Wrap

                                    verticalAlignment: Text.AlignVCenter

                                }

                            }

                        }



                        Item { Layout.fillHeight: true }

                    }

                }



                // Right Panel: Hardware failover & Watchdog simulation / DCA & Mute integration

                Rectangle {

                    id: rightPanel

                    Layout.fillWidth: true

                    Layout.fillHeight: true

                    color: "#161920"

                    border.color: "#252b36"

                    border.width: 1

                    radius: 8



                    property int activeTab: 0

                    property int selectedChannel: 0



                    ColumnLayout {

                        anchors.fill: parent

                        anchors.margins: 15

                        spacing: 12



                        // Tab Selector Row

                        RowLayout {

                            Layout.fillWidth: true

                            spacing: 6

                            height: 36



                            Button {

                                id: tab0Btn

                                text: "Diagnostics"

                                Layout.fillWidth: true

                                implicitHeight: 32

                                checkable: true

                                checked: rightPanel.activeTab === 0

                                background: Rectangle {

                                    color: tab0Btn.checked ? "#2600d084" : "#08ffffff"

                                    border.color: tab0Btn.checked ? "#00d084" : "#252b36"

                                    border.width: 1

                                    radius: 6

                                }

                                contentItem: Text {

                                    text: tab0Btn.text

                                    color: tab0Btn.checked ? "#00d084" : "#8a8d98"

                                    font.pixelSize: 10

                                    font.bold: true

                                    horizontalAlignment: Text.AlignHCenter

                                    verticalAlignment: Text.AlignVCenter

                                }

                                onClicked: rightPanel.activeTab = 0

                            }



                            Button {

                                id: tab1Btn

                                text: "DCA & Mutes"

                                Layout.fillWidth: true

                                implicitHeight: 32

                                checkable: true

                                checked: rightPanel.activeTab === 1

                                background: Rectangle {

                                    color: tab1Btn.checked ? "#26f0b000" : "#08ffffff"

                                    border.color: tab1Btn.checked ? "#f0b000" : "#252b36"

                                    border.width: 1

                                    radius: 6

                                }

                                contentItem: Text {

                                    text: tab1Btn.text

                                    color: tab1Btn.checked ? "#f0b000" : "#8a8d98"

                                    font.pixelSize: 10

                                    font.bold: true

                                    horizontalAlignment: Text.AlignHCenter

                                    verticalAlignment: Text.AlignVCenter

                                }

                                onClicked: rightPanel.activeTab = 1

                            }



                            Button {
                                id: tab3Btn
                                text: "Patch Board"
                                Layout.fillWidth: true
                                implicitHeight: 32
                                checkable: true
                                checked: rightPanel.activeTab === 3
                                background: Rectangle {
                                    color: tab3Btn.checked ? "#2600BDD6" : "#08ffffff"
                                    border.color: tab3Btn.checked ? "#00BDD6" : "#252b36"
                                    border.width: 1
                                    radius: 6
                                }
                                contentItem: Text {
                                    text: tab3Btn.text
                                    color: tab3Btn.checked ? "#00BDD6" : "#8a8d98"
                                    font.pixelSize: 10
                                    font.bold: true
                                    horizontalAlignment: Text.AlignHCenter
                                    verticalAlignment: Text.AlignVCenter
                                }
                                onClicked: rightPanel.activeTab = 3
                            }

                            Button {

                                id: tab2Btn

                                text: "Channel DSP"

                                Layout.fillWidth: true

                                implicitHeight: 32

                                checkable: true

                                checked: rightPanel.activeTab === 2

                                background: Rectangle {

                                    color: tab2Btn.checked ? "#2600d084" : "#08ffffff"

                                    border.color: tab2Btn.checked ? "#00d084" : "#252b36"

                                    border.width: 1

                                    radius: 6

                                }

                                contentItem: Text {

                                    text: tab2Btn.text

                                    color: tab2Btn.checked ? "#00d084" : "#8a8d98"

                                    font.pixelSize: 10

                                    font.bold: true

                                    horizontalAlignment: Text.AlignHCenter

                                    verticalAlignment: Text.AlignVCenter

                                }

                                onClicked: rightPanel.activeTab = 2

                            }

                        }



                        // Tab 0 Content: Diagnostics (Watchdog & Failover controls)

                        ColumnLayout {

                            Layout.fillWidth: true

                            Layout.fillHeight: true

                            visible: rightPanel.activeTab === 0

                            spacing: 12



                            Text {

                                text: "FAIL-SAFE DIAGNOSTICS"

                                color: "#8a8d98"

                                font.pixelSize: 9

                                font.bold: true

                            }



                            // Hot-plug

                            ColumnLayout {

                                spacing: 4

                                Layout.fillWidth: true

                                Text {

                                    text: "INTERFACE FAILOVER"

                                    color: "#00d084"

                                    font.pixelSize: 8

                                    font.bold: true

                                }

                                RowLayout {

                                    spacing: 8

                                    Button {

                                        text: "Simulate ASIO Drop"

                                        Layout.fillWidth: true

                                        enabled: !audioCore.usingFallback

                                        onClicked: audioCore.simulateDeviceFailure()

                                    }

                                    Button {

                                        text: "Recover ASIO"

                                        Layout.fillWidth: true

                                        enabled: audioCore.usingFallback

                                        onClicked: audioCore.recoverDevice()

                                    }

                                }

                            }



                            // Watchdog Shedding

                            ColumnLayout {

                                spacing: 4

                                Layout.fillWidth: true

                                Text {

                                    text: "WATCHDOG SHEDDING"

                                    color: "#ff3b30"

                                    font.pixelSize: 8

                                    font.bold: true

                                }

                                RowLayout {

                                    spacing: 4

                                    Repeater {

                                        model: 4

                                        delegate: Button {

                                            text: "Lvl " + index

                                            Layout.fillWidth: true

                                            onClicked: audioCore.setSheddingLevel(index)

                                        }

                                    }

                                }

                            }



                            Item { Layout.fillHeight: true }



                            // Active State indicators

                            Rectangle {

                                Layout.fillWidth: true

                                height: 38

                                color: audioCore.usingFallback ? "#3a2a1a" : "#11261d"

                                radius: 6

                                border.color: audioCore.usingFallback ? "#f0a000" : "#00d084"



                                Text {

                                    anchors.centerIn: parent

                                    text: "INTERFACE: " + audioCore.activeDevice

                                    color: audioCore.usingFallback ? "#f0b000" : "#00d084"

                                    font.pixelSize: 10

                                    font.bold: true

                                }

                            }

                        }



                        // Tab 1 Content: DCA & Mute Matrix (Interactive 24x4 Setup Grid and 4 DCA master sliders)

                        ColumnLayout {

                            Layout.fillWidth: true

                            Layout.fillHeight: true

                            visible: rightPanel.activeTab === 1

                            spacing: 8



                            Text {

                                text: "DCA & MUTE INTEGRATION MATRIX"

                                color: "#f0b000"

                                font.pixelSize: 9

                                font.bold: true

                            }



                            // 4 DCA Master Sliders

                            // 8 DCA Master Sliders

                            RowLayout {

                                Layout.fillWidth: true

                                spacing: 6

                                height: 80



                                Repeater {

                                    model: 8

                                    delegate: Rectangle {

                                        Layout.fillWidth: true

                                        Layout.fillHeight: true

                                        color: "#101216"

                                        radius: 6

                                        border.color: "#252b36"

                                        border.width: 1



                                        ColumnLayout {

                                            anchors.fill: parent

                                            anchors.margins: 4

                                            spacing: 1



                                            Text {

                                                text: "DCA " + (index + 1)

                                                color: "#00d084"

                                                font.pixelSize: 9

                                                font.bold: true

                                                Layout.alignment: Qt.AlignHCenter

                                            }



                                            // A small Slider representing DCA volume

                                            PremiumSlider {
                                                id: dcaSlider
                                                Layout.fillWidth: true
                                                Layout.preferredHeight: 18
                                                accentColor: "#00d084"
                                                from: 0.0
                                                to: 1.0
                                                value: audioCore.dcaVolumes[index]
                                                onMoved: {
                                                    audioCore.updateDCAVolume(index, value);
                                                }
                                            }



                                            Text {

                                                text: Math.round(audioCore.dcaVolumes[index] * 100) + "%"

                                                color: "#8a8d98"

                                                font.pixelSize: 8

                                                Layout.alignment: Qt.AlignHCenter

                                            }



                                            // Mute Group toggle

                                            Button {

                                                id: muteGrpBtn

                                                Layout.fillWidth: true

                                                implicitHeight: 18

                                                checkable: true

                                                checked: audioCore.dcaMutes[index]

                                                background: Rectangle {

                                                    color: muteGrpBtn.checked ? "#ff3b30" : "#1a1f29"

                                                    radius: 4

                                                }

                                                contentItem: Text {

                                                    text: "MUTE G" + (index + 1)

                                                    color: muteGrpBtn.checked ? "#ffffff" : "#ff3b30"

                                                    font.pixelSize: 7

                                                    font.bold: true

                                                    horizontalAlignment: Text.AlignHCenter

                                                    verticalAlignment: Text.AlignVCenter

                                                }

                                                onClicked: {

                                                    audioCore.updateMuteGroupState(index, !audioCore.dcaMutes[index]);

                                                }

                                            }

                                        }

                                    }

                                }

                            }



                            // Matrix grid header

                            RowLayout {

                                Layout.fillWidth: true

                                spacing: 2

                                Text {

                                    text: "CH"

                                    color: "#8a8d98"

                                    font.pixelSize: 8

                                    font.bold: true

                                    width: 25

                                    horizontalAlignment: Text.AlignHCenter

                                }

                                Text {

                                    text: "DCA GROUPS (1-8)"

                                    color: "#00d084"

                                    font.pixelSize: 8

                                    font.bold: true

                                    Layout.fillWidth: true

                                    horizontalAlignment: Text.AlignHCenter

                                }

                                Text {

                                    text: "MUTE GROUPS (1-8)"

                                    color: "#ff3b30"

                                    font.pixelSize: 8

                                    font.bold: true

                                    Layout.fillWidth: true

                                    horizontalAlignment: Text.AlignHCenter

                                }

                            }



                            // Interactive 24x8 Setup Grid inside a ScrollView

                            ScrollView {

                                Layout.fillWidth: true

                                Layout.fillHeight: true

                                clip: true



                                ColumnLayout {

                                    width: parent.width - 12

                                    spacing: 4



                                    Repeater {

                                        model: 24

                                        delegate: Rectangle {

                                            Layout.fillWidth: true

                                            height: 24

                                            color: index % 2 === 0 ? "#05ffffff" : "#26000000"

                                            radius: 3

                                            border.color: "#0dffffff"

                                            border.width: 1



                                            property int chIdx: index



                                            RowLayout {

                                                anchors.fill: parent

                                                anchors.margins: 2

                                                spacing: 4



                                                Text {

                                                    text: "CH" + (chIdx + 1)

                                                    color: "#ffffff"

                                                    font.pixelSize: 8

                                                    font.bold: true

                                                    width: 25

                                                    horizontalAlignment: Text.AlignHCenter

                                                }



                                                // DCA Toggles

                                                RowLayout {

                                                    Layout.fillWidth: true

                                                    spacing: 4

                                                    Repeater {

                                                        model: 8

                                                        delegate: Rectangle {

                                                            Layout.fillWidth: true

                                                            Layout.fillHeight: true

                                                            radius: 3

                                                            color: (audioCore.channelDcaMasks[chIdx] & (1 << index)) ? "#00d084" : "#1a1f29"

                                                            border.color: (audioCore.channelDcaMasks[chIdx] & (1 << index)) ? "#00d084" : "#252b36"

                                                            border.width: 1



                                                            Text {

                                                                text: (index + 1)

                                                                color: (audioCore.channelDcaMasks[chIdx] & (1 << index)) ? "#0a0c10" : "#8a8d98"

                                                                font.pixelSize: 8

                                                                font.bold: true

                                                                anchors.centerIn: parent

                                                            }



                                                            MouseArea {

                                                                anchors.fill: parent

                                                                onClicked: {

                                                                    var active = (audioCore.channelDcaMasks[chIdx] & (1 << index)) !== 0;

                                                                    audioCore.updateChannelDCAMapping(chIdx, index, !active);

                                                                }

                                                            }

                                                        }

                                                    }

                                                }



                                                // Mute Group Toggles

                                                RowLayout {

                                                    Layout.fillWidth: true

                                                    spacing: 4

                                                    Repeater {

                                                        model: 8

                                                        delegate: Rectangle {

                                                            Layout.fillWidth: true

                                                            Layout.fillHeight: true

                                                            radius: 3

                                                            color: (audioCore.channelMuteMasks[chIdx] & (1 << index)) ? "#ff3b30" : "#1a1f29"

                                                            border.color: (audioCore.channelMuteMasks[chIdx] & (1 << index)) ? "#ff3b30" : "#252b36"

                                                            border.width: 1



                                                            Text {

                                                                text: "M" + (index + 1)

                                                                color: (audioCore.channelMuteMasks[chIdx] & (1 << index)) ? "#ffffff" : "#8a8d98"

                                                                font.pixelSize: 7

                                                                font.bold: true

                                                                anchors.centerIn: parent

                                                            }



                                                            MouseArea {

                                                                anchors.fill: parent

                                                                onClicked: {

                                                                    var active = (audioCore.channelMuteMasks[chIdx] & (1 << index)) !== 0;

                                                                    audioCore.updateChannelMuteMapping(chIdx, index, !active);

                                                                }

                                                            }

                                                        }

                                                    }

                                                }

                                            }

                                        }

                                    }

                                }

                            }

                                  // Tab 2 Content: Ultimate Channel Strip (UDCS-1) Edit View

                        ScrollView {

                            Layout.fillWidth: true

                            Layout.fillHeight: true

                            visible: rightPanel.activeTab === 2

                            clip: true



                            ColumnLayout {
                                width: rightPanel.width - 25
                                spacing: 12

                                Text {
                                    text: "SELECTED CHANNEL: CH " + (rightPanel.selectedChannel + 1)
                                    color: "#00d084"
                                    font.pixelSize: 11
                                    font.bold: true
                                    Layout.fillWidth: true
                                }

                                // --- PRE-AMP & HARMONIC SATURATION DECK ---
                                Rectangle {
                                    Layout.fillWidth: true
                                    implicitHeight: 180
                                    color: "#101216"
                                    radius: 8
                                    border.color: "#252b36"
                                    border.width: 1

                                    ColumnLayout {
                                        anchors.fill: parent
                                        anchors.margins: 10
                                        spacing: 8

                                        RowLayout {
                                            Layout.fillWidth: true
                                            Text { text: "PRE-AMP & HARMONIC SATURATION"; color: "#8a8d98"; font.pixelSize: 9; font.bold: true }
                                            Item { Layout.fillWidth: true }
                                            Button {
                                                id: satBypassBtn_sandbox
                                                text: audioCore.channelSatBypasses[rightPanel.selectedChannel] ? "BYPASSED" : "ACTIVE"
                                                implicitWidth: 60; implicitHeight: 18
                                                background: Rectangle {
                                                    color: audioCore.channelSatBypasses[rightPanel.selectedChannel] ? "#ff3b30" : "#11261d"
                                                    radius: 4
                                                }
                                                contentItem: Text {
                                                    text: satBypassBtn_sandbox.text
                                                    color: "#ffffff"; font.pixelSize: 8; font.bold: true
                                                    horizontalAlignment: Text.AlignHCenter
                                                    verticalAlignment: Text.AlignVCenter
                                                }
                                                onClicked: audioCore.updateChannelSaturation(rightPanel.selectedChannel, audioCore.channelSatDrives[rightPanel.selectedChannel], audioCore.channelSatMixes[rightPanel.selectedChannel], audioCore.channelSatModes[rightPanel.selectedChannel], !audioCore.channelSatBypasses[rightPanel.selectedChannel])
                                            }
                                        }

                                        RowLayout {
                                            Layout.fillWidth: true
                                            spacing: 12

                                            // Wave Shaper Canvas
                                            Canvas {
                                                renderStrategy: Canvas.Immediate
                                                id: satCanvas_sandbox
                                                width: 80; height: 80
                                                Layout.alignment: Qt.AlignVCenter
                                                onPaint: {
                                                    var ctx = getContext("2d");
                                                    ctx.clearRect(0, 0, width, height);
                                                    ctx.fillStyle = "#0c0e12";
                                                    ctx.fillRect(0, 0, width, height);

                                                    // Draw shaping grid
                                                    ctx.strokeStyle = "#1b1e25"; ctx.lineWidth = 1;
                                                    ctx.beginPath();
                                                    ctx.moveTo(width/2, 0); ctx.lineTo(width/2, height);
                                                    ctx.moveTo(0, height/2); ctx.lineTo(width, height/2);
                                                    ctx.stroke();

                                                    // Plot saturation transfer curve
                                                    ctx.strokeStyle = audioCore.channelSatBypasses[rightPanel.selectedChannel] ? "#8a8d98" : "#00d084";
                                                    ctx.lineWidth = 2;
                                                    ctx.beginPath();
                                                    var mode = audioCore.channelSatModes[rightPanel.selectedChannel];
                                                    var drive = audioCore.channelSatDrives[rightPanel.selectedChannel];
                                                    var mix = audioCore.channelSatMixes[rightPanel.selectedChannel];

                                                    for (var i = 0; i <= width; i++) {
                                                        var x = (i / width) * 2.0 - 1.0;
                                                        var saturated = x;
                                                        if (mode === 0) { // Tube
                                                            saturated = Math.tanh(drive * x);
                                                        } else if (mode === 1) { // Tape
                                                            var driven = drive * x * 0.707;
                                                            saturated = driven - 0.12 * driven * driven - 0.22 * driven * driven * driven;
                                                            saturated = Math.max(-1.0, Math.min(saturated, 1.0));
                                                        } else if (mode === 2) { // Transistor
                                                            var driven = drive * x;
                                                            saturated = driven >= 0 ? 1.0 - Math.exp(-driven) : -1.0 + Math.exp(driven);
                                                        }
                                                        var yVal = (1.0 - mix) * x + mix * saturated;
                                                        var mapY = (1.0 - (yVal + 1.0) / 2.0) * height;
                                                        if (i === 0) ctx.moveTo(i, mapY);
                                                        else ctx.lineTo(i, mapY);
                                                    }
                                                    ctx.stroke();
                                                }
                                                Connections {
                                                    target: audioCore
                                                    function onDspChanged() { satCanvas_sandbox.requestPaint(); }
                                                }
                                            }

                                            ColumnLayout {
                                                Layout.fillWidth: true
                                                spacing: 6

                                                RowLayout {
                                                    spacing: 4
                                                    Repeater {
                                                        model: ["TUBE", "TAPE", "TRANSISTOR"]
                                                        delegate: Button {
                                                            text: modelData
                                                            implicitWidth: 80; implicitHeight: 20
                                                            background: Rectangle {
                                                                color: audioCore.channelSatModes[rightPanel.selectedChannel] === index ? "#00d084" : "#1a1f29"
                                                                radius: 4
                                                            }
                                                            contentItem: Text {
                                                                text: parent.text
                                                                color: audioCore.channelSatModes[rightPanel.selectedChannel] === index ? "#ffffff" : "#8a8d98"
                                                                font.pixelSize: 8; font.bold: true
                                                                horizontalAlignment: Text.AlignHCenter
                                                                verticalAlignment: Text.AlignVCenter
                                                            }
                                                            onClicked: audioCore.updateChannelSaturation(rightPanel.selectedChannel, audioCore.channelSatDrives[rightPanel.selectedChannel], audioCore.channelSatMixes[rightPanel.selectedChannel], index, audioCore.channelSatBypasses[rightPanel.selectedChannel])
                                                        }
                                                    }
                                                }

                                                RowLayout {
                                                    Layout.fillWidth: true
                                                    Text { text: "DRIVE"; color: "#8a8d98"; font.pixelSize: 8; width: 35 }
                                                    PremiumSlider {
                                                        accentColor: "#00d084"
                                                        Layout.fillWidth: true
                                                        from: 1.0; to: 10.0
                                                        value: audioCore.channelSatDrives[rightPanel.selectedChannel]
                                                        onMoved: audioCore.updateChannelSaturation(rightPanel.selectedChannel, value, audioCore.channelSatMixes[rightPanel.selectedChannel], audioCore.channelSatModes[rightPanel.selectedChannel], audioCore.channelSatBypasses[rightPanel.selectedChannel])
                                                    }
                                                    Text { text: audioCore.channelSatDrives[rightPanel.selectedChannel].toFixed(1) + "x"; color: "#00d084"; font.pixelSize: 8; font.family: "Courier New"; width: 28 }
                                                }

                                                RowLayout {
                                                    Layout.fillWidth: true
                                                    Text { text: "MIX"; color: "#8a8d98"; font.pixelSize: 8; width: 35 }
                                                    PremiumSlider {
                                                        accentColor: "#00d084"
                                                        Layout.fillWidth: true
                                                        from: 0.0; to: 1.0
                                                        value: audioCore.channelSatMixes[rightPanel.selectedChannel]
                                                        onMoved: audioCore.updateChannelSaturation(rightPanel.selectedChannel, audioCore.channelSatDrives[rightPanel.selectedChannel], value, audioCore.channelSatModes[rightPanel.selectedChannel], audioCore.channelSatBypasses[rightPanel.selectedChannel])
                                                    }
                                                    Text { text: Math.round(audioCore.channelSatMixes[rightPanel.selectedChannel] * 100) + "%"; color: "#00d084"; font.pixelSize: 8; font.family: "Courier New"; width: 28 }
                                                }
                                            }
                                        }

                                        // Pre-Amp Trim Gain
                                        RowLayout {
                                            Layout.fillWidth: true
                                            Text { text: "TRIM"; color: "#8a8d98"; font.pixelSize: 8; width: 35 }
                                            PremiumSlider {
                                                accentColor: "#00d084"
                                                Layout.fillWidth: true
                                                from: -18.0; to: 18.0
                                                value: audioCore.channelTrims[rightPanel.selectedChannel]
                                                onMoved: audioCore.updateChannelTrim(rightPanel.selectedChannel, value)
                                            }
                                            Text { text: audioCore.channelTrims[rightPanel.selectedChannel].toFixed(1) + "dB"; color: "#00d084"; font.pixelSize: 8; font.family: "Courier New"; width: 35 }

                                            Button {
                                                id: phaseBtn_sandbox
                                                text: "Ø INVERT"
                                                implicitWidth: 50; implicitHeight: 18
                                                background: Rectangle {
                                                    color: audioCore.channelPhases[rightPanel.selectedChannel] ? "#ff3b30" : "#1a1f29"
                                                    radius: 4
                                                }
                                                contentItem: Text {
                                                    text: phaseBtn_sandbox.text
                                                    color: "#ffffff"; font.pixelSize: 7; font.bold: true
                                                    horizontalAlignment: Text.AlignHCenter
                                                    verticalAlignment: Text.AlignVCenter
                                                }
                                                onClicked: audioCore.updateChannelPhase(rightPanel.selectedChannel, !audioCore.channelPhases[rightPanel.selectedChannel])
                                            }
                                        }
                                    }
                                }

                                // --- SELECTABLE 12/24dB/OCT HPF & LPF DECK ---
                                Rectangle {
                                    Layout.fillWidth: true
                                    implicitHeight: 135
                                    color: "#101216"
                                    radius: 8
                                    border.color: "#252b36"
                                    border.width: 1

                                    ColumnLayout {
                                        anchors.fill: parent
                                        anchors.margins: 10
                                        spacing: 6

                                        // HPF sub-section
                                        RowLayout {
                                            Layout.fillWidth: true
                                            Text { text: "HIGH-PASS FILTER (HPF)"; color: "#8a8d98"; font.pixelSize: 9; font.bold: true }
                                            Item { Layout.fillWidth: true }
                                            Button {
                                                text: audioCore.channelHPFSlopes[rightPanel.selectedChannel] + " dB"
                                                implicitWidth: 40; implicitHeight: 16
                                                background: Rectangle { color: "#1a1f29"; radius: 3 }
                                                contentItem: Text { text: parent.text; color: "#00d084"; font.pixelSize: 7; font.bold: true; anchors.centerIn: parent }
                                                onClicked: audioCore.updateChannelHPF(rightPanel.selectedChannel, audioCore.channelHPFCutoffs[rightPanel.selectedChannel], audioCore.channelHPFSlopes[rightPanel.selectedChannel] === 12 ? 24 : 12, audioCore.channelHPFBypasses[rightPanel.selectedChannel])
                                            }
                                            Button {
                                                text: audioCore.channelHPFBypasses[rightPanel.selectedChannel] ? "BYPASSED" : "ACTIVE"
                                                implicitWidth: 55; implicitHeight: 16
                                                background: Rectangle { color: audioCore.channelHPFBypasses[rightPanel.selectedChannel] ? "#ff3b30" : "#11261d"; radius: 3 }
                                                contentItem: Text { text: parent.text; color: "#ffffff"; font.pixelSize: 7; font.bold: true; anchors.centerIn: parent }
                                                onClicked: audioCore.updateChannelHPF(rightPanel.selectedChannel, audioCore.channelHPFCutoffs[rightPanel.selectedChannel], audioCore.channelHPFSlopes[rightPanel.selectedChannel], !audioCore.channelHPFBypasses[rightPanel.selectedChannel])
                                            }
                                        }

                                        RowLayout {
                                            Layout.fillWidth: true
                                            PremiumSlider {
                                                accentColor: "#00d084"
                                                Layout.fillWidth: true
                                                from: 20.0; to: 400.0
                                                value: audioCore.channelHPFCutoffs[rightPanel.selectedChannel]
                                                onMoved: audioCore.updateChannelHPF(rightPanel.selectedChannel, value, audioCore.channelHPFSlopes[rightPanel.selectedChannel], audioCore.channelHPFBypasses[rightPanel.selectedChannel])
                                            }
                                            Text { text: Math.round(audioCore.channelHPFCutoffs[rightPanel.selectedChannel]) + " Hz"; color: "#00d084"; font.pixelSize: 8; font.bold: true; font.family: "Courier New"; width: 40 }
                                        }

                                        // LPF sub-section
                                        RowLayout {
                                            Layout.fillWidth: true
                                            Text { text: "LOW-PASS FILTER (LPF)"; color: "#8a8d98"; font.pixelSize: 9; font.bold: true }
                                            Item { Layout.fillWidth: true }
                                            Button {
                                                text: audioCore.channelLPFSlopes[rightPanel.selectedChannel] + " dB"
                                                implicitWidth: 40; implicitHeight: 16
                                                background: Rectangle { color: "#1a1f29"; radius: 3 }
                                                contentItem: Text { text: parent.text; color: "#00d084"; font.pixelSize: 7; font.bold: true; anchors.centerIn: parent }
                                                onClicked: audioCore.updateChannelLPF(rightPanel.selectedChannel, audioCore.channelLPFCutoffs[rightPanel.selectedChannel], audioCore.channelLPFSlopes[rightPanel.selectedChannel] === 12 ? 24 : 12, audioCore.channelLPFBypasses[rightPanel.selectedChannel])
                                            }
                                            Button {
                                                text: audioCore.channelLPFBypasses[rightPanel.selectedChannel] ? "BYPASSED" : "ACTIVE"
                                                implicitWidth: 55; implicitHeight: 16
                                                background: Rectangle { color: audioCore.channelLPFBypasses[rightPanel.selectedChannel] ? "#ff3b30" : "#11261d"; radius: 3 }
                                                contentItem: Text { text: parent.text; color: "#ffffff"; font.pixelSize: 7; font.bold: true; anchors.centerIn: parent }
                                                onClicked: audioCore.updateChannelLPF(rightPanel.selectedChannel, audioCore.channelLPFCutoffs[rightPanel.selectedChannel], audioCore.channelLPFSlopes[rightPanel.selectedChannel], !audioCore.channelLPFBypasses[rightPanel.selectedChannel])
                                            }
                                        }

                                        RowLayout {
                                            Layout.fillWidth: true
                                            PremiumSlider {
                                                accentColor: "#00d084"
                                                Layout.fillWidth: true
                                                from: 2000.0; to: 20000.0
                                                value: audioCore.channelLPFCutoffs[rightPanel.selectedChannel]
                                                onMoved: audioCore.updateChannelLPF(rightPanel.selectedChannel, value, audioCore.channelLPFSlopes[rightPanel.selectedChannel], audioCore.channelLPFBypasses[rightPanel.selectedChannel])
                                            }
                                            Text { text: (audioCore.channelLPFCutoffs[rightPanel.selectedChannel] / 1000.0).toFixed(1) + " kHz"; color: "#00d084"; font.pixelSize: 8; font.bold: true; font.family: "Courier New"; width: 40 }
                                        }
                                    }
                                }

                                // --- DE-ESSER & TRANSIENT DESIGNER DECK ---
                                Rectangle {
                                    Layout.fillWidth: true
                                    implicitHeight: 155
                                    color: "#101216"
                                    radius: 8
                                    border.color: "#252b36"
                                    border.width: 1

                                    ColumnLayout {
                                        anchors.fill: parent
                                        anchors.margins: 10
                                        spacing: 6

                                        // De-Esser
                                        RowLayout {
                                            Layout.fillWidth: true
                                            Text { text: "SIBILANCE DE-ESSER"; color: "#8a8d98"; font.pixelSize: 9; font.bold: true }
                                            Item { Layout.fillWidth: true }
                                            Button {
                                                text: audioCore.channelDeEsserBypasses[rightPanel.selectedChannel] ? "BYPASSED" : "ACTIVE"
                                                implicitWidth: 55; implicitHeight: 16
                                                background: Rectangle { color: audioCore.channelDeEsserBypasses[rightPanel.selectedChannel] ? "#ff3b30" : "#11261d"; radius: 3 }
                                                contentItem: Text { text: parent.text; color: "#ffffff"; font.pixelSize: 7; font.bold: true; anchors.centerIn: parent }
                                                onClicked: audioCore.updateChannelDeEsser(rightPanel.selectedChannel, audioCore.channelDeEsserFreqs[rightPanel.selectedChannel], audioCore.channelDeEsserThresholds[rightPanel.selectedChannel], !audioCore.channelDeEsserBypasses[rightPanel.selectedChannel])
                                            }
                                        }

                                        RowLayout {
                                            Layout.fillWidth: true
                                            spacing: 6
                                            Text { text: "FREQ"; color: "#8a8d98"; font.pixelSize: 8; width: 35 }
                                            PremiumSlider {
                                                Layout.fillWidth: true
                                                accentColor: "#00d084"
                                                from: 4000.0; to: 10000.0
                                                value: audioCore.channelDeEsserFreqs[rightPanel.selectedChannel]
                                                onMoved: audioCore.updateChannelDeEsser(rightPanel.selectedChannel, value, audioCore.channelDeEsserThresholds[rightPanel.selectedChannel], audioCore.channelDeEsserBypasses[rightPanel.selectedChannel])
                                            }
                                            Text { text: Math.round(audioCore.channelDeEsserFreqs[rightPanel.selectedChannel]) + "Hz"; color: "#00d084"; font.pixelSize: 8; font.family: "Courier New"; width: 40 }
                                        }

                                        RowLayout {
                                            Layout.fillWidth: true
                                            spacing: 6
                                            Text { text: "THRESH"; color: "#8a8d98"; font.pixelSize: 8; width: 35 }
                                            PremiumSlider {
                                                Layout.fillWidth: true
                                                accentColor: "#ff9500"
                                                from: -60.0; to: 0.0
                                                value: audioCore.channelDeEsserThresholds[rightPanel.selectedChannel]
                                                onMoved: audioCore.updateChannelDeEsser(rightPanel.selectedChannel, audioCore.channelDeEsserFreqs[rightPanel.selectedChannel], value, audioCore.channelDeEsserBypasses[rightPanel.selectedChannel])
                                            }
                                            Text { text: Math.round(audioCore.channelDeEsserThresholds[rightPanel.selectedChannel]) + "dB"; color: "#ff9500"; font.pixelSize: 8; font.family: "Courier New"; width: 40 }
                                        }

                                        // Transient Designer
                                        RowLayout {
                                            Layout.fillWidth: true
                                            Text { text: "TRANSIENT DESIGNER"; color: "#8a8d98"; font.pixelSize: 9; font.bold: true }
                                            Item { Layout.fillWidth: true }
                                            Button {
                                                text: audioCore.channelTransientBypasses[rightPanel.selectedChannel] ? "BYPASSED" : "ACTIVE"
                                                implicitWidth: 55; implicitHeight: 16
                                                background: Rectangle { color: audioCore.channelTransientBypasses[rightPanel.selectedChannel] ? "#ff3b30" : "#11261d"; radius: 3 }
                                                contentItem: Text { text: parent.text; color: "#ffffff"; font.pixelSize: 7; font.bold: true; anchors.centerIn: parent }
                                                onClicked: audioCore.updateChannelTransient(rightPanel.selectedChannel, audioCore.channelTransientAttacks[rightPanel.selectedChannel], audioCore.channelTransientSustains[rightPanel.selectedChannel], !audioCore.channelTransientBypasses[rightPanel.selectedChannel])
                                            }
                                        }

                                        RowLayout {
                                            Layout.fillWidth: true
                                            spacing: 8
                                            Text { text: "ATTACK"; color: "#8a8d98"; font.pixelSize: 8; width: 35 }
                                            PremiumSlider {
                                                Layout.fillWidth: true
                                                accentColor: "#00d084"
                                                from: -1.0; to: 1.0
                                                value: audioCore.channelTransientAttacks[rightPanel.selectedChannel]
                                                onMoved: audioCore.updateChannelTransient(rightPanel.selectedChannel, value, audioCore.channelTransientSustains[rightPanel.selectedChannel], audioCore.channelTransientBypasses[rightPanel.selectedChannel])
                                            }
                                            Text { text: (audioCore.channelTransientAttacks[rightPanel.selectedChannel] >= 0 ? "+" : "") + Math.round(audioCore.channelTransientAttacks[rightPanel.selectedChannel] * 15) + "dB"; color: "#00d084"; font.pixelSize: 8; font.family: "Courier New"; width: 40 }
                                        }
                                    }
                                }

                                // --- 4-BAND PARAMETRIC & DYNAMIC EQ DECK ---
                                Rectangle {
                                    Layout.fillWidth: true
                                    implicitHeight: 480
                                    color: "#101216"
                                    radius: 8
                                    border.color: "#252b36"
                                    border.width: 1

                                    ColumnLayout {
                                        anchors.fill: parent
                                        anchors.margins: 10
                                        spacing: 6

                                        Text { text: "4-BAND PARAMETRIC & DYNAMIC EQ"; color: "#8a8d98"; font.pixelSize: 9; font.bold: true }

                                        // Interactive Logarithmic EQ Node Graph
                                        Canvas {
                                            renderStrategy: Canvas.Immediate
                                            id: eqCanvas_sandbox
                                            Layout.fillWidth: true
                                            height: 80
                                            Connections {
                                                target: audioCore
                                                function onDspChanged() { eqCanvas_sandbox.requestPaint(); }
                                            }
                                            onPaint: {
                                                var ctx = getContext("2d");
                                                ctx.clearRect(0, 0, width, height);
                                                ctx.fillStyle = "#0c0e12";
                                                ctx.fillRect(0, 0, width, height);

                                                // Reference grid
                                                ctx.strokeStyle = "#15181e"; ctx.lineWidth = 1;
                                                ctx.beginPath();
                                                ctx.moveTo(0, height/2); ctx.lineTo(width, height/2);
                                                ctx.stroke();

                                                // Plot neon cyan curve
                                                ctx.strokeStyle = "#00d084"; ctx.lineWidth = 2.5;
                                                ctx.beginPath();
                                                var ch = rightPanel.selectedChannel;
                                                var g0 = audioCore.channelEQBand0Gains[ch];
                                                var g1 = audioCore.channelEQBand1Gains[ch];
                                                var g2 = audioCore.channelEQBand2Gains[ch];
                                                var g3 = audioCore.channelEQBand3Gains[ch];

                                                var f0 = audioCore.channelEQBand0Freqs[ch];
                                                var f1 = audioCore.channelEQBand1Freqs[ch];
                                                var f2 = audioCore.channelEQBand2Freqs[ch];
                                                var f3 = audioCore.channelEQBand3Freqs[ch];

                                                var type0 = audioCore.channelEQBand0Types[ch];
                                                var type3 = audioCore.channelEQBand3Types[ch];

                                                for (var x = 0; x <= width; x += 2) {
                                                    var pct = x / width;
                                                    var f = 20 * Math.pow(1000, pct);
                                                    var yVal = 0;

                                                    if (type0 === 0) {
                                                        yVal += g0 * (1.0 - Math.min(1.0, Math.max(0.0, (f - f0) / (f0 * 1.5))));
                                                    } else {
                                                        yVal += g0 * Math.exp(-Math.abs(Math.log10(f / f0)) * 5.0);
                                                    }

                                                    yVal += g1 * Math.exp(-Math.abs(Math.log10(f / f1)) * 5.0);
                                                    yVal += g2 * Math.exp(-Math.abs(Math.log10(f / f2)) * 5.0);

                                                    if (type3 === 0) {
                                                        yVal += g3 * Math.min(1.0, Math.max(0.0, (f - f3) / f3));
                                                    } else {
                                                        yVal += g3 * Math.exp(-Math.abs(Math.log10(f / f3)) * 5.0);
                                                    }

                                                    var mapY = (height / 2) - (yVal / 15.0) * (height / 2.4);
                                                    if (x === 0) ctx.moveTo(x, mapY);
                                                    else ctx.lineTo(x, mapY);
                                                }
                                                ctx.stroke();

                                                // Draw interactive band node handles
                                                var freqs = [f0, f1, f2, f3];
                                                var gains = [g0, g1, g2, g3];
                                                var bandColors = ["#00d084", "#ffc72c", "#ff9500", "#ff3b30"];

                                                for (var i = 0; i < 4; i++) {
                                                    var nx = width * Math.log10(freqs[i] / 20) / 3;
                                                    var ny = (height / 2) - (gains[i] / 15.0) * (height / 2.4);

                                                    // 1. Outer glow
                                                    ctx.globalAlpha = 0.3;
                                                    ctx.fillStyle = bandColors[i];
                                                    ctx.beginPath();
                                                    ctx.arc(nx, ny, 8, 0, 2 * Math.PI);
                                                    ctx.fill();

                                                    // 2. Inner solid
                                                    ctx.globalAlpha = 1.0;
                                                    ctx.fillStyle = bandColors[i];
                                                    ctx.beginPath();
                                                    ctx.arc(nx, ny, 4, 0, 2 * Math.PI);
                                                    ctx.fill();

                                                    // 3. White border
                                                    ctx.strokeStyle = "#ffffff";
                                                    ctx.lineWidth = 1.5;
                                                    ctx.beginPath();
                                                    ctx.arc(nx, ny, 4, 0, 2 * Math.PI);
                                                    ctx.stroke();
                                                }
                                                // Reset globalAlpha to default
                                                ctx.globalAlpha = 1.0;
                                            }

                                            MouseArea {
                                                anchors.fill: parent
                                                hoverEnabled: true
                                                property int grabbedBand: -1

                                                onPressed: (mouse) => {
                                                    var ch = rightPanel.selectedChannel;
                                                    var freqs = [
                                                        audioCore.channelEQBand0Freqs[ch],
                                                        audioCore.channelEQBand1Freqs[ch],
                                                        audioCore.channelEQBand2Freqs[ch],
                                                        audioCore.channelEQBand3Freqs[ch]
                                                    ];
                                                    var gains = [
                                                        audioCore.channelEQBand0Gains[ch],
                                                        audioCore.channelEQBand1Gains[ch],
                                                        audioCore.channelEQBand2Gains[ch],
                                                        audioCore.channelEQBand3Gains[ch]
                                                    ];

                                                    var closestBand = -1;
                                                    var minDistance = 999999;

                                                    for (var i = 0; i < 4; i++) {
                                                        var nx = parent.width * Math.log10(freqs[i] / 20) / 3;
                                                        var ny = (parent.height / 2) - (gains[i] / 15.0) * (parent.height / 2.4);

                                                        var dist = Math.sqrt((mouse.x - nx) * (mouse.x - nx) + (mouse.y - ny) * (mouse.y - ny));
                                                        if (dist < minDistance) {
                                                            minDistance = dist;
                                                            closestBand = i;
                                                        }
                                                    }

                                                    if (minDistance <= 16) {
                                                        grabbedBand = closestBand;
                                                    } else {
                                                        grabbedBand = -1;
                                                    }
                                                }

                                                onPositionChanged: (mouse) => {
                                                    if (grabbedBand !== -1) {
                                                        var ch = rightPanel.selectedChannel;
                                                        var minF = sandboxWin.getBandMinFreq(grabbedBand);
                                                        var maxF = sandboxWin.getBandMaxFreq(grabbedBand);
                                                        
                                                        // Map mouse.x to logarithmic frequency
                                                        var freq = 20 * Math.pow(1000, mouse.x / parent.width);
                                                        freq = Math.min(maxF, Math.max(minF, freq));

                                                        // Map mouse.y to linear gain
                                                        var gain = 15 - 30 * mouse.y / parent.height;
                                                        gain = Math.min(15.0, Math.max(-15.0, gain));

                                                        // Call C++ update methods
                                                        audioCore.updateChannelEQ(ch, grabbedBand, gain);
                                                        audioCore.updateChannelEQFreq(ch, grabbedBand, freq);
                                                        
                                                        parent.requestPaint();
                                                    }
                                                }

                                                onReleased: (mouse) => {
                                                    grabbedBand = -1;
                                                }
                                            }
                                        }

                                        // Quick band sliders and dynamic selectors
                                        ColumnLayout {
                                            Layout.fillWidth: true
                                            spacing: 4

                                            // BAND 0 (LOW SHELF)
                                            ColumnLayout {
                                                Layout.fillWidth: true
                                                spacing: 4

                                                // Band Header
                                                RowLayout {
                                                    Layout.fillWidth: true
                                                    Text { 
                                                        text: audioCore.channelEQBand0Types[rightPanel.selectedChannel] === 0 ? "LOW SHELF" : "LOW PEAK"
                                                        color: "#00d084"; font.pixelSize: 9; font.bold: true 
                                                    }
                                                    Item { Layout.fillWidth: true }
                                                    Button {
                                                        text: audioCore.channelEQBand0Types[rightPanel.selectedChannel] === 0 ? "SHELF" : "BELL"
                                                        implicitWidth: 42; implicitHeight: 16
                                                        background: Rectangle { color: audioCore.channelEQBand0Types[rightPanel.selectedChannel] === 0 ? "#11261d" : "#1a1f29"; radius: 3 }
                                                        contentItem: Text { text: parent.text; color: "#00d084"; font.pixelSize: 7; font.bold: true; anchors.centerIn: parent }
                                                        onClicked: audioCore.updateChannelEQType(rightPanel.selectedChannel, 0, audioCore.channelEQBand0Types[rightPanel.selectedChannel] === 0 ? 1 : 0)
                                                    }
                                                    Button {
                                                        text: audioCore.channelEQBand0Dynamics[rightPanel.selectedChannel] ? "DYN ON" : "DYN OFF"
                                                        implicitWidth: 46; implicitHeight: 16
                                                        background: Rectangle { color: audioCore.channelEQBand0Dynamics[rightPanel.selectedChannel] ? "#00d084" : "#1a1f29"; radius: 3 }
                                                        contentItem: Text { text: parent.text; color: audioCore.channelEQBand0Dynamics[rightPanel.selectedChannel] ? "#0a0c10" : "#8a8d98"; font.pixelSize: 7; font.bold: true; anchors.centerIn: parent }
                                                        onClicked: audioCore.updateChannelEQDynamic(rightPanel.selectedChannel, 0, !audioCore.channelEQBand0Dynamics[rightPanel.selectedChannel])
                                                    }
                                                }

                                                // Sliders
                                                RowLayout {
                                                    Layout.fillWidth: true
                                                    spacing: 6

                                                    // Gain
                                                    RowLayout {
                                                        Layout.fillWidth: true; Layout.preferredWidth: 1; spacing: 4
                                                        Text { text: "G"; color: "#8a8d98"; font.pixelSize: 8; font.bold: true }
                                                        PremiumSlider {
                                                            Layout.fillWidth: true; accentColor: "#00d084"
                                                            from: -15.0; to: 15.0
                                                            value: audioCore.channelEQBand0Gains[rightPanel.selectedChannel]
                                                            onMoved: audioCore.updateChannelEQ(rightPanel.selectedChannel, 0, value)
                                                        }
                                                        Text { text: audioCore.channelEQBand0Gains[rightPanel.selectedChannel].toFixed(1) + "dB"; color: "#00d084"; font.pixelSize: 8; font.family: "Courier New"; width: 35 }
                                                    }

                                                    // Frequency
                                                    RowLayout {
                                                        Layout.fillWidth: true; Layout.preferredWidth: 1; spacing: 4
                                                        Text { text: "F"; color: "#8a8d98"; font.pixelSize: 8; font.bold: true }
                                                        PremiumSlider {
                                                            Layout.fillWidth: true; accentColor: "#00d084"
                                                            from: 0.0; to: 1.0
                                                            value: sandboxWin.getEQFreqSliderVal(0, rightPanel.selectedChannel)
                                                            onMoved: audioCore.updateChannelEQFreq(rightPanel.selectedChannel, 0, sandboxWin.getBandMinFreq(0) * Math.pow(sandboxWin.getBandMaxFreq(0) / sandboxWin.getBandMinFreq(0), value))
                                                        }
                                                        Text {
                                                            text: {
                                                                var f = sandboxWin.getEQFreq(0, rightPanel.selectedChannel);
                                                                return (f >= 1000 ? (f/1000).toFixed(1) + "k" : Math.round(f)) + "Hz";
                                                            }
                                                            color: "#00d084"; font.pixelSize: 8; font.family: "Courier New"; width: 40
                                                        }
                                                    }

                                                    // Q
                                                    RowLayout {
                                                        Layout.fillWidth: true; Layout.preferredWidth: 1; spacing: 4
                                                        Text { text: "Q"; color: "#8a8d98"; font.pixelSize: 8; font.bold: true }
                                                        PremiumSlider {
                                                            Layout.fillWidth: true; accentColor: "#00d084"
                                                            from: 0.5; to: 10.0
                                                            value: audioCore.channelEQBand0Qs[rightPanel.selectedChannel]
                                                            onMoved: audioCore.updateChannelEQQ(rightPanel.selectedChannel, 0, value)
                                                        }
                                                        Text { text: audioCore.channelEQBand0Qs[rightPanel.selectedChannel].toFixed(2); color: "#00d084"; font.pixelSize: 8; font.family: "Courier New"; width: 28 }
                                                    }
                                                }
                                            }

                                            // Spacer line between bands
                                            Rectangle {
                                                Layout.fillWidth: true; height: 1; color: "#1e222b"
                                            }

                                            // BAND 1 (LOW-MID)
                                            ColumnLayout {
                                                Layout.fillWidth: true
                                                spacing: 4

                                                // Band Header
                                                RowLayout {
                                                    Layout.fillWidth: true
                                                    Text { text: "LOW-MID"; color: "#ffc72c"; font.pixelSize: 9; font.bold: true }
                                                    Item { Layout.fillWidth: true }
                                                    Button {
                                                        text: audioCore.channelEQBand1Dynamics[rightPanel.selectedChannel] ? "DYN ON" : "DYN OFF"
                                                        implicitWidth: 46; implicitHeight: 16
                                                        background: Rectangle { color: audioCore.channelEQBand1Dynamics[rightPanel.selectedChannel] ? "#ffc72c" : "#1a1f29"; radius: 3 }
                                                        contentItem: Text { text: parent.text; color: audioCore.channelEQBand1Dynamics[rightPanel.selectedChannel] ? "#0a0c10" : "#8a8d98"; font.pixelSize: 7; font.bold: true; anchors.centerIn: parent }
                                                        onClicked: audioCore.updateChannelEQDynamic(rightPanel.selectedChannel, 1, !audioCore.channelEQBand1Dynamics[rightPanel.selectedChannel])
                                                    }
                                                }

                                                // Sliders
                                                RowLayout {
                                                    Layout.fillWidth: true
                                                    spacing: 6

                                                    // Gain
                                                    RowLayout {
                                                        Layout.fillWidth: true; Layout.preferredWidth: 1; spacing: 4
                                                        Text { text: "G"; color: "#8a8d98"; font.pixelSize: 8; font.bold: true }
                                                        PremiumSlider {
                                                            Layout.fillWidth: true; accentColor: "#ffc72c"
                                                            from: -15.0; to: 15.0
                                                            value: audioCore.channelEQBand1Gains[rightPanel.selectedChannel]
                                                            onMoved: audioCore.updateChannelEQ(rightPanel.selectedChannel, 1, value)
                                                        }
                                                        Text { text: audioCore.channelEQBand1Gains[rightPanel.selectedChannel].toFixed(1) + "dB"; color: "#ffc72c"; font.pixelSize: 8; font.family: "Courier New"; width: 35 }
                                                    }

                                                    // Frequency
                                                    RowLayout {
                                                        Layout.fillWidth: true; Layout.preferredWidth: 1; spacing: 4
                                                        Text { text: "F"; color: "#8a8d98"; font.pixelSize: 8; font.bold: true }
                                                        PremiumSlider {
                                                            Layout.fillWidth: true; accentColor: "#ffc72c"
                                                            from: 0.0; to: 1.0
                                                            value: sandboxWin.getEQFreqSliderVal(1, rightPanel.selectedChannel)
                                                            onMoved: audioCore.updateChannelEQFreq(rightPanel.selectedChannel, 1, sandboxWin.getBandMinFreq(1) * Math.pow(sandboxWin.getBandMaxFreq(1) / sandboxWin.getBandMinFreq(1), value))
                                                        }
                                                        Text {
                                                            text: {
                                                                var f = sandboxWin.getEQFreq(1, rightPanel.selectedChannel);
                                                                return (f >= 1000 ? (f/1000).toFixed(1) + "k" : Math.round(f)) + "Hz";
                                                            }
                                                            color: "#ffc72c"; font.pixelSize: 8; font.family: "Courier New"; width: 40
                                                        }
                                                    }

                                                    // Q
                                                    RowLayout {
                                                        Layout.fillWidth: true; Layout.preferredWidth: 1; spacing: 4
                                                        Text { text: "Q"; color: "#8a8d98"; font.pixelSize: 8; font.bold: true }
                                                        PremiumSlider {
                                                            Layout.fillWidth: true; accentColor: "#ffc72c"
                                                            from: 0.5; to: 10.0
                                                            value: audioCore.channelEQBand1Qs[rightPanel.selectedChannel]
                                                            onMoved: audioCore.updateChannelEQQ(rightPanel.selectedChannel, 1, value)
                                                        }
                                                        Text { text: audioCore.channelEQBand1Qs[rightPanel.selectedChannel].toFixed(2); color: "#ffc72c"; font.pixelSize: 8; font.family: "Courier New"; width: 28 }
                                                    }
                                                }
                                            }

                                            // Spacer line between bands
                                            Rectangle {
                                                Layout.fillWidth: true; height: 1; color: "#1e222b"
                                            }

                                            // BAND 2 (HIGH-MID)
                                            ColumnLayout {
                                                Layout.fillWidth: true
                                                spacing: 4

                                                // Band Header
                                                RowLayout {
                                                    Layout.fillWidth: true
                                                    Text { text: "HIGH-MID"; color: "#ff9500"; font.pixelSize: 9; font.bold: true }
                                                    Item { Layout.fillWidth: true }
                                                    Button {
                                                        text: audioCore.channelEQBand2Dynamics[rightPanel.selectedChannel] ? "DYN ON" : "DYN OFF"
                                                        implicitWidth: 46; implicitHeight: 16
                                                        background: Rectangle { color: audioCore.channelEQBand2Dynamics[rightPanel.selectedChannel] ? "#ff9500" : "#1a1f29"; radius: 3 }
                                                        contentItem: Text { text: parent.text; color: audioCore.channelEQBand2Dynamics[rightPanel.selectedChannel] ? "#0a0c10" : "#8a8d98"; font.pixelSize: 7; font.bold: true; anchors.centerIn: parent }
                                                        onClicked: audioCore.updateChannelEQDynamic(rightPanel.selectedChannel, 2, !audioCore.channelEQBand2Dynamics[rightPanel.selectedChannel])
                                                    }
                                                }

                                                // Sliders
                                                RowLayout {
                                                    Layout.fillWidth: true
                                                    spacing: 6

                                                    // Gain
                                                    RowLayout {
                                                        Layout.fillWidth: true; Layout.preferredWidth: 1; spacing: 4
                                                        Text { text: "G"; color: "#8a8d98"; font.pixelSize: 8; font.bold: true }
                                                        PremiumSlider {
                                                            Layout.fillWidth: true; accentColor: "#ff9500"
                                                            from: -15.0; to: 15.0
                                                            value: audioCore.channelEQBand2Gains[rightPanel.selectedChannel]
                                                            onMoved: audioCore.updateChannelEQ(rightPanel.selectedChannel, 2, value)
                                                        }
                                                        Text { text: audioCore.channelEQBand2Gains[rightPanel.selectedChannel].toFixed(1) + "dB"; color: "#ff9500"; font.pixelSize: 8; font.family: "Courier New"; width: 35 }
                                                    }

                                                    // Frequency
                                                    RowLayout {
                                                        Layout.fillWidth: true; Layout.preferredWidth: 1; spacing: 4
                                                        Text { text: "F"; color: "#8a8d98"; font.pixelSize: 8; font.bold: true }
                                                        PremiumSlider {
                                                            Layout.fillWidth: true; accentColor: "#ff9500"
                                                            from: 0.0; to: 1.0
                                                            value: sandboxWin.getEQFreqSliderVal(2, rightPanel.selectedChannel)
                                                            onMoved: audioCore.updateChannelEQFreq(rightPanel.selectedChannel, 2, sandboxWin.getBandMinFreq(2) * Math.pow(sandboxWin.getBandMaxFreq(2) / sandboxWin.getBandMinFreq(2), value))
                                                        }
                                                        Text {
                                                            text: {
                                                                var f = sandboxWin.getEQFreq(2, rightPanel.selectedChannel);
                                                                return (f >= 1000 ? (f/1000).toFixed(1) + "k" : Math.round(f)) + "Hz";
                                                            }
                                                            color: "#ff9500"; font.pixelSize: 8; font.family: "Courier New"; width: 40
                                                        }
                                                    }

                                                    // Q
                                                    RowLayout {
                                                        Layout.fillWidth: true; Layout.preferredWidth: 1; spacing: 4
                                                        Text { text: "Q"; color: "#8a8d98"; font.pixelSize: 8; font.bold: true }
                                                        PremiumSlider {
                                                            Layout.fillWidth: true; accentColor: "#ff9500"
                                                            from: 0.5; to: 10.0
                                                            value: audioCore.channelEQBand2Qs[rightPanel.selectedChannel]
                                                            onMoved: audioCore.updateChannelEQQ(rightPanel.selectedChannel, 2, value)
                                                        }
                                                        Text { text: audioCore.channelEQBand2Qs[rightPanel.selectedChannel].toFixed(2); color: "#ff9500"; font.pixelSize: 8; font.family: "Courier New"; width: 28 }
                                                    }
                                                }
                                            }

                                            // Spacer line between bands
                                            Rectangle {
                                                Layout.fillWidth: true; height: 1; color: "#1e222b"
                                            }

                                            // BAND 3 (HIGH SHELF)
                                            ColumnLayout {
                                                Layout.fillWidth: true
                                                spacing: 4

                                                // Band Header
                                                RowLayout {
                                                    Layout.fillWidth: true
                                                    Text { 
                                                        text: audioCore.channelEQBand3Types[rightPanel.selectedChannel] === 0 ? "HIGH SHELF" : "HIGH PEAK"
                                                        color: "#ff3b30"; font.pixelSize: 9; font.bold: true 
                                                    }
                                                    Item { Layout.fillWidth: true }
                                                    Button {
                                                        text: audioCore.channelEQBand3Types[rightPanel.selectedChannel] === 0 ? "SHELF" : "BELL"
                                                        implicitWidth: 42; implicitHeight: 16
                                                        background: Rectangle { color: audioCore.channelEQBand3Types[rightPanel.selectedChannel] === 0 ? "#261111" : "#1a1f29"; radius: 3 }
                                                        contentItem: Text { text: parent.text; color: "#ff3b30"; font.pixelSize: 7; font.bold: true; anchors.centerIn: parent }
                                                        onClicked: audioCore.updateChannelEQType(rightPanel.selectedChannel, 3, audioCore.channelEQBand3Types[rightPanel.selectedChannel] === 0 ? 1 : 0)
                                                    }
                                                    Button {
                                                        text: audioCore.channelEQBand3Dynamics[rightPanel.selectedChannel] ? "DYN ON" : "DYN OFF"
                                                        implicitWidth: 46; implicitHeight: 16
                                                        background: Rectangle { color: audioCore.channelEQBand3Dynamics[rightPanel.selectedChannel] ? "#ff3b30" : "#1a1f29"; radius: 3 }
                                                        contentItem: Text { text: parent.text; color: audioCore.channelEQBand3Dynamics[rightPanel.selectedChannel] ? "#0a0c10" : "#8a8d98"; font.pixelSize: 7; font.bold: true; anchors.centerIn: parent }
                                                        onClicked: audioCore.updateChannelEQDynamic(rightPanel.selectedChannel, 3, !audioCore.channelEQBand3Dynamics[rightPanel.selectedChannel])
                                                    }
                                                }

                                                // Sliders
                                                RowLayout {
                                                    Layout.fillWidth: true
                                                    spacing: 6

                                                    // Gain
                                                    RowLayout {
                                                        Layout.fillWidth: true; Layout.preferredWidth: 1; spacing: 4
                                                        Text { text: "G"; color: "#8a8d98"; font.pixelSize: 8; font.bold: true }
                                                        PremiumSlider {
                                                            Layout.fillWidth: true; accentColor: "#ff3b30"
                                                            from: -15.0; to: 15.0
                                                            value: audioCore.channelEQBand3Gains[rightPanel.selectedChannel]
                                                            onMoved: audioCore.updateChannelEQ(rightPanel.selectedChannel, 3, value)
                                                        }
                                                        Text { text: audioCore.channelEQBand3Gains[rightPanel.selectedChannel].toFixed(1) + "dB"; color: "#ff3b30"; font.pixelSize: 8; font.family: "Courier New"; width: 35 }
                                                    }

                                                    // Frequency
                                                    RowLayout {
                                                        Layout.fillWidth: true; Layout.preferredWidth: 1; spacing: 4
                                                        Text { text: "F"; color: "#8a8d98"; font.pixelSize: 8; font.bold: true }
                                                        PremiumSlider {
                                                            Layout.fillWidth: true; accentColor: "#ff3b30"
                                                            from: 0.0; to: 1.0
                                                            value: sandboxWin.getEQFreqSliderVal(3, rightPanel.selectedChannel)
                                                            onMoved: audioCore.updateChannelEQFreq(rightPanel.selectedChannel, 3, sandboxWin.getBandMinFreq(3) * Math.pow(sandboxWin.getBandMaxFreq(3) / sandboxWin.getBandMinFreq(3), value))
                                                        }
                                                        Text {
                                                            text: {
                                                                var f = sandboxWin.getEQFreq(3, rightPanel.selectedChannel);
                                                                return (f >= 1000 ? (f/1000).toFixed(1) + "k" : Math.round(f)) + "Hz";
                                                            }
                                                            color: "#ff3b30"; font.pixelSize: 8; font.family: "Courier New"; width: 40
                                                        }
                                                    }

                                                    // Q
                                                    RowLayout {
                                                        Layout.fillWidth: true; Layout.preferredWidth: 1; spacing: 4
                                                        Text { text: "Q"; color: "#8a8d98"; font.pixelSize: 8; font.bold: true }
                                                        PremiumSlider {
                                                            Layout.fillWidth: true; accentColor: "#ff3b30"
                                                            from: 0.5; to: 10.0
                                                            value: audioCore.channelEQBand3Qs[rightPanel.selectedChannel]
                                                            onMoved: audioCore.updateChannelEQQ(rightPanel.selectedChannel, 3, value)
                                                        }
                                                        Text { text: audioCore.channelEQBand3Qs[rightPanel.selectedChannel].toFixed(2); color: "#ff3b30"; font.pixelSize: 8; font.family: "Courier New"; width: 28 }
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }

                                // --- TRI-MODE ANALOG COMPRESSOR DECK ---
                                Rectangle {
                                    Layout.fillWidth: true
                                    implicitHeight: 215
                                    color: "#101216"
                                    radius: 8
                                    border.color: "#252b36"
                                    border.width: 1

                                    ColumnLayout {
                                        anchors.fill: parent
                                        anchors.margins: 10
                                        spacing: 6

                                        RowLayout {
                                            Layout.fillWidth: true
                                            Text { text: "TRI-MODE BROADCAST COMPRESSOR"; color: "#8a8d98"; font.pixelSize: 9; font.bold: true }
                                            Item { Layout.fillWidth: true }
                                            Button {
                                                text: audioCore.channelCompBypasses[rightPanel.selectedChannel] ? "BYPASSED" : "ACTIVE"
                                                implicitWidth: 55; implicitHeight: 16
                                                background: Rectangle { color: audioCore.channelCompBypasses[rightPanel.selectedChannel] ? "#ff3b30" : "#11261d"; radius: 3 }
                                                contentItem: Text { text: parent.text; color: "#ffffff"; font.pixelSize: 7; font.bold: true; anchors.centerIn: parent }
                                                onClicked: audioCore.updateChannelCompressor(rightPanel.selectedChannel, audioCore.channelCompThresholds[rightPanel.selectedChannel], audioCore.channelCompRatios[rightPanel.selectedChannel], audioCore.channelCompMakeups[rightPanel.selectedChannel], audioCore.channelCompAttacks[rightPanel.selectedChannel], audioCore.channelCompReleases[rightPanel.selectedChannel], audioCore.channelCompModes[rightPanel.selectedChannel], !audioCore.channelCompBypasses[rightPanel.selectedChannel])
                                            }
                                        }

                                        RowLayout {
                                            spacing: 4
                                            Repeater {
                                                model: ["VCA (SLEEK)", "FET (FAST)", "OPTO (SMOOTH)"]
                                                delegate: Button {
                                                    text: modelData
                                                    implicitWidth: 80; implicitHeight: 18
                                                    background: Rectangle {
                                                        color: audioCore.channelCompModes[rightPanel.selectedChannel] === index ? "#ff9500" : "#1a1f29"
                                                        radius: 4
                                                    }
                                                    contentItem: Text {
                                                        text: parent.text
                                                        color: audioCore.channelCompModes[rightPanel.selectedChannel] === index ? "#0a0c10" : "#8a8d98"
                                                        font.pixelSize: 7; font.bold: true; anchors.centerIn: parent
                                                    }
                                                    onClicked: audioCore.updateChannelCompressor(rightPanel.selectedChannel, audioCore.channelCompThresholds[rightPanel.selectedChannel], audioCore.channelCompRatios[rightPanel.selectedChannel], audioCore.channelCompMakeups[rightPanel.selectedChannel], audioCore.channelCompAttacks[rightPanel.selectedChannel], audioCore.channelCompReleases[rightPanel.selectedChannel], index, audioCore.channelCompBypasses[rightPanel.selectedChannel])
                                                }
                                            }
                                        }

                                        // Threshold
                                        RowLayout {
                                            Layout.fillWidth: true; spacing: 8
                                            Text { text: "THRESH"; color: "#8a8d98"; font.pixelSize: 8; width: 40 }
                                            PremiumSlider {
                                                Layout.fillWidth: true; accentColor: "#ff9500"
                                                from: -60.0; to: 0.0
                                                value: audioCore.channelCompThresholds[rightPanel.selectedChannel]
                                                onMoved: audioCore.updateChannelCompressor(rightPanel.selectedChannel, value, audioCore.channelCompRatios[rightPanel.selectedChannel], audioCore.channelCompMakeups[rightPanel.selectedChannel], audioCore.channelCompAttacks[rightPanel.selectedChannel], audioCore.channelCompReleases[rightPanel.selectedChannel], audioCore.channelCompModes[rightPanel.selectedChannel], audioCore.channelCompBypasses[rightPanel.selectedChannel])
                                            }
                                            Text { text: Math.round(audioCore.channelCompThresholds[rightPanel.selectedChannel]) + "dB"; color: "#ff9500"; font.pixelSize: 8; font.family: "Courier New"; width: 35 }
                                        }

                                        // Ratio
                                        RowLayout {
                                            Layout.fillWidth: true; spacing: 8
                                            Text { text: "RATIO"; color: "#8a8d98"; font.pixelSize: 8; width: 40 }
                                            PremiumSlider {
                                                Layout.fillWidth: true; accentColor: "#ff9500"
                                                from: 1.0; to: 20.0
                                                value: audioCore.channelCompRatios[rightPanel.selectedChannel]
                                                onMoved: audioCore.updateChannelCompressor(rightPanel.selectedChannel, audioCore.channelCompThresholds[rightPanel.selectedChannel], value, audioCore.channelCompMakeups[rightPanel.selectedChannel], audioCore.channelCompAttacks[rightPanel.selectedChannel], audioCore.channelCompReleases[rightPanel.selectedChannel], audioCore.channelCompModes[rightPanel.selectedChannel], audioCore.channelCompBypasses[rightPanel.selectedChannel])
                                            }
                                            Text { text: audioCore.channelCompRatios[rightPanel.selectedChannel].toFixed(1) + ":1"; color: "#ff9500"; font.pixelSize: 8; font.family: "Courier New"; width: 35 }
                                        }

                                        // Makeup
                                        RowLayout {
                                            Layout.fillWidth: true; spacing: 8
                                            Text { text: "MAKEUP"; color: "#8a8d98"; font.pixelSize: 8; width: 40 }
                                            PremiumSlider {
                                                Layout.fillWidth: true; accentColor: "#ff9500"
                                                from: 0.0; to: 24.0
                                                value: audioCore.channelCompMakeups[rightPanel.selectedChannel]
                                                onMoved: audioCore.updateChannelCompressor(rightPanel.selectedChannel, audioCore.channelCompThresholds[rightPanel.selectedChannel], audioCore.channelCompRatios[rightPanel.selectedChannel], value, audioCore.channelCompAttacks[rightPanel.selectedChannel], audioCore.channelCompReleases[rightPanel.selectedChannel], audioCore.channelCompModes[rightPanel.selectedChannel], audioCore.channelCompBypasses[rightPanel.selectedChannel])
                                            }
                                            Text { text: Math.round(audioCore.channelCompMakeups[rightPanel.selectedChannel]) + "dB"; color: "#ff9500"; font.pixelSize: 8; font.family: "Courier New"; width: 35 }
                                        }

                                        // Attack / Release Row
                                        RowLayout {
                                            Layout.fillWidth: true; spacing: 12
                                            RowLayout {
                                                Layout.fillWidth: true; spacing: 4
                                                Text { text: "ATTACK"; color: "#8a8d98"; font.pixelSize: 8; width: 35 }
                                                PremiumSlider {
                                                    Layout.fillWidth: true; accentColor: "#ff9500"
                                                    from: 0.1; to: 200.0
                                                    value: audioCore.channelCompAttacks[rightPanel.selectedChannel]
                                                    onMoved: audioCore.updateChannelCompressor(rightPanel.selectedChannel, audioCore.channelCompThresholds[rightPanel.selectedChannel], audioCore.channelCompRatios[rightPanel.selectedChannel], audioCore.channelCompMakeups[rightPanel.selectedChannel], value, audioCore.channelCompReleases[rightPanel.selectedChannel], audioCore.channelCompModes[rightPanel.selectedChannel], audioCore.channelCompBypasses[rightPanel.selectedChannel])
                                                }
                                                Text { text: audioCore.channelCompAttacks[rightPanel.selectedChannel].toFixed(1) + "ms"; color: "#ff9500"; font.pixelSize: 8; font.family: "Courier New"; width: 45 }
                                            }
                                            RowLayout {
                                                Layout.fillWidth: true; spacing: 4
                                                Text { text: "RELEASE"; color: "#8a8d98"; font.pixelSize: 8; width: 45 }
                                                PremiumSlider {
                                                    Layout.fillWidth: true; accentColor: "#ff9500"
                                                    from: 10.0; to: 1000.0
                                                    value: audioCore.channelCompReleases[rightPanel.selectedChannel]
                                                    onMoved: audioCore.updateChannelCompressor(rightPanel.selectedChannel, audioCore.channelCompThresholds[rightPanel.selectedChannel], audioCore.channelCompRatios[rightPanel.selectedChannel], audioCore.channelCompMakeups[rightPanel.selectedChannel], audioCore.channelCompAttacks[rightPanel.selectedChannel], value, audioCore.channelCompModes[rightPanel.selectedChannel], audioCore.channelCompBypasses[rightPanel.selectedChannel])
                                                }
                                                Text { text: Math.round(audioCore.channelCompReleases[rightPanel.selectedChannel]) + "ms"; color: "#ff9500"; font.pixelSize: 8; font.family: "Courier New"; width: 45 }
                                            }
                                        }
                                    }
                                }

                                // --- HYSTERESIS SIDECHAIN NOISE GATE DECK ---
                                Rectangle {
                                    Layout.fillWidth: true
                                    implicitHeight: 180
                                    color: "#101216"
                                    radius: 8
                                    border.color: "#252b36"
                                    border.width: 1

                                    ColumnLayout {
                                        anchors.fill: parent
                                        anchors.margins: 10
                                        spacing: 6

                                        RowLayout {
                                            Layout.fillWidth: true
                                            Text { text: "HYSTERESIS SIDECHAIN GATE"; color: "#8a8d98"; font.pixelSize: 9; font.bold: true }
                                            Item { Layout.fillWidth: true }
                                            Button {
                                                text: audioCore.channelGateBypasses[rightPanel.selectedChannel] ? "BYPASSED" : "ACTIVE"
                                                implicitWidth: 55; implicitHeight: 16
                                                background: Rectangle { color: audioCore.channelGateBypasses[rightPanel.selectedChannel] ? "#ff3b30" : "#11261d"; radius: 3 }
                                                contentItem: Text { text: parent.text; color: "#ffffff"; font.pixelSize: 7; font.bold: true; anchors.centerIn: parent }
                                                onClicked: audioCore.updateChannelGate(rightPanel.selectedChannel, audioCore.channelGateThresholds[rightPanel.selectedChannel], audioCore.channelGateRanges[rightPanel.selectedChannel], audioCore.channelGateAttacks[rightPanel.selectedChannel], audioCore.channelGateReleases[rightPanel.selectedChannel], audioCore.channelGateHolds[rightPanel.selectedChannel], !audioCore.channelGateBypasses[rightPanel.selectedChannel])
                                            }
                                        }

                                        // Threshold
                                        RowLayout {
                                            Layout.fillWidth: true; spacing: 8
                                            Text { text: "THRESH"; color: "#8a8d98"; font.pixelSize: 8; width: 40 }
                                            PremiumSlider {
                                                Layout.fillWidth: true; accentColor: "#00e5ff"
                                                from: -80.0; to: 0.0
                                                value: audioCore.channelGateThresholds[rightPanel.selectedChannel]
                                                onMoved: audioCore.updateChannelGate(rightPanel.selectedChannel, value, audioCore.channelGateRanges[rightPanel.selectedChannel], audioCore.channelGateAttacks[rightPanel.selectedChannel], audioCore.channelGateReleases[rightPanel.selectedChannel], audioCore.channelGateHolds[rightPanel.selectedChannel], audioCore.channelGateBypasses[rightPanel.selectedChannel])
                                            }
                                            Text { text: Math.round(audioCore.channelGateThresholds[rightPanel.selectedChannel]) + "dB"; color: "#00e5ff"; font.pixelSize: 8; font.family: "Courier New"; width: 35 }
                                        }

                                        // Range
                                        RowLayout {
                                            Layout.fillWidth: true; spacing: 8
                                            Text { text: "RANGE"; color: "#8a8d98"; font.pixelSize: 8; width: 40 }
                                            PremiumSlider {
                                                Layout.fillWidth: true; accentColor: "#00e5ff"
                                                from: -80.0; to: 0.0
                                                value: audioCore.channelGateRanges[rightPanel.selectedChannel]
                                                onMoved: audioCore.updateChannelGate(rightPanel.selectedChannel, audioCore.channelGateThresholds[rightPanel.selectedChannel], value, audioCore.channelGateAttacks[rightPanel.selectedChannel], audioCore.channelGateReleases[rightPanel.selectedChannel], audioCore.channelGateHolds[rightPanel.selectedChannel], audioCore.channelGateBypasses[rightPanel.selectedChannel])
                                            }
                                            Text { text: Math.round(audioCore.channelGateRanges[rightPanel.selectedChannel]) + "dB"; color: "#00e5ff"; font.pixelSize: 8; font.family: "Courier New"; width: 35 }
                                        }

                                        RowLayout {
                                            Layout.fillWidth: true; spacing: 12
                                            RowLayout {
                                                Layout.fillWidth: true; spacing: 4
                                                Text { text: "ATTACK"; color: "#8a8d98"; font.pixelSize: 8; width: 35 }
                                                PremiumSlider {
                                                    Layout.fillWidth: true; accentColor: "#00e5ff"
                                                    from: 0.1; to: 100.0
                                                    value: audioCore.channelGateAttacks[rightPanel.selectedChannel]
                                                    onMoved: audioCore.updateChannelGate(rightPanel.selectedChannel, audioCore.channelGateThresholds[rightPanel.selectedChannel], audioCore.channelGateRanges[rightPanel.selectedChannel], value, audioCore.channelGateReleases[rightPanel.selectedChannel], audioCore.channelGateHolds[rightPanel.selectedChannel], audioCore.channelGateBypasses[rightPanel.selectedChannel])
                                                }
                                                Text { text: audioCore.channelGateAttacks[rightPanel.selectedChannel].toFixed(1) + "ms"; color: "#00e5ff"; font.pixelSize: 8; font.family: "Courier New"; width: 40 }
                                            }
                                            RowLayout {
                                                Layout.fillWidth: true; spacing: 4
                                                Text { text: "RELEASE"; color: "#8a8d98"; font.pixelSize: 8; width: 45 }
                                                PremiumSlider {
                                                    Layout.fillWidth: true; accentColor: "#00e5ff"
                                                    from: 10.0; to: 2000.0
                                                    value: audioCore.channelGateReleases[rightPanel.selectedChannel]
                                                    onMoved: audioCore.updateChannelGate(rightPanel.selectedChannel, audioCore.channelGateThresholds[rightPanel.selectedChannel], audioCore.channelGateRanges[rightPanel.selectedChannel], audioCore.channelGateAttacks[rightPanel.selectedChannel], value, audioCore.channelGateHolds[rightPanel.selectedChannel], audioCore.channelGateBypasses[rightPanel.selectedChannel])
                                                }
                                                Text { text: Math.round(audioCore.channelGateReleases[rightPanel.selectedChannel]) + "ms"; color: "#00e5ff"; font.pixelSize: 8; font.family: "Courier New"; width: 45 }
                                            }
                                            RowLayout {
                                                Layout.fillWidth: true; spacing: 4
                                                Text { text: "HOLD"; color: "#8a8d98"; font.pixelSize: 8; width: 25 }
                                                PremiumSlider {
                                                    Layout.fillWidth: true; accentColor: "#00e5ff"
                                                    from: 5.0; to: 1000.0
                                                    value: audioCore.channelGateHolds[rightPanel.selectedChannel]
                                                    onMoved: audioCore.updateChannelGate(rightPanel.selectedChannel, audioCore.channelGateThresholds[rightPanel.selectedChannel], audioCore.channelGateRanges[rightPanel.selectedChannel], audioCore.channelGateAttacks[rightPanel.selectedChannel], audioCore.channelGateReleases[rightPanel.selectedChannel], value, audioCore.channelGateBypasses[rightPanel.selectedChannel])
                                                }
                                                Text { text: Math.round(audioCore.channelGateHolds[rightPanel.selectedChannel]) + "ms"; color: "#00e5ff"; font.pixelSize: 8; font.family: "Courier New"; width: 40 }
                                            }
                                        }
                                    }
                                }

                                // --- SAFETY BRICKWALL LIMITER DECK ---
                                Rectangle {
                                    Layout.fillWidth: true
                                    implicitHeight: 65
                                    color: "#1a0d0d"
                                    radius: 8
                                    border.color: "#3d1414"
                                    border.width: 1

                                    ColumnLayout {
                                        anchors.fill: parent
                                        anchors.margins: 10
                                        spacing: 4

                                        RowLayout {
                                            Layout.fillWidth: true
                                            Text { text: "ZERO-LATENCY SAFETY CEILING LIMITER"; color: "#ff5e5e"; font.pixelSize: 9; font.bold: true }
                                            Item { Layout.fillWidth: true }
                                            Button {
                                                text: audioCore.channelLimiterBypasses[rightPanel.selectedChannel] ? "BYPASSED" : "ACTIVE"
                                                implicitWidth: 55; implicitHeight: 16
                                                background: Rectangle { color: audioCore.channelLimiterBypasses[rightPanel.selectedChannel] ? "#ff3b30" : "#5c1111"; radius: 3 }
                                                contentItem: Text { text: parent.text; color: "#ffffff"; font.pixelSize: 7; font.bold: true; anchors.centerIn: parent }
                                                onClicked: audioCore.updateChannelLimiter(rightPanel.selectedChannel, audioCore.channelLimiterThresholds[rightPanel.selectedChannel], !audioCore.channelLimiterBypasses[rightPanel.selectedChannel])
                                            }
                                        }

                                        RowLayout {
                                            Layout.fillWidth: true; spacing: 8
                                            Text { text: "CEILING"; color: "#ff8585"; font.pixelSize: 8; width: 40 }
                                            PremiumSlider {
                                                Layout.fillWidth: true; accentColor: "#ff3b30"
                                                from: -12.0; to: 0.0
                                                value: audioCore.channelLimiterThresholds[rightPanel.selectedChannel]
                                                onMoved: audioCore.updateChannelLimiter(rightPanel.selectedChannel, value, audioCore.channelLimiterBypasses[rightPanel.selectedChannel])
                                            }
                                            Text { text: audioCore.channelLimiterThresholds[rightPanel.selectedChannel].toFixed(1) + "dBFS"; color: "#ff5e5e"; font.pixelSize: 8; font.family: "Courier New"; width: 45 }
                                        }
                                    }
                                }
                            }

                        }

                    }

                    // Tab 3 Content: Audio Patch Board Matrix
                    ScrollView {
                        id: patchBoardScrollView
                        property int patchSubTab: 0 // 0 = Input Patch, 1 = Routing, 2 = Output Patch
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        visible: rightPanel.activeTab === 3
                        clip: true

                        ColumnLayout {
                            width: Math.max(rightPanel.width - 25, implicitWidth)
                            spacing: 12

                            Text {
                                text: "AUDIO PATCH MATRIX & ROUTING"
                                color: "#00BDD6"
                                font.pixelSize: 11
                                font.bold: true
                                Layout.fillWidth: true
                            }


                            // --- SUB-TAB SWITCHER NAVIGATION BAR ---
                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 4
                                height: 26

                                Repeater {
                                    model: ["1. INPUT PATCH", "2. INTERNAL ROUTING", "3. OUTPUT PATCH"]
                                    delegate: Button {
                                        Layout.fillWidth: true
                                        implicitHeight: 24
                                        text: modelData
                                        
                                        background: Rectangle {
                                            color: patchBoardScrollView.patchSubTab === index ? "#004F58" : "#1a1c1e"
                                            border.color: patchBoardScrollView.patchSubTab === index ? "#00BDD6" : "#252b36"
                                            border.width: 1
                                            radius: 4
                                        }
                                        contentItem: Text {
                                            text: parent.text
                                            color: patchBoardScrollView.patchSubTab === index ? "#00BDD6" : "#8a8d98"
                                            font.pixelSize: 8
                                            font.bold: true
                                            anchors.centerIn: parent
                                        }
                                        onClicked: {
                                            patchBoardScrollView.patchSubTab = index;
                                        }
                                    }
                                }
                            }

                            // --- INPUT PATCH PANEL ---
                            Rectangle {
                                id: inputPatchPanel
                                visible: patchBoardScrollView.patchSubTab === 0
                                Layout.fillWidth: true
                                implicitWidth: inputPatchLayout.implicitWidth + 24
                                implicitHeight: inputPatchLayout.implicitHeight + 24
                                color: "#0a0c10"
                                radius: 8
                                border.color: "#252b36"
                                border.width: 1

                                // Cached lists for delegates
                                property var deviceNamesList: audioCore.captureDevices ? audioCore.captureDevices.map(function(d) { return d.deviceName; }) : []
                                property var availableProcessesList: audioCore.availableProcesses ? Object.keys(audioCore.availableProcesses) : []

                                ColumnLayout {
                                    id: inputPatchLayout
                                    anchors.fill: parent
                                    anchors.margins: 12
                                    spacing: 8

                                    Text {
                                        text: "CONSOLE CHANNEL INPUT PATCHING"
                                        color: "#8a8d98"
                                        font.pixelSize: 9
                                        font.bold: true
                                    }

                                    Repeater {
                                        model: 24
                                        delegate: RowLayout {
                                            spacing: 6
                                            Layout.fillWidth: true
                                            property int channelIdx: index
                                            
                                            // Channel Label (CH 1..24)
                                            Rectangle {
                                                width: 36; height: 24
                                                color: "#1a1c1e"
                                                radius: 4
                                                border.color: "#252b36"
                                                Text {
                                                    anchors.centerIn: parent
                                                    text: "CH " + (channelIdx + 1)
                                                    color: "#00BDD6"
                                                    font.pixelSize: 9
                                                    font.bold: true
                                                }
                                            }
                                            
                                            // Channel Name
                                            Text {
                                                text: "Channel " + (channelIdx + 1)
                                                color: "#f8fafc"
                                                font.pixelSize: 10
                                                Layout.preferredWidth: 70
                                            }
                                            
                                            // Source Type ComboBox
                                            ComboBox {
                                                id: srcTypeCombo
                                                implicitHeight: 24
                                                Layout.preferredWidth: 115
                                                model: ["Unpatched", "ASIO Hardware", "Test Generator", "App Capture"]
                                                
                                                currentIndex: {
                                                    if (audioCore.inputPatches && audioCore.inputPatches[channelIdx] !== undefined) {
                                                        return audioCore.inputPatches[channelIdx].type;
                                                    }
                                                    return 0;
                                                }
                                                
                                                onActivated: {
                                                    var newType = index;
                                                    var oldType = (audioCore.inputPatches && audioCore.inputPatches[channelIdx] !== undefined) ? audioCore.inputPatches[channelIdx].type : 0;
                                                    if (oldType === 3 && newType !== 3) {
                                                        audioCore.stopApplicationCapture(channelIdx);
                                                    }
                                                    
                                                    if (newType === 3) {
                                                        if (audioCore.availableProcesses) {
                                                            var processes = inputPatchPanel.availableProcessesList;
                                                            if (processes.length > 0) {
                                                                var procName = processes[0];
                                                                var pid = audioCore.availableProcesses[procName];
                                                                audioCore.setInputPatch(channelIdx, 3, pid);
                                                                audioCore.startApplicationCapture(channelIdx, procName, pid);
                                                            } else {
                                                                audioCore.setInputPatch(channelIdx, 3, 0);
                                                            }
                                                        } else {
                                                            audioCore.setInputPatch(channelIdx, 3, 0);
                                                        }
                                                    } else if (newType === 1) {
                                                        audioCore.setInputPatch(channelIdx, 1, 0); // Default to device 0, channel 0
                                                    } else {
                                                        audioCore.setInputPatch(channelIdx, newType, 0);
                                                    }
                                                }
                                            }
                                            
                                            // --- HARDWARE DEVICE SELECTION (Visible only for type 1) ---
                                            ComboBox {
                                                id: hwDeviceCombo
                                                implicitHeight: 24
                                                Layout.preferredWidth: 135
                                                visible: srcTypeCombo.currentIndex === 1
                                                
                                                model: inputPatchPanel.deviceNamesList
                                                
                                                currentIndex: {
                                                    if (audioCore.inputPatches && audioCore.inputPatches[channelIdx] !== undefined) {
                                                        var patch = audioCore.inputPatches[channelIdx];
                                                        if (patch.type === 1) {
                                                            var devIdx = patch.index >> 8;
                                                            if (audioCore.captureDevices && devIdx >= 0 && devIdx < audioCore.captureDevices.length) {
                                                                return devIdx;
                                                            }
                                                        }
                                                    }
                                                    return 0;
                                                }
                                                
                                                onActivated: {
                                                    if (audioCore.captureDevices && audioCore.captureDevices.length > 0) {
                                                        var devIdx = index;
                                                        var dev = audioCore.captureDevices[devIdx];
                                                        var maxChannels = dev ? dev.channels : 2;
                                                        var chIdx = hwChannelCombo.currentIndex;
                                                        if (chIdx >= maxChannels) {
                                                            chIdx = 0;
                                                        }
                                                        var patchIdx = (devIdx << 8) | chIdx;
                                                        audioCore.setInputPatch(channelIdx, 1, patchIdx);
                                                    }
                                                }
                                            }
                                            
                                            // --- HARDWARE CHANNEL SELECTION (Visible only for type 1) ---
                                            ComboBox {
                                                id: hwChannelCombo
                                                implicitHeight: 24
                                                Layout.preferredWidth: 75
                                                visible: srcTypeCombo.currentIndex === 1
                                                
                                                model: {
                                                    var devIdx = hwDeviceCombo.currentIndex;
                                                    if (audioCore.captureDevices && devIdx >= 0 && devIdx < audioCore.captureDevices.length) {
                                                        var dev = audioCore.captureDevices[devIdx];
                                                        var count = dev ? dev.channels : 2;
                                                        var list = [];
                                                        for (var i = 0; i < count; ++i) {
                                                            list.push("Input " + (i + 1));
                                                        }
                                                        return list;
                                                    }
                                                    return ["Input 1", "Input 2"];
                                                }
                                                
                                                currentIndex: {
                                                    if (audioCore.inputPatches && audioCore.inputPatches[channelIdx] !== undefined) {
                                                        var patch = audioCore.inputPatches[channelIdx];
                                                        if (patch.type === 1) {
                                                            return patch.index & 0xFF;
                                                        }
                                                    }
                                                    return 0;
                                                }
                                                
                                                onActivated: {
                                                    if (audioCore.captureDevices && audioCore.captureDevices.length > 0) {
                                                        var devIdx = hwDeviceCombo.currentIndex;
                                                        var chIdx = index;
                                                        var patchIdx = (devIdx << 8) | chIdx;
                                                        audioCore.setInputPatch(channelIdx, 1, patchIdx);
                                                    }
                                                }
                                            }
                                            
                                            // --- TEST GENERATOR SELECTION (Visible only for type 2) ---
                                            ComboBox {
                                                id: generatorCombo
                                                implicitHeight: 24
                                                Layout.preferredWidth: 135
                                                visible: srcTypeCombo.currentIndex === 2
                                                model: ["1kHz Sine Wave", "Pink Noise"]
                                                
                                                currentIndex: {
                                                    if (audioCore.inputPatches && audioCore.inputPatches[channelIdx] !== undefined) {
                                                        var patch = audioCore.inputPatches[channelIdx];
                                                        if (patch.type === 2) {
                                                            return patch.index;
                                                        }
                                                    }
                                                    return 0;
                                                }
                                                
                                                onActivated: {
                                                    audioCore.setInputPatch(channelIdx, 2, index);
                                                }
                                            }
                                            
                                            // --- APP CAPTURE SELECTION (Visible only for type 3) ---
                                            ComboBox {
                                                id: appCaptureCombo
                                                implicitHeight: 24
                                                Layout.preferredWidth: 210
                                                visible: srcTypeCombo.currentIndex === 3
                                                
                                                model: inputPatchPanel.availableProcessesList
                                                
                                                currentIndex: {
                                                    if (audioCore.inputPatches && audioCore.inputPatches[channelIdx] !== undefined) {
                                                        var patch = audioCore.inputPatches[channelIdx];
                                                        if (patch.type === 3 && audioCore.availableProcesses) {
                                                            var processes = inputPatchPanel.availableProcessesList;
                                                            for (var i = 0; i < processes.length; i++) {
                                                                if (audioCore.availableProcesses[processes[i]] === patch.index) {
                                                                    return i;
                                                                }
                                                            }
                                                        }
                                                    }
                                                    return -1;
                                                }
                                                
                                                onActivated: {
                                                    if (audioCore.availableProcesses) {
                                                        var processes = inputPatchPanel.availableProcessesList;
                                                        if (index >= 0 && index < processes.length) {
                                                            var procName = processes[index];
                                                            var pid = audioCore.availableProcesses[procName];
                                                            audioCore.setInputPatch(channelIdx, 3, pid);
                                                            audioCore.startApplicationCapture(channelIdx, procName, pid);
                                                        }
                                                    }
                                                }
                                            }
                                            
                                            // PID Info for App Capture
                                            Text {
                                                Layout.fillWidth: true
                                                text: {
                                                    if (srcTypeCombo.currentIndex === 3 && audioCore.availableProcesses) {
                                                        var processes = inputPatchPanel.availableProcessesList;
                                                        var selIdx = appCaptureCombo.currentIndex;
                                                        if (selIdx >= 0 && selIdx < processes.length) {
                                                            var procName = processes[selIdx];
                                                            var pid = audioCore.availableProcesses[procName];
                                                            return "PID: " + pid;
                                                        }
                                                    }
                                                    return "";
                                                }
                                                color: "#8a8d98"
                                                font.pixelSize: 9
                                                font.family: "Courier New"
                                            }
                                        }
                                    }
                                }
                            }

                            // --- INTERNAL ROUTING MATRIX ---
                            Rectangle {
                                visible: patchBoardScrollView.patchSubTab === 1
                                Layout.fillWidth: true
                                implicitWidth: routingMatrixLayout.implicitWidth + 24
                                implicitHeight: routingMatrixLayout.implicitHeight + 24
                                color: "#0a0c10"
                                radius: 8
                                border.color: "#252b36"
                                border.width: 1

                                ColumnLayout {
                                    id: routingMatrixLayout
                                    anchors.fill: parent
                                    anchors.margins: 12
                                    spacing: 6

                                    Text {
                                        text: "CONSOLE INTERNAL ROUTING GRID MATRIX"
                                        color: "#8a8d98"
                                        font.pixelSize: 9
                                        font.bold: true
                                    }

                                    // Column Headers (Destinations)
                                    RowLayout {
                                        Layout.fillWidth: true
                                        spacing: 1

                                        // Corner Spacer
                                        Rectangle {
                                            width: 80; height: 35
                                            color: "#101216"
                                            radius: 4
                                            Text {
                                                text: "CH \\ DEST"
                                                color: "#00BDD6"
                                                font.pixelSize: 8
                                                font.bold: true
                                                anchors.centerIn: parent
                                            }
                                        }

                                        // Column Header Labels (8 summing paths + 8 DCAs)
                                        Repeater {
                                            model: [
                                                { name: "MST L", cat: "BUS" },
                                                { name: "MST R", cat: "BUS" },
                                                { name: "AUX 1", cat: "BUS" },
                                                { name: "AUX 2", cat: "BUS" },
                                                { name: "AUX 3", cat: "BUS" },
                                                { name: "AUX 4", cat: "BUS" },
                                                { name: "REC L", cat: "BUS" },
                                                { name: "REC R", cat: "BUS" },
                                                { name: "DCA 1", cat: "DCA" },
                                                { name: "DCA 2", cat: "DCA" },
                                                { name: "DCA 3", cat: "DCA" },
                                                { name: "DCA 4", cat: "DCA" },
                                                { name: "DCA 5", cat: "DCA" },
                                                { name: "DCA 6", cat: "DCA" },
                                                { name: "DCA 7", cat: "DCA" },
                                                { name: "DCA 8", cat: "DCA" }
                                            ]
                                            delegate: Rectangle {
                                                width: 24; height: 35
                                                color: "#14171a"
                                                radius: 3
                                                border.color: "#252b36"
                                                border.width: 1

                                                ColumnLayout {
                                                    anchors.fill: parent
                                                    anchors.margins: 2
                                                    spacing: 1
                                                    
                                                    Text {
                                                        text: modelData.cat
                                                        color: modelData.cat === "BUS" ? "#00BDD6" : "#E040FB"
                                                        font.pixelSize: 6
                                                        font.bold: true
                                                        Layout.alignment: Qt.AlignHCenter
                                                    }
                                                    Text {
                                                        text: modelData.name
                                                        color: "#ffffff"
                                                        font.pixelSize: 7
                                                        font.bold: true
                                                        Layout.alignment: Qt.AlignHCenter
                                                    }
                                                }
                                            }
                                        }
                                    }

                                    // Matrix Rows (24 Console Channels)
                                    Repeater {
                                        model: 24
                                        delegate: RowLayout {
                                            spacing: 1
                                            Layout.fillWidth: true
                                            property int rIdx: index

                                            // Row Label
                                            Rectangle {
                                                width: 80; height: 18
                                                color: "#101216"
                                                radius: 3
                                                Text {
                                                    text: "CH " + (rIdx + 1)
                                                    color: "#a0a5b0"
                                                    font.pixelSize: 8
                                                    anchors.left: parent.left
                                                    anchors.leftMargin: 6
                                                    anchors.verticalCenter: parent.verticalCenter
                                                }
                                            }

                                            // 16 Cells (8 Buses + 8 DCAs)
                                            Repeater {
                                                model: 16
                                                delegate: Rectangle {
                                                    width: 24; height: 18
                                                    color: cellMouseArea.containsMouse ? "#1e222b" : "#0f1011"
                                                    border.color: "#1c1f22"
                                                    border.width: 1
                                                    radius: 2

                                                    property int cIdx: index
                                                    property bool isBus: cIdx < 8
                                                    property int dcaIdx: cIdx - 8
                                                    property bool isRouteActive: isBus ? sandboxWin.checkRouteActive(rIdx, cIdx) : ((audioCore.channelDcaMasks[rIdx] & (1 << dcaIdx)) !== 0)
                                                    property int tapPoint: isBus ? sandboxWin.getRouteTap(rIdx, cIdx) : 0

                                                    Rectangle {
                                                        width: 6; height: 6
                                                        radius: 3
                                                        anchors.centerIn: parent
                                                        visible: parent.isRouteActive
                                                        color: {
                                                            if (parent.isBus) {
                                                                return parent.tapPoint === 0 ? "#00BDD6" : (parent.tapPoint === 1 ? "#ffb300" : "#00E676");
                                                            } else {
                                                                return "#E040FB"; // Magenta
                                                            }
                                                        }
                                                    }

                                                    MouseArea {
                                                        id: cellMouseArea
                                                        anchors.fill: parent
                                                        hoverEnabled: true
                                                        onClicked: {
                                                            if (parent.isBus) {
                                                                sandboxWin.toggleRoute(rIdx, parent.cIdx);
                                                            } else {
                                                                var active = parent.isRouteActive;
                                                                audioCore.updateChannelDCAMapping(rIdx, parent.dcaIdx, !active);
                                                            }
                                                        }
                                                        onDoubleClicked: {
                                                            if (parent.isBus) {
                                                                var pt = cellMouseArea.mapToItem(root.contentItem, cellMouseArea.width/2, cellMouseArea.height/2);
                                                                sandboxWin.openRouteEditor(rIdx, parent.cIdx, pt);
                                                            }
                                                        }
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }
                            }

                            // --- OUTPUT PATCH PANEL ---
                            Rectangle {
                                visible: patchBoardScrollView.patchSubTab === 2
                                Layout.fillWidth: true
                                implicitWidth: outputPatchLayout.implicitWidth + 24
                                implicitHeight: outputPatchLayout.implicitHeight + 24
                                color: "#0a0c10"
                                radius: 8
                                border.color: "#252b36"
                                border.width: 1

                                ColumnLayout {
                                    id: outputPatchLayout
                                    anchors.fill: parent
                                    anchors.margins: 12
                                    spacing: 8

                                    Text {
                                        text: "SUMMING BUS OUTPUT PATCHING"
                                        color: "#8a8d98"
                                        font.pixelSize: 9
                                        font.bold: true
                                    }

                                    Repeater {
                                        model: 8
                                        delegate: RowLayout {
                                            spacing: 12
                                            Layout.fillWidth: true
                                            property int busIdx: index
                                            property var busNames: ["Master L", "Master R", "Aux 1", "Aux 2", "Aux 3", "Aux 4", "Rec L", "Rec R"]

                                            // Label
                                            Rectangle {
                                                width: 120; height: 24
                                                color: "#1a1c1e"
                                                radius: 4
                                                border.color: "#252b36"
                                                Text {
                                                    anchors.centerIn: parent
                                                    text: busNames[busIdx]
                                                    color: "#00BDD6"
                                                    font.pixelSize: 9
                                                    font.bold: true
                                                }
                                            }

                                            // ComboBox
                                            ComboBox {
                                                id: patchedBusCombo
                                                implicitHeight: 24
                                                Layout.preferredWidth: 200
                                                model: ["Unpatched", "ASIO Output 1", "ASIO Output 2", "ASIO Output 3", "ASIO Output 4", "ASIO Output 5", "ASIO Output 6", "ASIO Output 7", "ASIO Output 8"]
                                                
                                                currentIndex: {
                                                    if (audioCore.outputPatches && audioCore.outputPatches[busIdx] !== undefined) {
                                                        var patch = audioCore.outputPatches[busIdx];
                                                        if (patch && patch.active) {
                                                            return patch.hwOutputIdx + 1;
                                                        }
                                                    }
                                                    return 0;
                                                }

                                                onActivated: {
                                                    var active = index > 0;
                                                    var hwOutputIdx = index - 1;
                                                    audioCore.setOutputPatch(busIdx, hwOutputIdx, active);
                                                }
                                            }

                                            Item { Layout.fillWidth: true }
                                        }
                                    }
                                }
                            }
                        }
                    }

                }

            }

        }

    }
    }
