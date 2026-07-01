import QtQuick

import QtQuick.Controls

import QtQuick.Layouts

import Overwatch.Core



Window {

    id: root

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

    
    visible: true

    width: 360

    height: 520

    title: "Overwatch Launcher Dashboard"

    color: "#0a0c10"

    x: 80

    y: 80



    // audioCore, showBuilder provided as context properties from main.cpp



    Connections {

        target: audioCore

        function onPatchesChanged() {
            activePatchesList = audioCore.getActivePatches();
        }

        

        function onUndoRestored(channelVols, channelMutes, masterVol, masterMute, programCam, previewCam, ftb) {

            channelVolumes = channelVols;

            channelMutes = channelMutes;

            masterVolume = masterVol;

            masterMute = masterMute;

            programCameraIdx = programCam;

            previewCameraIdx = previewCam;

            audioCore.fadeToBlack = ftb;

        }

        

        function onUndoStep(channelVols, masterVol) {

            channelVolumes = channelVols;

            masterVolume = masterVol;

        }



        function onChannelVolumeChanged(chIdx, volume) {

            var temp = channelVolumes;

            temp[chIdx] = volume;

            channelVolumes = temp;

        }



        function onChannelMuteChanged(chIdx, mute) {

            var temp = channelMutes;

            temp[chIdx] = mute;

            channelMutes = temp;

        }



        function onCueTriggered(cueIndex) {

            console.log("Stream Deck triggered cue: " + cueIndex);

            autoTransition();

        }

    }



    function logStateBeforeChange() {

        audioCore.captureUndoSnapshot(

            channelVolumes,

            channelMutes,

            masterVolume,

            masterMute,

            programCameraIdx,

            previewCameraIdx,

            audioCore.fadeToBlack

        );

    }



    // Window Visibility States

    property bool audioWindowOpen: false

    property bool videoWindowOpen: false

    property bool sandboxWindowOpen: false



    // 24-Channel Audio Mixer State

    property var activePatchesList: []


    property var channelVolumes: [

        1.0, 1.0, 1.0, 1.0,   1.0, 1.0, 1.0, 1.0,

        1.0, 1.0, 1.0, 1.0,   1.0, 1.0, 1.0, 1.0,

        1.0, 1.0, 1.0, 1.0,   1.0, 1.0, 1.0, 1.0

    ]

    property var channelMutes: [

        false, false, false, false,   false, false, false, false,

        false, false, false, false,   false, false, false, false,

        false, false, false, false,   false, false, false, false

    ]

    property var busVolumes: [ 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0 ]
    property var busMutes: [ false, false, false, false, false, false, false, false ]
    property var auxVolumes: [ 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0 ]
    property var auxMutes: [ false, false, false, false, false, false, false, false ]

    function getVolumeForFader(type, actualIdx) {
        if (type === "input") return channelVolumes[actualIdx];
        if (type === "dca") return audioCore.dcaVolumes[actualIdx];
        if (type === "bus") return busVolumes[actualIdx];
        if (type === "aux") return auxVolumes[actualIdx];
        return 1.0;
    }
    
    function getMuteForFader(type, actualIdx) {
        if (type === "input") return channelMutes[actualIdx];
        if (type === "dca") return audioCore.dcaMutes[actualIdx];
        if (type === "bus") return busMutes[actualIdx];
        if (type === "aux") return auxMutes[actualIdx];
        return false;
    }
    
    function setVolumeForFader(type, actualIdx, val) {
        if (type === "input") {
            setVolume(actualIdx, val);
        } else if (type === "dca") {
            audioCore.updateDCAVolume(actualIdx, val);
        } else if (type === "bus") {
            var temp = busVolumes;
            temp[actualIdx] = val;
            busVolumes = temp;
            audioCore.notifyFaderChanged(64 + actualIdx, val);
        } else if (type === "aux") {
            var temp = auxVolumes;
            temp[actualIdx] = val;
            auxVolumes = temp;
            audioCore.notifyFaderChanged(80 + actualIdx, val);
        }
    }
    
    function setMuteForFader(type, actualIdx, val) {
        if (type === "input") {
            setMute(actualIdx, val);
        } else if (type === "dca") {
            audioCore.updateMuteGroupState(actualIdx, val);
        } else if (type === "bus") {
            var temp = busMutes;
            temp[actualIdx] = val;
            busMutes = temp;
            audioCore.setChannelMuted(64 + actualIdx, val);
        } else if (type === "aux") {
            var temp = auxMutes;
            temp[actualIdx] = val;
            auxMutes = temp;
            audioCore.setChannelMuted(80 + actualIdx, val);
        }
    }

    property int activeBank: 0 // 0=Ch1-8, 1=Ch9-16, 2=Ch17-24, 3=DCA1-8, 4=ASSIGN LAYER

    property real masterVolume: 0.8

    property bool masterMute: false



    // Helper functions for updating arrays reactively

    function setVolume(index, val) {

        if (index === 24) { // Master index

            masterVolume = val;

            audioCore.faderVolume = val;

            return;

        }

        var temp = channelVolumes;

        temp[index] = val;

        channelVolumes = temp;

        

        // Notify C++ to push motorized fader feedback

        audioCore.notifyFaderChanged(index, val);

    }



    function checkRouteActive(src, dest) {
        for (var i = 0; i < activePatchesList.length; ++i) {
            if (activePatchesList[i].src === src && activePatchesList[i].dest === dest) {
                return true;
            }
        }
        return false;
    }

    function getRouteTap(src, dest) {
        for (var i = 0; i < activePatchesList.length; ++i) {
            if (activePatchesList[i].src === src && activePatchesList[i].dest === dest) {
                return activePatchesList[i].tap;
            }
        }
        return 2; // Default PostFader
    }

    function getRouteGain(src, dest) {
        for (var i = 0; i < activePatchesList.length; ++i) {
            if (activePatchesList[i].src === src && activePatchesList[i].dest === dest) {
                return activePatchesList[i].gain;
            }
        }
        return 1.0;
    }

    function toggleRoute(src, dest) {
        if (checkRouteActive(src, dest)) {
            audioCore.unpatchRoute(src, dest);
        } else {
            audioCore.patchRoute(src, dest, 1.0, 2); // default Post-Fader
        }
        activePatchesList = audioCore.getActivePatches();
    }

    // Properties for inline route editor popup
    property bool routeEditorOpen: false
    property int selectedRouteSrc: 0
    property int selectedRouteDest: 0
    property real selectedRouteGain: 1.0
    property int selectedRouteTap: 2
    property real popupX: 0
    property real popupY: 0

    function openRouteEditor(src, dest, pt) {
        selectedRouteSrc = src;
        selectedRouteDest = dest;
        selectedRouteGain = getRouteGain(src, dest);
        selectedRouteTap = getRouteTap(src, dest);
        popupX = pt.x + 30;
        popupY = pt.y - 40;
        routeEditorOpen = true;
    }

    function setMute(index, val) {

        if (index === 24) {

            masterMute = val;
            audioCore.setChannelMuted(24, val);

            return;

        }

        var temp = channelMutes;

        temp[index] = val;

        channelMutes = temp;
        audioCore.setChannelMuted(index, val);

    }



    // Switcher Camera Selection States

    property int programCameraIdx: 0

    property int previewCameraIdx: 1

    property real transitionPercent: 0.0



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

        target: root

        property: "transitionPercent"

        from: 0.0

        to: 1.0

        duration: 300

        onFinished: {

            cutTransition();

        }

    }



    // Pulse frame timer count for animated buttons

    property int m_frameCount: 0



    // ----------------------------------------------------

    // 1. MASTER LAUNCHER DASHBOARD WINDOW

    // ----------------------------------------------------

        ColumnLayout {

            anchors.fill: parent

            anchors.margins: 20

            spacing: 16



            // Header Section

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

                    text: "MASTER SETTINGS LAUNCHER"

                    color: "#8a8d98"

                    font.pixelSize: 8

                    font.letterSpacing: 1.5

                    Layout.alignment: Qt.AlignHCenter

                }

            }



            Rectangle {

                Layout.fillWidth: true

                height: 1

                color: "#252b36"

            }



            // Modules Selector Deck

            Text {

                text: "SYSTEM MODULE CONTROLS"

                color: "#8a8d98"

                font.pixelSize: 9

                font.bold: true

                font.letterSpacing: 1

            }



            ColumnLayout {

                spacing: 10

                Layout.fillWidth: true



                // Audio Console Module Toggle

                Rectangle {

                    Layout.fillWidth: true

                    height: 54

                    color: "#161920"

                    border.color: audioWindowOpen ? "#00d084" : "#252b36"

                    border.width: 1

                    radius: 8



                    RowLayout {

                        anchors.fill: parent

                        anchors.margins: 12

                        spacing: 12



                        Text {

                            text: "🔊"

                            font.pixelSize: 16

                        }



                        ColumnLayout {

                            spacing: 1

                            Text {

                                text: "Audio Touch Console"

                                color: "#ffffff"

                                font.pixelSize: 12

                                font.bold: true

                            }

                            Text {

                                text: "24-Channel Fader Bay"

                                color: "#8a8d98"

                                font.pixelSize: 9

                            }

                        }



                        Item { Layout.fillWidth: true }



                        // Sliding Switch representation

                        Rectangle {

                            width: 48

                            height: 24

                            radius: 12

                            color: audioWindowOpen ? "#00d084" : "#101216"

                            border.color: audioWindowOpen ? "#00d084" : "#252b36"

                            border.width: 1



                            Rectangle {

                                width: 20

                                height: 20

                                radius: 10

                                color: "#ffffff"

                                x: audioWindowOpen ? 26 : 2

                                y: 2

                                Behavior on x { NumberAnimation { duration: 150 } }

                            }



                            MouseArea {

                                anchors.fill: parent

                                onClicked: audioCore.toggleWindow("Audio Touch Console")

                            }

                        }

                    }

                }



                // Video Switcher Module Toggle

                Rectangle {

                    Layout.fillWidth: true

                    height: 54

                    color: "#161920"

                    border.color: videoWindowOpen ? "#00a0f0" : "#252b36"

                    border.width: 1

                    radius: 8



                    RowLayout {

                        anchors.fill: parent

                        anchors.margins: 12

                        spacing: 12



                        Text {

                            text: "📹"

                            font.pixelSize: 16

                        }



                        ColumnLayout {

                            spacing: 1

                            Text {

                                text: "GPU Video Switcher"

                                color: "#ffffff"

                                font.pixelSize: 12

                                font.bold: true

                            }

                            Text {

                                text: "Widescreen 4-Cam Switch"

                                color: "#8a8d98"

                                font.pixelSize: 9

                            }

                        }



                        Item { Layout.fillWidth: true }



                        Rectangle {

                            width: 48

                            height: 24

                            radius: 12

                            color: videoWindowOpen ? "#00a0f0" : "#101216"

                            border.color: videoWindowOpen ? "#00a0f0" : "#252b36"

                            border.width: 1



                            Rectangle {

                                width: 20

                                height: 20

                                radius: 10

                                color: "#ffffff"

                                x: videoWindowOpen ? 26 : 2

                                y: 2

                                Behavior on x { NumberAnimation { duration: 150 } }

                            }



                            MouseArea {

                                anchors.fill: parent

                                onClicked: audioCore.toggleWindow("Video Switcher Console")

                            }

                        }

                    }

                }



                // Show Control Sandbox Toggle

                Rectangle {

                    Layout.fillWidth: true

                    height: 54

                    color: "#161920"

                    border.color: sandboxWindowOpen ? "#f0b000" : "#252b36"

                    border.width: 1

                    radius: 8



                    RowLayout {

                        anchors.fill: parent

                        anchors.margins: 12

                        spacing: 12



                        Text {

                            text: "🛠️"

                            font.pixelSize: 16

                        }



                        ColumnLayout {

                            spacing: 1

                            Text {

                                text: "Show Builder Sandbox"

                                color: "#ffffff"

                                font.pixelSize: 12

                                font.bold: true

                            }

                            Text {

                                text: "Diagnostics & WAL Files"

                                color: "#8a8d98"

                                font.pixelSize: 9

                            }

                        }



                        Item { Layout.fillWidth: true }



                        Rectangle {

                            width: 48

                            height: 24

                            radius: 12

                            color: sandboxWindowOpen ? "#f0b000" : "#101216"

                            border.color: sandboxWindowOpen ? "#f0b000" : "#252b36"

                            border.width: 1



                            Rectangle {

                                width: 20

                                height: 20

                                radius: 10

                                color: "#ffffff"

                                x: sandboxWindowOpen ? 26 : 2

                                y: 2

                                Behavior on x { NumberAnimation { duration: 150 } }

                            }



                            MouseArea {

                                anchors.fill: parent

                                onClicked: audioCore.toggleWindow("Show Control Sandbox")

                            }

                        }

                    }

                }

            }



            Item { Layout.fillHeight: true }



            // Master Emergency Panic Section (Fade to Black / Global Mute)

            Button {

                id: panicButton

                Layout.fillWidth: true

                implicitHeight: 64

                checkable: true

                checked: audioCore.fadeToBlack



                background: Rectangle {

                    color: audioCore.fadeToBlack ? "#ff3b30" : "#1a1012"

                    border.color: "#ff3b30"

                    border.width: 2

                    radius: 8



                    Rectangle {

                        anchors.fill: parent

                        color: "#ff3b30"

                        opacity: audioCore.fadeToBlack ? 0.35 + 0.15 * Math.sin(root.m_frameCount * 0.15) : 0.04

                        radius: 8

                    }

                }



                contentItem: ColumnLayout {

                    spacing: 2

                    anchors.centerIn: parent

                    Text {

                        text: audioCore.fadeToBlack ? "🚨 FADE TO BLACK ACTIVE 🚨" : "EMERGENCY PANIC (FTB)"

                        color: audioCore.fadeToBlack ? "#ffffff" : "#ff3b30"

                        font.pixelSize: 12

                        font.bold: true

                        Layout.alignment: Qt.AlignHCenter

                    }

                    Text {

                        text: audioCore.fadeToBlack ? "GLOBAL AUDIO MUTE AND SCREEN BLACKOUT" : "ENGAGE FOR IMMEDIATE ZERO-ALLOCATION SHUTDOWN"

                        color: audioCore.fadeToBlack ? "#ffcccc" : "#8a8d98"

                        font.pixelSize: 7

                        Layout.alignment: Qt.AlignHCenter

                    }

                }



                onClicked: {

                    logStateBeforeChange();

                    audioCore.fadeToBlack = !audioCore.fadeToBlack;

                }

            }

        }



        Timer {

            interval: 50

            running: true

            repeat: true

            onTriggered: root.m_frameCount++

        }





    // Window position persistence
    WindowStateStore { id: winStore }

    Component.onCompleted: {
        var rect = winStore.restoreWindowGeometry("MasterLauncher", Qt.rect(80, 80, 360, 520));
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

    // --- INLINE ROUTE CONTROLLER POPUP ---
    Rectangle {
        id: routePopup
        width: 200
        height: 155
        color: "#1c1f25"
        border.color: "#00BDD6"
        border.width: 1.5
        radius: 8
        visible: root.routeEditorOpen
        x: root.popupX
        y: root.popupY
        z: 100

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 10
            spacing: 6

            RowLayout {
                Layout.fillWidth: true
                Text {
                    text: "EDIT ROUTE PIPELINE"
                    color: "#00BDD6"
                    font.pixelSize: 8
                    font.bold: true
                }
                Item { Layout.fillWidth: true }
                Text {
                    text: "×"
                    color: "#8a8d98"
                    font.pixelSize: 12
                    font.bold: true
                    MouseArea {
                        anchors.fill: parent
                        onClicked: root.routeEditorOpen = false
                    }
                }
            }

            Rectangle {
                Layout.fillWidth: true
                height: 1
                color: "#252b36"
            }

            RowLayout {
                Layout.fillWidth: true
                Text { text: "SOURCE: "; color: "#8a8d98"; font.pixelSize: 7; font.bold: true }
                Text {
                    text: root.selectedRouteSrc < 16 ? ("ASIO IN " + (root.selectedRouteSrc + 1)) : (root.selectedRouteSrc === 16 ? "1kHz SINE" : "PINK NOISE")
                    color: "#ffffff"
                    font.pixelSize: 7
                }
            }

            RowLayout {
                Layout.fillWidth: true
                Text { text: "DEST: "; color: "#8a8d98"; font.pixelSize: 7; font.bold: true }
                Text {
                    text: "SUM OUT " + (root.selectedRouteDest + 1)
                    color: "#ffffff"
                    font.pixelSize: 7
                }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 4
                Text { text: "TRIM"; color: "#8a8d98"; font.pixelSize: 7; font.bold: true; width: 25 }
                PremiumSlider {
                    id: trimSlider
                    Layout.fillWidth: true
                    from: 0.0
                    to: 2.0
                    accentColor: "#00E676"
                    value: root.selectedRouteGain
                    onMoved: {
                        root.selectedRouteGain = value;
                        audioCore.patchRoute(root.selectedRouteSrc, root.selectedRouteDest, value, root.selectedRouteTap);
                    }
                }
                Text {
                    text: (20 * Math.log10(root.selectedRouteGain + 0.0001)).toFixed(1) + " dB"
                    color: "#00E676"
                    font.pixelSize: 7
                    font.family: "Courier New"
                    width: 32
                }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 3
                
                Repeater {
                    model: ["Pre-EQ", "Pre-Fad", "Post-Fad"]
                    delegate: Button {
                        Layout.fillWidth: true
                        implicitHeight: 18
                        checkable: true
                        checked: root.selectedRouteTap === index
                        
                        background: Rectangle {
                            color: checked ? "#004F58" : "#14171a"
                            border.color: checked ? "#00BDD6" : "#252b36"
                            border.width: 1
                            radius: 3
                        }
                        contentItem: Text {
                            text: modelData
                            color: checked ? "#00BDD6" : "#8a8d98"
                            font.pixelSize: 6
                            font.bold: true
                            anchors.centerIn: parent
                        }
                        onClicked: {
                            root.selectedRouteTap = index;
                            audioCore.patchRoute(root.selectedRouteSrc, root.selectedRouteDest, root.selectedRouteGain, index);
                        }
                    }
                }
            }

            Rectangle {
                Layout.fillWidth: true
                height: 1
                color: "#252b36"
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 6
                Button {
                    text: "UNPATCH"
                    Layout.fillWidth: true
                    implicitHeight: 18
                    background: Rectangle { color: "#ff3b30"; radius: 4 }
                    contentItem: Text { text: parent.text; color: "#ffffff"; font.pixelSize: 7; font.bold: true; anchors.centerIn: parent }
                    onClicked: {
                        audioCore.unpatchRoute(root.selectedRouteSrc, root.selectedRouteDest);
                        root.routeEditorOpen = false;
                    }
                }
                Button {
                    text: "CLOSE"
                    Layout.fillWidth: true
                    implicitHeight: 18
                    background: Rectangle { color: "#252b36"; radius: 4; border.color: "#2d3139"; border.width: 1 }
                    contentItem: Text { text: parent.text; color: "#f8fafc"; font.pixelSize: 7; font.bold: true; anchors.centerIn: parent }
                    onClicked: root.routeEditorOpen = false;
                }
            }
        }
    }

}
