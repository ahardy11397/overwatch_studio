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



    // Shared Bridge Interfaces eagerly instantiated under the root QtObject

    AudioEngineBridge {

        id: audioCore

    }



    ShowBuilderBridge {

        id: showBuilder

    }



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

                                onClicked: audioWindowOpen = !audioWindowOpen

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

                                onClicked: videoWindowOpen = !videoWindowOpen

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

                                onClicked: sandboxWindowOpen = !sandboxWindowOpen

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





    // ----------------------------------------------------

    // 2. AUDIO TOUCH CONSOLE WINDOW

    // ----------------------------------------------------

    Window {

        id: audioWin

        visible: audioWindowOpen

        onVisibleChanged: {

            audioWindowOpen = visible;

        }

        width: 1620

        height: 680

        title: "Audio Touch Console"

        property bool dspPanelOpen: false

        property int selectedChannel: 0
        property bool editLayerAssignmentsActive: false
        property int uiInputsCount: 24
        property int uiBusesCount: 8
        property int uiAuxesCount: 8
        property int uiDCAsCount: 8
        property var faderAssignments: [
            // Bank 0 (default: CH 1-8)
            [
                {"type": "input", "actualIndex": 0, "name": "Mic 1"},
                {"type": "input", "actualIndex": 1, "name": "Mic 2"},
                {"type": "input", "actualIndex": 2, "name": "Mic 3"},
                {"type": "input", "actualIndex": 3, "name": "Mic 4"},
                {"type": "input", "actualIndex": 4, "name": "Mic 5"},
                {"type": "input", "actualIndex": 5, "name": "Mic 6"},
                {"type": "input", "actualIndex": 6, "name": "Mic 7"},
                {"type": "input", "actualIndex": 7, "name": "Mic 8"}
            ],
            // Bank 1 (default: CH 9-16)
            [
                {"type": "input", "actualIndex": 8, "name": "Mic 9"},
                {"type": "input", "actualIndex": 9, "name": "Mic 10"},
                {"type": "input", "actualIndex": 10, "name": "Mic 11"},
                {"type": "input", "actualIndex": 11, "name": "Mic 12"},
                {"type": "input", "actualIndex": 12, "name": "Mic 13"},
                {"type": "input", "actualIndex": 13, "name": "Mic 14"},
                {"type": "input", "actualIndex": 14, "name": "Mic 15"},
                {"type": "input", "actualIndex": 15, "name": "Mic 16"}
            ],
            // Bank 2 (default: CH 17-24)
            [
                {"type": "input", "actualIndex": 16, "name": "Mic 17"},
                {"type": "input", "actualIndex": 17, "name": "Mic 18"},
                {"type": "input", "actualIndex": 18, "name": "Mic 19"},
                {"type": "input", "actualIndex": 19, "name": "Mic 20"},
                {"type": "input", "actualIndex": 20, "name": "Mic 21"},
                {"type": "input", "actualIndex": 21, "name": "Mic 22"},
                {"type": "input", "actualIndex": 22, "name": "Mic 23"},
                {"type": "input", "actualIndex": 23, "name": "Mic 24"}
            ],
            // Bank 3 (default: DCA 1-8)
            [
                {"type": "dca", "actualIndex": 0, "name": "DCA 1"},
                {"type": "dca", "actualIndex": 1, "name": "DCA 2"},
                {"type": "dca", "actualIndex": 2, "name": "DCA 3"},
                {"type": "dca", "actualIndex": 3, "name": "DCA 4"},
                {"type": "dca", "actualIndex": 4, "name": "DCA 5"},
                {"type": "dca", "actualIndex": 5, "name": "DCA 6"},
                {"type": "dca", "actualIndex": 6, "name": "DCA 7"},
                {"type": "dca", "actualIndex": 7, "name": "DCA 8"}
            ],
            // Bank 4 (default custom layout)
            [
                {"type": "input", "actualIndex": 0, "name": "Mic 1"},
                {"type": "input", "actualIndex": 1, "name": "Discord Loop"},
                {"type": "input", "actualIndex": 2, "name": "Spotify Stream"},
                {"type": "input", "actualIndex": 3, "name": "Chrome Loop"},
                {"type": "aux",   "actualIndex": 0, "name": "Stage Mon"},
                {"type": "bus",   "actualIndex": 0, "name": "Mix Bus 1"},
                {"type": "dca",   "actualIndex": 0, "name": "Drums Master"},
                {"type": "dca",   "actualIndex": 1, "name": "Vocal Group"}
            ]
        ]
        color: "#0a0c10"

        x: 460

        y: 80



        property bool anySoloActive: {

            if (!audioCore || !audioCore.channelSoloStates) return false;

            for (var i = 0; i < audioCore.channelSoloStates.length; i++) {

                if (audioCore.channelSoloStates[i]) return true;

            }

            return false;

        }



        RowLayout {

            anchors.fill: parent

            anchors.margins: 15

            spacing: 15



            // Left Deck: Fader Banking selector

            Rectangle {

                Layout.fillHeight: true

                width: 110

                color: "#161920"

                border.color: "#252b36"

                border.width: 1

                radius: 10



                ColumnLayout {

                    anchors.fill: parent

                    anchors.margins: 12

                    spacing: 6



                    Text {

                        text: "FADER BANKS"

                        color: "#00d084"

                        font.pixelSize: 10

                        font.bold: true

                        font.letterSpacing: 1.2

                        Layout.alignment: Qt.AlignHCenter

                    }



                    Rectangle {

                        Layout.fillWidth: true

                        height: 1

                        color: "#252b36"

                    }



                    // Bank selection repeater

                    Repeater {

                        model: [

                            { name: "CH 1 - 8", bankIdx: 0 },

                            { name: "CH 9 - 16", bankIdx: 1 },

                            { name: "CH 17 - 24", bankIdx: 2 },

                            { name: "DCA 1 - 8", bankIdx: 3 },

                            { name: "ASSIGN LAYER", bankIdx: 4 }

                        ]



                        delegate: Button {

                            id: bankBtn

                            text: modelData.name

                            Layout.fillWidth: true

                            implicitHeight: 44

                            checkable: true

                            checked: activeBank === modelData.bankIdx



                            background: Rectangle {

                                color: bankBtn.checked ? "#00d084" : "#101216"

                                border.color: bankBtn.checked ? "#00d084" : "#252b36"

                                border.width: 1

                                radius: 6

                            }



                            contentItem: Text {

                                text: bankBtn.text

                                color: bankBtn.checked ? "#ffffff" : "#8a8d98"

                                font.pixelSize: 11

                                font.bold: true

                                horizontalAlignment: Text.AlignHCenter

                                verticalAlignment: Text.AlignVCenter

                            }



                            onClicked: {

                                activeBank = modelData.bankIdx;

                            }

                        }

                    }



                    Item { Layout.fillHeight: true }



                    // Tiny stats indicator at bottom of banking

                    Rectangle {

                        Layout.fillWidth: true

                        height: 52

                        color: "#101216"

                        radius: 6

                        border.color: "#252b36"



                        ColumnLayout {

                            anchors.centerIn: parent

                            spacing: 1

                            Text {

                                text: "LATENCY BUFFER"

                                color: "#8a8d98"

                                font.pixelSize: 7

                                font.bold: true

                            }

                            Text {

                                text: "32 SMP @ 48K"

                                color: "#00d084"

                                font.pixelSize: 10

                                font.bold: true

                            }

                        }

                    }

                }

            }



            // Center Deck: 4 Swappable Fader Channels

            Rectangle {

                Layout.fillWidth: true

                Layout.fillHeight: true

                color: "#161920"

                border.color: "#252b36"

                border.width: 1

                radius: 10



                ColumnLayout {

                    anchors.fill: parent

                    anchors.leftMargin: 8

                    anchors.rightMargin: 8

                    anchors.topMargin: 15

                    anchors.bottomMargin: 15

                    spacing: 10



                    // Top Utility Bar with Solo Clear

                    RowLayout {

                        Layout.fillWidth: true

                        height: 36

                        spacing: 12



                        Text {

                            text: "CONSOLE CHANNEL BANK"

                            color: "#8a8d98"

                            font.pixelSize: 11

                            font.bold: true

                            font.letterSpacing: 1.0

                        }



                        Item { Layout.fillWidth: true }

                        Button {
                            id: editLayerBtn
                            implicitWidth: 160
                            implicitHeight: 28
                            checkable: true
                            checked: audioWin.editLayerAssignmentsActive
                            
                            background: Rectangle {
                                color: editLayerBtn.checked ? "#00d084" : "#1a1f29"
                                border.color: editLayerBtn.checked ? "#00d084" : "#252b36"
                                border.width: 1.5
                                radius: 6
                            }
                            
                            contentItem: Text {
                                text: editLayerBtn.checked ? "⚙ EDITING FADERS (ACTIVE)" : "⚙ CUSTOMIZE FADERS"
                                color: editLayerBtn.checked ? "#0a0c10" : "#8a8d98"
                                font.pixelSize: 9
                                font.bold: true
                                horizontalAlignment: Text.AlignHCenter
                                verticalAlignment: Text.AlignVCenter
                            }
                            
                            onClicked: {
                                audioWin.editLayerAssignmentsActive = !audioWin.editLayerAssignmentsActive;
                            }
                        }

                        Button {

                            id: soloClearBtn

                            visible: audioWin.anySoloActive

                            implicitWidth: 140

                            implicitHeight: 28

                            

                            background: Rectangle {

                                color: "#FFB300"

                                radius: 6

                                border.color: "#FFB300"

                                border.width: 1.5



                                SequentialAnimation on opacity {

                                    running: audioWin.anySoloActive

                                    loops: Animation.Infinite

                                    PropertyAnimation { to: 0.6; duration: 600; easing.type: Easing.InOutQuad }

                                    PropertyAnimation { to: 1.0; duration: 600; easing.type: Easing.InOutQuad }

                                }

                            }



                            contentItem: Text {

                                text: "SOLO ACTIVE [CLEAR]"

                                color: "#0a0c10"

                                font.pixelSize: 9

                                font.bold: true

                                horizontalAlignment: Text.AlignHCenter

                                verticalAlignment: Text.AlignVCenter

                            }



                            onClicked: {

                                logStateBeforeChange();

                                audioCore.clearAllSolos();

                            }

                        }

                    }



                     RowLayout {

                         Layout.fillWidth: true

                         Layout.fillHeight: true

                         spacing: 6



                        Repeater {

                            model: 8



                            delegate: Rectangle {

                                Layout.fillWidth: true

                                Layout.fillHeight: true

                                color: "#101216"

                                radius: 8

                                border.color: "#252b36"



                                property int chIdx: root.activeBank * 8 + index

                                

                                property bool isDCA: audioWin.faderAssignments[root.activeBank][index].type === "dca"

                                property bool isInput: audioWin.faderAssignments[root.activeBank][index].type === "input"

                                property bool isAux: audioWin.faderAssignments[root.activeBank][index].type === "aux"

                                property bool isBus: audioWin.faderAssignments[root.activeBank][index].type === "bus"

                                property bool isFX: audioWin.faderAssignments[root.activeBank][index].type === "fx"

                                

                                property int resolvedIdx: audioWin.faderAssignments[root.activeBank][index].actualIndex



                                ColumnLayout {

                                    anchors.fill: parent

                                    anchors.leftMargin: 6

                                    anchors.rightMargin: 6

                                    anchors.topMargin: 12

                                    anchors.bottomMargin: 12

                                    spacing: 12



                                    // Fader Source Selector Header

                                    ColumnLayout {

                                        Layout.fillWidth: true

                                        Layout.alignment: Qt.AlignHCenter

                                        visible: audioWin.editLayerAssignmentsActive

                                        spacing: 2

                                        Text {

                                            text: "FADER " + (index + 1) + " SOURCE"

                                            color: "#8a8d98"

                                            font.pixelSize: 7

                                            font.bold: true

                                            Layout.alignment: Qt.AlignHCenter

                                        }

                                        ComboBox {

                                            id: srcSelect

                                            Layout.fillWidth: true

                                            model: [
                                                "CH 1: Mic 1",
                                                "CH 2: Mic 2",
                                                "CH 3: Discord Loop",
                                                "CH 4: Spotify Stream",
                                                "CH 5: Chrome Loop",
                                                "CH 6: Sound Effects",
                                                "AUX 1: Stage Monitor",
                                                "AUX 2: FX Send 1",
                                                "BUS A: Stereo Master",
                                                "BUS B: Sub Group",
                                                "DCA 1: Drums Master",
                                                "DCA 2: Vocal Group",
                                                "DCA 3: BGM Group"
                                            ]

                                            currentIndex: {
                                                var type = audioWin.faderAssignments[root.activeBank][index].type;
                                                var actIdx = audioWin.faderAssignments[root.activeBank][index].actualIndex;
                                                if (type === "input") {
                                                    if (actIdx === 0) return 0;
                                                    if (actIdx === 1) return 1;
                                                    if (actIdx === 2) return 2;
                                                    if (actIdx === 3) return 3;
                                                    if (actIdx === 4) return 4;
                                                    if (actIdx === 5) return 5;
                                                } else if (type === "aux") {
                                                    if (actIdx === 0) return 6;
                                                    if (actIdx === 1) return 7;
                                                } else if (type === "bus") {
                                                    if (actIdx === 0) return 8;
                                                    if (actIdx === 1) return 9;
                                                } else if (type === "dca") {
                                                    if (actIdx === 0) return 10;
                                                    if (actIdx === 1) return 11;
                                                    if (actIdx === 2) return 12;
                                                }
                                                return 0;
                                            }

                                            onActivated: (comboIndex) => {
                                                var temp = JSON.parse(JSON.stringify(audioWin.faderAssignments));
                                                var newObj = {"type": "input", "actualIndex": 0, "name": "Mic 1"};
                                                if (comboIndex === 0) newObj = {"type": "input", "actualIndex": 0, "name": "Mic 1"};
                                                else if (comboIndex === 1) newObj = {"type": "input", "actualIndex": 1, "name": "Mic 2"};
                                                else if (comboIndex === 2) newObj = {"type": "input", "actualIndex": 2, "name": "Discord Loop"};
                                                else if (comboIndex === 3) newObj = {"type": "input", "actualIndex": 3, "name": "Spotify Stream"};
                                                else if (comboIndex === 4) newObj = {"type": "input", "actualIndex": 4, "name": "Chrome Loop"};
                                                else if (comboIndex === 5) newObj = {"type": "input", "actualIndex": 5, "name": "Sound Effects"};
                                                else if (comboIndex === 6) newObj = {"type": "aux", "actualIndex": 0, "name": "Stage Mon"};
                                                else if (comboIndex === 7) newObj = {"type": "aux", "actualIndex": 1, "name": "FX Send 1"};
                                                else if (comboIndex === 8) newObj = {"type": "bus", "actualIndex": 0, "name": "Stereo Mas"};
                                                else if (comboIndex === 9) newObj = {"type": "bus", "actualIndex": 1, "name": "Sub Group"};
                                                else if (comboIndex === 10) newObj = {"type": "dca", "actualIndex": 0, "name": "Drums Mast"};
                                                else if (comboIndex === 11) newObj = {"type": "dca", "actualIndex": 1, "name": "Vocal Grou"};
                                                else if (comboIndex === 12) newObj = {"type": "dca", "actualIndex": 2, "name": "BGM Group"};
                                                
                                                temp[root.activeBank][index] = newObj;
                                                audioWin.faderAssignments = temp;
                                            }
                                        }
                                    }







                                    // DCA & Mute Group Indicator Badges

                                    RowLayout {

                                        Layout.alignment: Qt.AlignHCenter

                                        spacing: 3

                                        height: 12

                                        visible: root.activeBank < 3



                                        // DCA active indicators

                                        Repeater {

                                            model: 8

                                            delegate: Rectangle {

                                                width: 10

                                                height: 10

                                                radius: 5

                                                color: "#00d084"

                                                visible: (chIdx < 24) && (audioCore.channelDcaMasks[chIdx] & (1 << index))

                                                Text {

                                                    text: (index + 1)

                                                    color: "#0a0c10"

                                                    font.pixelSize: 7

                                                    font.bold: true

                                                    anchors.centerIn: parent

                                                }

                                            }

                                        }



                                        // Mute Group active indicators

                                        Repeater {

                                            model: 8

                                            delegate: Rectangle {

                                                width: 12

                                                height: 10

                                                radius: 3

                                                color: "#ff3b30"

                                                visible: (chIdx < 24) && (audioCore.channelMuteMasks[chIdx] & (1 << index))

                                                Text {

                                                    text: "M" + (index + 1)

                                                    color: "#ffffff"

                                                    font.pixelSize: 6

                                                    font.bold: true

                                                    anchors.centerIn: parent

                                                }

                                            }

                                        }

                                    }



                                    // DCA Master label

                                    Text {

                                        visible: isDCA

                                        text: "DCA MASTER"

                                        color: "#f0b000"

                                        font.pixelSize: 9

                                        font.bold: true

                                        Layout.alignment: Qt.AlignHCenter

                                    }



                                                                 // Mute, Solo & EDIT Button Panel (Stacked Vertically)
                                     ColumnLayout {
                                         Layout.alignment: Qt.AlignHCenter
                                         spacing: 4

                                         // Mute Button (red when muted)
                                         Button {
                                              id: muteBtn
                                              Layout.alignment: Qt.AlignHCenter
                                              implicitWidth: isDCA ? 80 : 68
                                              implicitHeight: 28
                                              checkable: true
                                              checked: getMuteForFader(audioWin.faderAssignments[root.activeBank][index].type, resolvedIdx)

                                               background: Rectangle {
                                                   color: muteBtn.checked ? "#ff3b30" : "#1a1f29"
                                                   border.color: muteBtn.checked ? "#ff3b30" : "#252b36"
                                                   radius: 6
                                               }

                                               contentItem: Text {
                                                   text: "MUTE"
                                                   color: muteBtn.checked ? "#ffffff" : "#ff3b30"
                                                   font.pixelSize: 9
                                                   font.bold: true
                                                   horizontalAlignment: Text.AlignHCenter
                                                   verticalAlignment: Text.AlignVCenter
                                               }

                                               onClicked: {
                                                   logStateBeforeChange();
                                                   var faderType = audioWin.faderAssignments[root.activeBank][index].type;
                                                   setMuteForFader(faderType, resolvedIdx, !getMuteForFader(faderType, resolvedIdx));
                                               }
                                           }

                                          // Solo Button (glowing amber when active)
                                          Button {
                                              id: soloBtn
                                              visible: !isDCA
                                              Layout.alignment: Qt.AlignHCenter
                                              implicitWidth: 68
                                              implicitHeight: 28
                                              checkable: true
                                              checked: (!isDCA && resolvedIdx < 24) ? audioCore.channelSoloStates[resolvedIdx] : false

                                              background: Rectangle {
                                                  color: soloBtn.checked ? "#FFB300" : "#1a1f29"
                                                  border.color: soloBtn.checked ? "#FFB300" : "#252b36"
                                                  radius: 6
                                              }

                                              contentItem: Text {
                                                  text: "SOLO"
                                                  color: soloBtn.checked ? "#0a0c10" : "#FFB300"
                                                  font.pixelSize: 9
                                                  font.bold: true
                                                  horizontalAlignment: Text.AlignHCenter
                                                  verticalAlignment: Text.AlignVCenter
                                              }

                                              onClicked: {
                                                  logStateBeforeChange();
                                                  if (!isDCA) {
                                                      audioCore.updateChannelSoloState(resolvedIdx, !audioCore.channelSoloStates[resolvedIdx]);
                                                  }
                                              }
                                          }

                                          // EDIT Button (glowing green when active, matching Solo/Mute sizes!)
                                          Button {
                                              id: editBtn
                                              visible: !isDCA
                                              Layout.alignment: Qt.AlignHCenter
                                              implicitWidth: 68
                                              implicitHeight: 28
                                              background: Rectangle {
                                                  color: (audioWin.dspPanelOpen && audioWin.selectedChannel === resolvedIdx) ? "#00d084" : "#1a1f29"
                                                  border.color: (audioWin.dspPanelOpen && audioWin.selectedChannel === resolvedIdx) ? "#00d084" : "#252b36"
                                                  radius: 6
                                              }
                                              contentItem: Text {
                                                  text: "EDIT"
                                                  color: (audioWin.dspPanelOpen && audioWin.selectedChannel === resolvedIdx) ? "#ffffff" : "#8a8d98"
                                                  font.pixelSize: 9
                                                  font.bold: true
                                                  horizontalAlignment: Text.AlignHCenter
                                                  verticalAlignment: Text.AlignVCenter
                                              }
                                              onClicked: {
                                                  audioWin.selectedChannel = resolvedIdx;
                                                  audioWin.dspPanelOpen = true;
                                              }
                                          }
                                      }

                                      // Channel Label placed below the buttons ColumnLayout
                                      Text {
                                          text: {
                                              var type = audioWin.faderAssignments[root.activeBank][index].type;
                                              if (type === "input") return "CH " + (resolvedIdx + 1);
                                              return type.toUpperCase() + " " + (resolvedIdx + 1);
                                          }
                                                                                     color: {
                                               var type = audioWin.faderAssignments[root.activeBank][index].type;
                                               if (type === "input") return "#00d084";
                                               if (type === "bus") return "#ff9500";
                                               if (type === "aux") return "#00BDD6";
                                               if (type === "dca") return "#E040FB";
                                               return "#8a8d98";
                                           }
                                          font.pixelSize: 11
                                          font.bold: true
                                          Layout.alignment: Qt.AlignHCenter
                                      }                

                                     // Solo Mode (PFL/AFL) Selector Badge

                                     Rectangle {

                                         Layout.alignment: Qt.AlignHCenter

                                         visible: (root.activeBank < 3) && (chIdx < 24)

                                         width: 50

                                         height: 16

                                         color: "#1a1f29"

                                         border.color: "#252b36"

                                         radius: 4



                                         Text {

                                             text: (chIdx < 24 && audioCore.channelSoloModes[chIdx]) ? "AFL" : "PFL"

                                             color: (chIdx < 24 && audioCore.channelSoloModes[chIdx]) ? "#00d084" : "#ff9500"

                                             font.pixelSize: 8

                                             font.bold: true

                                             anchors.centerIn: parent

                                         }



                                         MouseArea {

                                             anchors.fill: parent

                                             onClicked: {

                                                 logStateBeforeChange();

                                                 audioCore.updateChannelSoloMode(chIdx, !audioCore.channelSoloModes[chIdx]);

                                             }

                                         }

                                     }



                                    Item { Layout.fillHeight: true }



                                     // Centered vertical fader and level meter

                                     Item {

                                         width: 76

                                         height: 240

                                         Layout.alignment: Qt.AlignHCenter



                                         // Vertical Level Meter on the left of fader

                                         Rectangle {

                                             id: channelMeter

                                             width: 10

                                             height: 240

                                             color: "#0d0f12"

                                             radius: 5

                                             border.color: "#252b36"

                                             border.width: 1

                                             anchors.right: faderSlider.left

                                             anchors.rightMargin: 4



                                             Rectangle {

                                                 width: parent.width

                                                 height: {
                                                      var faderType = audioWin.faderAssignments[root.activeBank][index].type;
                                                      if (audioCore.fadeToBlack || getMuteForFader(faderType, resolvedIdx)) return 0;

                                                      var peak = 0.0;
                                                      if (faderType === "input" && audioCore.channelPeaks && resolvedIdx < audioCore.channelPeaks.length) {
                                                          peak = audioCore.channelPeaks[resolvedIdx];
                                                      } else if (faderType === "bus" && audioCore.busPeaks && resolvedIdx < audioCore.busPeaks.length) {
                                                          peak = audioCore.busPeaks[resolvedIdx];
                                                      } else if (faderType === "aux" && audioCore.auxPeaks && resolvedIdx < audioCore.auxPeaks.length) {
                                                          peak = audioCore.auxPeaks[resolvedIdx];
                                                      } else if (faderType === "dca") {
                                                          var dcaMask = 1 << resolvedIdx;
                                                          for (var ch = 0; ch < 24; ++ch) {
                                                              if ((audioCore.channelDcaMasks[ch] & dcaMask) && audioCore.channelPeaks && ch < audioCore.channelPeaks.length) {
                                                                  peak = Math.max(peak, audioCore.channelPeaks[ch]);
                                                              }
                                                          }
                                                      }
                                                      return Math.max(0, Math.min(1.0, peak)) * parent.height;

                                                  }

                                                 anchors.bottom: parent.bottom

                                                 color: "#00d084"

                                                 radius: 5

                                             }

                                         }



                                         // Hand-optimized touch safe slider centered in the container

                                         Item {

                                             id: faderSlider

                                             width: 48

                                             height: 240

                                             anchors.horizontalCenter: parent.horizontalCenter



                                             // Slider track line

                                             Rectangle {

                                                 width: 6

                                                 height: parent.height - 30

                                                 color: "#080a0d"

                                                 radius: 3

                                                 anchors.horizontalCenter: parent.horizontalCenter

                                                 anchors.verticalCenter: parent.verticalCenter

                                             }



                                             // Fader knob cap: 3D Curved Metallic Brushed-Aluminum
                                             Rectangle {
                                                 id: faderKnob
                                                 width: 44 // 44px premium touch fader cap width
                                                 height: 28 // 28px height for solid grip
                                                 radius: 5
                                                 gradient: Gradient {
                                                     orientation: Gradient.Horizontal
                                                     GradientStop { position: 0.0; color: "#3a3f4d" }
                                                     GradientStop { position: 0.18; color: "#7a8291" }
                                                     GradientStop { position: 0.45; color: "#e2e6ed" }
                                                     GradientStop { position: 0.5; color: "#ffffff" }
                                                     GradientStop { position: 0.55; color: "#e2e6ed" }
                                                     GradientStop { position: 0.82; color: "#7a8291" }
                                                     GradientStop { position: 1.0; color: "#3a3f4d" }
                                                 }
                                                 border.color: "#1a1c22"
                                                 border.width: 1.5
                                                 anchors.horizontalCenter: parent.horizontalCenter
                                                 y: (parent.height - height - 30) * (1.0 - getVolumeForFader(audioWin.faderAssignments[root.activeBank][index].type, resolvedIdx)) + 15

                                                 // Horizontal finger rest recess indent
                                                 Rectangle {
                                                     width: parent.width - 6
                                                     height: 8
                                                     color: "#14171e"
                                                     radius: 2
                                                     anchors.centerIn: parent
                                                     border.color: "#3a3d46"
                                                     border.width: 0.5

                                                     // Glowing alignment line inside the finger rest recess
                                                     Rectangle {
                                                         width: parent.width - 10
                                                         height: 2
                                                         color: {
                                                             var type = audioWin.faderAssignments[root.activeBank][index].type;
                                                             if (type === "input") return "#00d084";
                                                             if (type === "bus") return "#ff9500";
                                                             if (type === "aux") return "#00BDD6";
                                                             if (type === "dca") return "#E040FB";
                                                             return "#8a8d98";
                                                         }
                                                         anchors.centerIn: parent
                                                     }
                                                 }
                                             }

                                             // Large transparent touchscreen hit-box area
                                             MouseArea {
                                                 anchors.fill: parent
                                                 preventStealing: true

                                                 function dragValue(mouseY) {
                                                     var margin = 15;
                                                     var range = parent.height - 30;
                                                     var clampedY = Math.max(margin, Math.min(mouseY, parent.height - margin));
                                                     var val = 1.0 - (clampedY - margin) / range;
                                                     
                                                     var faderType = audioWin.faderAssignments[root.activeBank][index].type;
                                                     setVolumeForFader(faderType, resolvedIdx, val);
                                                 }

                                                 onPressed: (mouse) => {
                                                     logStateBeforeChange();
                                                     dragValue(mouse.y);
                                                 }

                                                 onPositionChanged: (mouse) => dragValue(mouse.y)
                                             }
                                         }
                                     }



                                    Item { Layout.fillHeight: true }



                                    Text {
                                        text: Math.round(getVolumeForFader(audioWin.faderAssignments[root.activeBank][index].type, resolvedIdx) * 100) + "%"
                                        color: "#8a8d98"
                                        font.pixelSize: 9
                                        Layout.alignment: Qt.AlignHCenter
                                    }
                                    }

                                }

                            }

                        }

                    }

                }



            // Right Deck: Dedicated MASTER fader strip

            Rectangle {

                Layout.fillHeight: true

                width: 130

                color: "#161920"

                border.color: "#252b36"

                border.width: 1

                radius: 10



                ColumnLayout {

                    anchors.fill: parent

                    anchors.margins: 12

                    spacing: 12



                    Text {

                        text: "MASTER BUS"

                        color: "#ff3b30"

                        font.pixelSize: 11

                        font.bold: true

                        font.letterSpacing: 1.2

                        Layout.alignment: Qt.AlignHCenter

                    }



                    Button {

                        id: masterMuteBtn

                        Layout.alignment: Qt.AlignHCenter

                        implicitWidth: 80

                        implicitHeight: 36

                        checkable: true

                        checked: masterMute



                        background: Rectangle {

                            color: masterMuteBtn.checked ? "#ff3b30" : "#1a1f29"

                            border.color: masterMuteBtn.checked ? "#ff3b30" : "#252b36"

                            radius: 6

                        }



                        contentItem: Text {

                            text: "MUTE"

                            color: masterMuteBtn.checked ? "#ffffff" : "#ff3b30"

                            font.pixelSize: 9

                            font.bold: true

                            horizontalAlignment: Text.AlignHCenter

                            verticalAlignment: Text.AlignVCenter

                        }



                        onClicked: {

                            logStateBeforeChange();

                            setMute(24, !masterMute);

                        }

                    }



                    Item { Layout.fillHeight: true }



                    // Centered vertical master fader and level meter

                    Item {

                        width: 104

                        height: 280

                        Layout.alignment: Qt.AlignHCenter



                        // Master Peak Meter on the left of fader

                        Rectangle {

                            id: masterMeter

                            width: 12

                            height: 280

                            color: "#0d0f12"

                            radius: 6

                            border.color: "#252b36"

                            border.width: 1

                            anchors.right: masterFader.left

                            anchors.rightMargin: 4



                            Rectangle {

                                width: parent.width

                                height: {

                                    if (audioCore.fadeToBlack || masterMute) return 0;

                                    return Math.max(0, Math.min(1.0, audioCore.masterPeak)) * parent.height;

                                }

                                anchors.bottom: parent.bottom

                                color: "#ff3b30" // Master has red peak visual

                                radius: 6

                            }

                        }



                        // Master fader centered in the container

                        Item {

                            id: masterFader

                            width: 72

                            height: 280

                            anchors.horizontalCenter: parent.horizontalCenter



                            Rectangle {

                                width: 6

                                height: parent.height - 30

                                color: "#080a0d"

                                radius: 3

                                anchors.horizontalCenter: parent.horizontalCenter

                                anchors.verticalCenter: parent.verticalCenter

                            }



                            Rectangle {
                                id: masterKnob
                                width: 48 // Matching premium width
                                height: 30 // Solid height
                                radius: 5
                                gradient: Gradient {
                                    orientation: Gradient.Horizontal
                                    GradientStop { position: 0.0; color: "#4a2d2d" }
                                    GradientStop { position: 0.18; color: "#8a5757" }
                                    GradientStop { position: 0.45; color: "#fcdada" }
                                    GradientStop { position: 0.5; color: "#ffffff" }
                                    GradientStop { position: 0.55; color: "#fcdada" }
                                    GradientStop { position: 0.82; color: "#8a5757" }
                                    GradientStop { position: 1.0; color: "#4a2d2d" }
                                }
                                border.color: "#2b1414"
                                border.width: 1.5
                                anchors.horizontalCenter: parent.horizontalCenter
                                y: (parent.height - height - 30) * (1.0 - masterVolume) + 15


                                // Horizontal finger rest recess indent (Master dark red recess)

                                Rectangle {

                                    width: parent.width - 6

                                    height: 8

                                    color: "#1a0808"

                                    radius: 2

                                    anchors.centerIn: parent

                                    border.color: "#4a2525"

                                    border.width: 0.5

                                }



                                // Glowing Master Red indicator line inside the recess

                                Rectangle {

                                    width: parent.width - 10

                                    height: 2

                                    color: "#ff3b30"

                                    anchors.centerIn: parent

                                }

                            }



                            MouseArea {

                                anchors.fill: parent

                                preventStealing: true



                                function dragMaster(mouseY) {

                                    var margin = 15;

                                    var range = parent.height - 30;

                                    var clampedY = Math.max(margin, Math.min(mouseY, parent.height - margin));

                                    var val = 1.0 - (clampedY - margin) / range;

                                    setVolume(24, val);

                                }



                                onPressed: (mouse) => {

                                    logStateBeforeChange();

                                    dragMaster(mouse.y);

                                }

                                onPositionChanged: (mouse) => dragMaster(mouse.y)

                            }

                        }

                    }



                    Item { Layout.fillHeight: true }



                    Text {

                        text: Math.round(masterVolume * 100) + "%"

                        color: "#8a8d98"

                        font.pixelSize: 10

                        font.bold: true

                        Layout.alignment: Qt.AlignHCenter

                    }

                }

            }



            // Selected Channel DSP Inspector Panel

            Rectangle {

                id: dspInspectorPanel

                visible: audioWin.dspPanelOpen

                Layout.fillHeight: true

                Layout.preferredWidth: audioWin.dspPanelOpen ? 440 : 0

                color: "#161920"

                border.color: "#252b36"

                border.width: 1

                radius: 10

                clip: true



                Behavior on Layout.preferredWidth {

                    NumberAnimation { duration: 250; easing.type: Easing.OutCubic }

                }



                property int activeDspTab: 0



                ColumnLayout {

                    anchors.fill: parent

                    anchors.margins: 15

                    spacing: 12



                    // Header with Close [X] Button

                    RowLayout {

                        Layout.fillWidth: true

                        spacing: 10



                        Text {

                            text: "SELECTED CHANNEL: CH " + (audioWin.selectedChannel + 1)

                            color: "#00d084"

                            font.pixelSize: 12

                            font.bold: true

                        }



                        Item { Layout.fillWidth: true }



                        Button {

                            id: closeDspBtn

                            implicitWidth: 24

                            implicitHeight: 24

                            background: Rectangle {

                                color: "#1a1f29"

                                border.color: "#ff3b30"

                                radius: 12

                            }

                            contentItem: Text {

                                text: "X"

                                color: "#ff3b30"

                                font.pixelSize: 9

                                font.bold: true

                                horizontalAlignment: Text.AlignHCenter

                                verticalAlignment: Text.AlignVCenter

                            }

                            onClicked: audioWin.dspPanelOpen = false

                        }

                    }



                    // Frosted Tab Selector Row

                    RowLayout {

                        Layout.fillWidth: true

                        spacing: 6



                        Repeater {

                            model: ["PRE-AMP", "EQ", "DYNAMICS", "LIMITER"]

                            delegate: Button {

                                id: tabBtn

                                text: modelData

                                Layout.fillWidth: true

                                implicitHeight: 28

                                checkable: true

                                checked: dspInspectorPanel.activeDspTab === index



                                background: Rectangle {

                                    color: tabBtn.checked ? "#00d084" : "#101216"

                                    border.color: tabBtn.checked ? "#00d084" : "#252b36"

                                    border.width: 1

                                    radius: 4

                                }



                                contentItem: Text {

                                    text: tabBtn.text

                                    color: tabBtn.checked ? "#ffffff" : "#8a8d98"

                                    font.pixelSize: 9

                                    font.bold: true

                                    horizontalAlignment: Text.AlignHCenter

                                    verticalAlignment: Text.AlignVCenter

                                }



                                onClicked: dspInspectorPanel.activeDspTab = index

                            }

                        }

                    }



                    // Separator

                    Rectangle {

                        Layout.fillWidth: true

                        height: 1

                        color: "#252b36"

                    }



                    
                    // Active DSP Tab Views
                    Item {
                        Layout.fillWidth: true
                        Layout.fillHeight: true

                        // Page 1: Pre-Amp, HPF/LPF & Saturation Drive
                        ScrollView {
                            visible: dspInspectorPanel.activeDspTab === 0
                            anchors.fill: parent
                            clip: true
                            ColumnLayout {
                                width: parent.width - 20
                                spacing: 10
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

                                                id: satBypassBtn

                                                text: audioCore.channelSatBypasses[audioWin.selectedChannel] ? "BYPASSED" : "ACTIVE"

                                                implicitWidth: 60

                                                implicitHeight: 18

                                                background: Rectangle {

                                                    color: audioCore.channelSatBypasses[audioWin.selectedChannel] ? "#ff3b30" : "#11261d"

                                                    radius: 4

                                                }

                                                contentItem: Text {

                                                    text: satBypassBtn.text

                                                    color: "#ffffff"

                                                    font.pixelSize: 8

                                                    font.bold: true

                                                    horizontalAlignment: Text.AlignHCenter

                                                    verticalAlignment: Text.AlignVCenter

                                                }

                                                onClicked: audioCore.updateChannelSaturation(audioWin.selectedChannel, audioCore.channelSatDrives[audioWin.selectedChannel], audioCore.channelSatMixes[audioWin.selectedChannel], audioCore.channelSatModes[audioWin.selectedChannel], !audioCore.channelSatBypasses[audioWin.selectedChannel])

                                            }

                                        }



                                        RowLayout {

                                            Layout.fillWidth: true

                                            spacing: 12



                                            // Wave Shaper Canvas

                                            Canvas {

                                                id: satCanvas

                                                width: 80

                                                height: 80

                                                Layout.alignment: Qt.AlignVCenter

                                                onPaint: {

                                                    var ctx = getContext("2d");

                                                    ctx.clearRect(0, 0, width, height);

                                                    ctx.fillStyle = "#0c0e12";

                                                    ctx.fillRect(0, 0, width, height);



                                                    // Draw shaping grid

                                                    ctx.strokeStyle = "#1b1e25";

                                                    ctx.lineWidth = 1;

                                                    ctx.beginPath();

                                                    ctx.moveTo(width/2, 0); ctx.lineTo(width/2, height);

                                                    ctx.moveTo(0, height/2); ctx.lineTo(width, height/2);

                                                    ctx.stroke();



                                                    // Plot saturation transfer curve

                                                    ctx.strokeStyle = audioCore.channelSatBypasses[audioWin.selectedChannel] ? "#8a8d98" : "#00d084";

                                                    ctx.lineWidth = 2;

                                                    ctx.beginPath();

                                                    var mode = audioCore.channelSatModes[audioWin.selectedChannel];

                                                    var drive = audioCore.channelSatDrives[audioWin.selectedChannel];

                                                    var mix = audioCore.channelSatMixes[audioWin.selectedChannel];



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

                                                    function onDspChanged() { satCanvas.requestPaint(); }

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

                                                            implicitWidth: 80

                                                            implicitHeight: 20

                                                            background: Rectangle {

                                                                color: audioCore.channelSatModes[audioWin.selectedChannel] === index ? "#00d084" : "#1a1f29"

                                                                radius: 4

                                                            }

                                                            contentItem: Text {

                                                                text: parent.text

                                                                color: audioCore.channelSatModes[audioWin.selectedChannel] === index ? "#ffffff" : "#8a8d98"

                                                                font.pixelSize: 8

                                                                font.bold: true

                                                                horizontalAlignment: Text.AlignHCenter

                                                                verticalAlignment: Text.AlignVCenter

                                                            }

                                                            onClicked: audioCore.updateChannelSaturation(audioWin.selectedChannel, audioCore.channelSatDrives[audioWin.selectedChannel], audioCore.channelSatMixes[audioWin.selectedChannel], index, audioCore.channelSatBypasses[audioWin.selectedChannel])

                                                        }

                                                    }

                                                }



                                                RowLayout {

                                                    Layout.fillWidth: true

                                                    Text { text: "DRIVE"; color: "#8a8d98"; font.pixelSize: 8; width: 35 }

                                                    Slider {

                                                        Layout.fillWidth: true

                                                        from: 1.0; to: 10.0

                                                        value: audioCore.channelSatDrives[audioWin.selectedChannel]

                                                        onMoved: audioCore.updateChannelSaturation(audioWin.selectedChannel, value, audioCore.channelSatMixes[audioWin.selectedChannel], audioCore.channelSatModes[audioWin.selectedChannel], audioCore.channelSatBypasses[audioWin.selectedChannel])

                                                    }

                                                    Text { text: audioCore.channelSatDrives[audioWin.selectedChannel].toFixed(1) + "x"; color: "#00d084"; font.pixelSize: 8; width: 28 }

                                                }



                                                RowLayout {

                                                    Layout.fillWidth: true

                                                    Text { text: "MIX"; color: "#8a8d98"; font.pixelSize: 8; width: 35 }

                                                    Slider {

                                                        Layout.fillWidth: true

                                                        from: 0.0; to: 1.0

                                                        value: audioCore.channelSatMixes[audioWin.selectedChannel]

                                                        onMoved: audioCore.updateChannelSaturation(audioWin.selectedChannel, audioCore.channelSatDrives[audioWin.selectedChannel], value, audioCore.channelSatModes[audioWin.selectedChannel], audioCore.channelSatBypasses[audioWin.selectedChannel])

                                                    }

                                                    Text { text: Math.round(audioCore.channelSatMixes[audioWin.selectedChannel] * 100) + "%"; color: "#00d084"; font.pixelSize: 8; width: 28 }

                                                }

                                            }

                                        }



                                        // Pre-Amp Trim Gain

                                        RowLayout {

                                            Layout.fillWidth: true

                                            Text { text: "TRIM"; color: "#8a8d98"; font.pixelSize: 8; width: 35 }

                                            Slider {

                                                Layout.fillWidth: true

                                                from: -18.0; to: 18.0

                                                value: audioCore.channelTrims[audioWin.selectedChannel]

                                                onMoved: audioCore.updateChannelTrim(audioWin.selectedChannel, value)

                                            }

                                            Text { text: audioCore.channelTrims[audioWin.selectedChannel].toFixed(1) + "dB"; color: "#00d084"; font.pixelSize: 8; width: 35 }

                                            Button {

                                                id: phaseBtn

                                                text: "Ø INVERT"

                                                implicitWidth: 50

                                                implicitHeight: 18

                                                background: Rectangle {

                                                    color: audioCore.channelPhases[audioWin.selectedChannel] ? "#ff3b30" : "#1a1f29"

                                                    radius: 4

                                                }

                                                contentItem: Text {

                                                    text: phaseBtn.text

                                                    color: "#ffffff"

                                                    font.pixelSize: 7

                                                    font.bold: true

                                                    horizontalAlignment: Text.AlignHCenter

                                                    verticalAlignment: Text.AlignVCenter

                                                }

                                                onClicked: audioCore.updateChannelPhase(audioWin.selectedChannel, !audioCore.channelPhases[audioWin.selectedChannel])

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

                                                text: audioCore.channelHPFSlopes[audioWin.selectedChannel] + " dB"

                                                implicitWidth: 40; implicitHeight: 16

                                                background: Rectangle { color: "#1a1f29"; radius: 3 }

                                                contentItem: Text { text: parent.text; color: "#00d084"; font.pixelSize: 7; font.bold: true; anchors.centerIn: parent }

                                                onClicked: audioCore.updateChannelHPF(audioWin.selectedChannel, audioCore.channelHPFCutoffs[audioWin.selectedChannel], audioCore.channelHPFSlopes[audioWin.selectedChannel] === 12 ? 24 : 12, audioCore.channelHPFBypasses[audioWin.selectedChannel])

                                            }

                                            Button {

                                                text: audioCore.channelHPFBypasses[audioWin.selectedChannel] ? "BYPASSED" : "ACTIVE"

                                                implicitWidth: 55; implicitHeight: 16

                                                background: Rectangle { color: audioCore.channelHPFBypasses[audioWin.selectedChannel] ? "#ff3b30" : "#11261d"; radius: 3 }

                                                contentItem: Text { text: parent.text; color: "#ffffff"; font.pixelSize: 7; font.bold: true; anchors.centerIn: parent }

                                                onClicked: audioCore.updateChannelHPF(audioWin.selectedChannel, audioCore.channelHPFCutoffs[audioWin.selectedChannel], audioCore.channelHPFSlopes[audioWin.selectedChannel], !audioCore.channelHPFBypasses[audioWin.selectedChannel])

                                            }

                                        }

                                        RowLayout {

                                            Layout.fillWidth: true

                                            Slider {

                                                Layout.fillWidth: true

                                                from: 20.0; to: 400.0

                                                value: audioCore.channelHPFCutoffs[audioWin.selectedChannel]

                                                onMoved: audioCore.updateChannelHPF(audioWin.selectedChannel, value, audioCore.channelHPFSlopes[audioWin.selectedChannel], audioCore.channelHPFBypasses[audioWin.selectedChannel])

                                            }

                                            Text { text: Math.round(audioCore.channelHPFCutoffs[audioWin.selectedChannel]) + " Hz"; color: "#00d084"; font.pixelSize: 8; font.bold: true; width: 40 }

                                        }



                                        // LPF sub-section

                                        RowLayout {

                                            Layout.fillWidth: true

                                            Text { text: "LOW-PASS FILTER (LPF)"; color: "#8a8d98"; font.pixelSize: 9; font.bold: true }

                                            Item { Layout.fillWidth: true }

                                            Button {

                                                text: audioCore.channelLPFSlopes[audioWin.selectedChannel] + " dB"

                                                implicitWidth: 40; implicitHeight: 16

                                                background: Rectangle { color: "#1a1f29"; radius: 3 }

                                                contentItem: Text { text: parent.text; color: "#00d084"; font.pixelSize: 7; font.bold: true; anchors.centerIn: parent }

                                                onClicked: audioCore.updateChannelLPF(audioWin.selectedChannel, audioCore.channelLPFCutoffs[audioWin.selectedChannel], audioCore.channelLPFSlopes[audioWin.selectedChannel] === 12 ? 24 : 12, audioCore.channelLPFBypasses[audioWin.selectedChannel])

                                            }

                                            Button {

                                                text: audioCore.channelLPFBypasses[audioWin.selectedChannel] ? "BYPASSED" : "ACTIVE"

                                                implicitWidth: 55; implicitHeight: 16

                                                background: Rectangle { color: audioCore.channelLPFBypasses[audioWin.selectedChannel] ? "#ff3b30" : "#11261d"; radius: 3 }

                                                contentItem: Text { text: parent.text; color: "#ffffff"; font.pixelSize: 7; font.bold: true; anchors.centerIn: parent }

                                                onClicked: audioCore.updateChannelLPF(audioWin.selectedChannel, audioCore.channelLPFCutoffs[audioWin.selectedChannel], audioCore.channelLPFSlopes[audioWin.selectedChannel], !audioCore.channelLPFBypasses[audioWin.selectedChannel])

                                            }

                                        }

                                        RowLayout {

                                            Layout.fillWidth: true

                                            Slider {

                                                Layout.fillWidth: true

                                                from: 2000.0; to: 20000.0

                                                value: audioCore.channelLPFCutoffs[audioWin.selectedChannel]

                                                onMoved: audioCore.updateChannelLPF(audioWin.selectedChannel, value, audioCore.channelLPFSlopes[audioWin.selectedChannel], audioCore.channelLPFBypasses[audioWin.selectedChannel])

                                            }

                                            Text { text: (audioCore.channelLPFCutoffs[audioWin.selectedChannel] / 1000.0).toFixed(1) + " kHz"; color: "#00d084"; font.pixelSize: 8; font.bold: true; width: 40 }

                                        }

                                    }

                                }
                            }
                        }

                        // Page 2: EQ & Dynamic EQ Touch Canvas
                        ScrollView {
                            visible: dspInspectorPanel.activeDspTab === 1
                            anchors.fill: parent
                            clip: true
                            ColumnLayout {
                                width: parent.width - 20
                                spacing: 10
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
                                            id: eqCanvas
                                            Layout.fillWidth: true
                                            height: 80
                                            Connections {
                                                target: audioCore
                                                function onDspChanged() { eqCanvas.requestPaint(); }
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
                                                var ch = audioWin.selectedChannel;
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
                                                    var ch = audioWin.selectedChannel;
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
                                                        var ch = audioWin.selectedChannel;
                                                        var minF = root.getBandMinFreq(grabbedBand);
                                                        var maxF = root.getBandMaxFreq(grabbedBand);
                                                        
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
                                                        text: audioCore.channelEQBand0Types[audioWin.selectedChannel] === 0 ? "LOW SHELF" : "LOW PEAK"
                                                        color: "#00d084"; font.pixelSize: 9; font.bold: true 
                                                    }
                                                    Item { Layout.fillWidth: true }
                                                    Button {
                                                        text: audioCore.channelEQBand0Types[audioWin.selectedChannel] === 0 ? "SHELF" : "BELL"
                                                        implicitWidth: 42; implicitHeight: 16
                                                        background: Rectangle { color: audioCore.channelEQBand0Types[audioWin.selectedChannel] === 0 ? "#11261d" : "#1a1f29"; radius: 3 }
                                                        contentItem: Text { text: parent.text; color: "#00d084"; font.pixelSize: 7; font.bold: true; anchors.centerIn: parent }
                                                        onClicked: audioCore.updateChannelEQType(audioWin.selectedChannel, 0, audioCore.channelEQBand0Types[audioWin.selectedChannel] === 0 ? 1 : 0)
                                                    }
                                                    Button {
                                                        text: audioCore.channelEQBand0Dynamics[audioWin.selectedChannel] ? "DYN ON" : "DYN OFF"
                                                        implicitWidth: 46; implicitHeight: 16
                                                        background: Rectangle { color: audioCore.channelEQBand0Dynamics[audioWin.selectedChannel] ? "#00d084" : "#1a1f29"; radius: 3 }
                                                        contentItem: Text { text: parent.text; color: audioCore.channelEQBand0Dynamics[audioWin.selectedChannel] ? "#0a0c10" : "#8a8d98"; font.pixelSize: 7; font.bold: true; anchors.centerIn: parent }
                                                        onClicked: audioCore.updateChannelEQDynamic(audioWin.selectedChannel, 0, !audioCore.channelEQBand0Dynamics[audioWin.selectedChannel])
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
                                                            value: audioCore.channelEQBand0Gains[audioWin.selectedChannel]
                                                            onMoved: audioCore.updateChannelEQ(audioWin.selectedChannel, 0, value)
                                                        }
                                                        Text { text: audioCore.channelEQBand0Gains[audioWin.selectedChannel].toFixed(1) + "dB"; color: "#00d084"; font.pixelSize: 8; font.family: "Courier New"; width: 35 }
                                                    }

                                                    // Frequency
                                                    RowLayout {
                                                        Layout.fillWidth: true; Layout.preferredWidth: 1; spacing: 4
                                                        Text { text: "F"; color: "#8a8d98"; font.pixelSize: 8; font.bold: true }
                                                        PremiumSlider {
                                                            Layout.fillWidth: true; accentColor: "#00d084"
                                                            from: 0.0; to: 1.0
                                                            value: root.getEQFreqSliderVal(0, audioWin.selectedChannel)
                                                            onMoved: audioCore.updateChannelEQFreq(audioWin.selectedChannel, 0, root.getBandMinFreq(0) * Math.pow(root.getBandMaxFreq(0) / root.getBandMinFreq(0), value))
                                                        }
                                                        Text {
                                                            text: {
                                                                var f = root.getEQFreq(0, audioWin.selectedChannel);
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
                                                            value: audioCore.channelEQBand0Qs[audioWin.selectedChannel]
                                                            onMoved: audioCore.updateChannelEQQ(audioWin.selectedChannel, 0, value)
                                                        }
                                                        Text { text: audioCore.channelEQBand0Qs[audioWin.selectedChannel].toFixed(2); color: "#00d084"; font.pixelSize: 8; font.family: "Courier New"; width: 28 }
                                                    }
                                                }
                                            }

                                            // Spacer line between bands
                                            Rectangle {
                                                Layout.fillWidth: true
                                                height: 1
                                                color: "#1e222b"
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
                                                        text: audioCore.channelEQBand1Dynamics[audioWin.selectedChannel] ? "DYN ON" : "DYN OFF"
                                                        implicitWidth: 46; implicitHeight: 16
                                                        background: Rectangle { color: audioCore.channelEQBand1Dynamics[audioWin.selectedChannel] ? "#ffc72c" : "#1a1f29"; radius: 3 }
                                                        contentItem: Text { text: parent.text; color: audioCore.channelEQBand1Dynamics[audioWin.selectedChannel] ? "#0a0c10" : "#8a8d98"; font.pixelSize: 7; font.bold: true; anchors.centerIn: parent }
                                                        onClicked: audioCore.updateChannelEQDynamic(audioWin.selectedChannel, 1, !audioCore.channelEQBand1Dynamics[audioWin.selectedChannel])
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
                                                            value: audioCore.channelEQBand1Gains[audioWin.selectedChannel]
                                                            onMoved: audioCore.updateChannelEQ(audioWin.selectedChannel, 1, value)
                                                        }
                                                        Text { text: audioCore.channelEQBand1Gains[audioWin.selectedChannel].toFixed(1) + "dB"; color: "#ffc72c"; font.pixelSize: 8; font.family: "Courier New"; width: 35 }
                                                    }

                                                    // Frequency
                                                    RowLayout {
                                                        Layout.fillWidth: true; Layout.preferredWidth: 1; spacing: 4
                                                        Text { text: "F"; color: "#8a8d98"; font.pixelSize: 8; font.bold: true }
                                                        PremiumSlider {
                                                            Layout.fillWidth: true; accentColor: "#ffc72c"
                                                            from: 0.0; to: 1.0
                                                            value: root.getEQFreqSliderVal(1, audioWin.selectedChannel)
                                                            onMoved: audioCore.updateChannelEQFreq(audioWin.selectedChannel, 1, root.getBandMinFreq(1) * Math.pow(root.getBandMaxFreq(1) / root.getBandMinFreq(1), value))
                                                        }
                                                        Text {
                                                            text: {
                                                                var f = root.getEQFreq(1, audioWin.selectedChannel);
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
                                                            value: audioCore.channelEQBand1Qs[audioWin.selectedChannel]
                                                            onMoved: audioCore.updateChannelEQQ(audioWin.selectedChannel, 1, value)
                                                        }
                                                        Text { text: audioCore.channelEQBand1Qs[audioWin.selectedChannel].toFixed(2); color: "#ffc72c"; font.pixelSize: 8; font.family: "Courier New"; width: 28 }
                                                    }
                                                }
                                            }

                                            // Spacer line between bands
                                            Rectangle {
                                                Layout.fillWidth: true
                                                height: 1
                                                color: "#1e222b"
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
                                                        text: audioCore.channelEQBand2Dynamics[audioWin.selectedChannel] ? "DYN ON" : "DYN OFF"
                                                        implicitWidth: 46; implicitHeight: 16
                                                        background: Rectangle { color: audioCore.channelEQBand2Dynamics[audioWin.selectedChannel] ? "#ff9500" : "#1a1f29"; radius: 3 }
                                                        contentItem: Text { text: parent.text; color: audioCore.channelEQBand2Dynamics[audioWin.selectedChannel] ? "#0a0c10" : "#8a8d98"; font.pixelSize: 7; font.bold: true; anchors.centerIn: parent }
                                                        onClicked: audioCore.updateChannelEQDynamic(audioWin.selectedChannel, 2, !audioCore.channelEQBand2Dynamics[audioWin.selectedChannel])
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
                                                            value: audioCore.channelEQBand2Gains[audioWin.selectedChannel]
                                                            onMoved: audioCore.updateChannelEQ(audioWin.selectedChannel, 2, value)
                                                        }
                                                        Text { text: audioCore.channelEQBand2Gains[audioWin.selectedChannel].toFixed(1) + "dB"; color: "#ff9500"; font.pixelSize: 8; font.family: "Courier New"; width: 35 }
                                                    }

                                                    // Frequency
                                                    RowLayout {
                                                        Layout.fillWidth: true; Layout.preferredWidth: 1; spacing: 4
                                                        Text { text: "F"; color: "#8a8d98"; font.pixelSize: 8; font.bold: true }
                                                        PremiumSlider {
                                                            Layout.fillWidth: true; accentColor: "#ff9500"
                                                            from: 0.0; to: 1.0
                                                            value: root.getEQFreqSliderVal(2, audioWin.selectedChannel)
                                                            onMoved: audioCore.updateChannelEQFreq(audioWin.selectedChannel, 2, root.getBandMinFreq(2) * Math.pow(root.getBandMaxFreq(2) / root.getBandMinFreq(2), value))
                                                        }
                                                        Text {
                                                            text: {
                                                                var f = root.getEQFreq(2, audioWin.selectedChannel);
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
                                                            value: audioCore.channelEQBand2Qs[audioWin.selectedChannel]
                                                            onMoved: audioCore.updateChannelEQQ(audioWin.selectedChannel, 2, value)
                                                        }
                                                        Text { text: audioCore.channelEQBand2Qs[audioWin.selectedChannel].toFixed(2); color: "#ff9500"; font.pixelSize: 8; font.family: "Courier New"; width: 28 }
                                                    }
                                                }
                                            }

                                            // Spacer line between bands
                                            Rectangle {
                                                Layout.fillWidth: true
                                                height: 1
                                                color: "#1e222b"
                                            }

                                            // BAND 3 (HIGH SHELF)
                                            ColumnLayout {
                                                Layout.fillWidth: true
                                                spacing: 4

                                                // Band Header
                                                RowLayout {
                                                    Layout.fillWidth: true
                                                    Text { 
                                                        text: audioCore.channelEQBand3Types[audioWin.selectedChannel] === 0 ? "HIGH SHELF" : "HIGH PEAK"
                                                        color: "#ff3b30"; font.pixelSize: 9; font.bold: true 
                                                    }
                                                    Item { Layout.fillWidth: true }
                                                    Button {
                                                        text: audioCore.channelEQBand3Types[audioWin.selectedChannel] === 0 ? "SHELF" : "BELL"
                                                        implicitWidth: 42; implicitHeight: 16
                                                        background: Rectangle { color: audioCore.channelEQBand3Types[audioWin.selectedChannel] === 0 ? "#261111" : "#1a1f29"; radius: 3 }
                                                        contentItem: Text { text: parent.text; color: "#ff3b30"; font.pixelSize: 7; font.bold: true; anchors.centerIn: parent }
                                                        onClicked: audioCore.updateChannelEQType(audioWin.selectedChannel, 3, audioCore.channelEQBand3Types[audioWin.selectedChannel] === 0 ? 1 : 0)
                                                    }
                                                    Button {
                                                        text: audioCore.channelEQBand3Dynamics[audioWin.selectedChannel] ? "DYN ON" : "DYN OFF"
                                                        implicitWidth: 46; implicitHeight: 16
                                                        background: Rectangle { color: audioCore.channelEQBand3Dynamics[audioWin.selectedChannel] ? "#ff3b30" : "#1a1f29"; radius: 3 }
                                                        contentItem: Text { text: parent.text; color: audioCore.channelEQBand3Dynamics[audioWin.selectedChannel] ? "#0a0c10" : "#8a8d98"; font.pixelSize: 7; font.bold: true; anchors.centerIn: parent }
                                                        onClicked: audioCore.updateChannelEQDynamic(audioWin.selectedChannel, 3, !audioCore.channelEQBand3Dynamics[audioWin.selectedChannel])
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
                                                            value: audioCore.channelEQBand3Gains[audioWin.selectedChannel]
                                                            onMoved: audioCore.updateChannelEQ(audioWin.selectedChannel, 3, value)
                                                        }
                                                        Text { text: audioCore.channelEQBand3Gains[audioWin.selectedChannel].toFixed(1) + "dB"; color: "#ff3b30"; font.pixelSize: 8; font.family: "Courier New"; width: 35 }
                                                    }

                                                    // Frequency
                                                    RowLayout {
                                                        Layout.fillWidth: true; Layout.preferredWidth: 1; spacing: 4
                                                        Text { text: "F"; color: "#8a8d98"; font.pixelSize: 8; font.bold: true }
                                                        PremiumSlider {
                                                            Layout.fillWidth: true; accentColor: "#ff3b30"
                                                            from: 0.0; to: 1.0
                                                            value: root.getEQFreqSliderVal(3, audioWin.selectedChannel)
                                                            onMoved: audioCore.updateChannelEQFreq(audioWin.selectedChannel, 3, root.getBandMinFreq(3) * Math.pow(root.getBandMaxFreq(3) / root.getBandMinFreq(3), value))
                                                        }
                                                        Text {
                                                            text: {
                                                                var f = root.getEQFreq(3, audioWin.selectedChannel);
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
                                                            value: audioCore.channelEQBand3Qs[audioWin.selectedChannel]
                                                            onMoved: audioCore.updateChannelEQQ(audioWin.selectedChannel, 3, value)
                                                        }
                                                        Text { text: audioCore.channelEQBand3Qs[audioWin.selectedChannel].toFixed(2); color: "#ff3b30"; font.pixelSize: 8; font.family: "Courier New"; width: 28 }
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }

                        // Page 3: Compressor & De-Esser / Transient Designer
                                                ScrollView {
                            visible: dspInspectorPanel.activeDspTab === 2
                            anchors.fill: parent
                            clip: true
                            ColumnLayout {
                                width: parent.width - 20
                                spacing: 10
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
                                                text: audioCore.channelCompBypasses[audioWin.selectedChannel] ? "BYPASSED" : "ACTIVE"
                                                implicitWidth: 55; implicitHeight: 16
                                                background: Rectangle { color: audioCore.channelCompBypasses[audioWin.selectedChannel] ? "#ff3b30" : "#11261d"; radius: 3 }
                                                contentItem: Text { text: parent.text; color: "#ffffff"; font.pixelSize: 7; font.bold: true; anchors.centerIn: parent }
                                                onClicked: audioCore.updateChannelCompressor(audioWin.selectedChannel, audioCore.channelCompThresholds[audioWin.selectedChannel], audioCore.channelCompRatios[audioWin.selectedChannel], audioCore.channelCompMakeups[audioWin.selectedChannel], audioCore.channelCompAttacks[audioWin.selectedChannel], audioCore.channelCompReleases[audioWin.selectedChannel], audioCore.channelCompModes[audioWin.selectedChannel], !audioCore.channelCompBypasses[audioWin.selectedChannel])
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
                                                        color: audioCore.channelCompModes[audioWin.selectedChannel] === index ? "#ff9500" : "#1a1f29"
                                                        radius: 4
                                                    }
                                                    contentItem: Text {
                                                        text: parent.text
                                                        color: audioCore.channelCompModes[audioWin.selectedChannel] === index ? "#0a0c10" : "#8a8d98"
                                                        font.pixelSize: 7; font.bold: true; anchors.centerIn: parent
                                                    }
                                                     onClicked: audioCore.updateChannelCompressor(audioWin.selectedChannel, audioCore.channelCompThresholds[audioWin.selectedChannel], audioCore.channelCompRatios[audioWin.selectedChannel], audioCore.channelCompMakeups[audioWin.selectedChannel], audioCore.channelCompAttacks[audioWin.selectedChannel], audioCore.channelCompReleases[audioWin.selectedChannel], index, audioCore.channelCompBypasses[audioWin.selectedChannel])
                                                }
                                            }
                                        }

                                        // Threshold
                                        RowLayout {
                                            Layout.fillWidth: true
                                            spacing: 8
                                            Text { text: "THRESH"; color: "#8a8d98"; font.pixelSize: 8; width: 40 }
                                            PremiumSlider {
                                                Layout.fillWidth: true
                                                accentColor: "#ff9500"
                                                from: -60.0; to: 0.0
                                                value: audioCore.channelCompThresholds[audioWin.selectedChannel]
                                                onMoved: audioCore.updateChannelCompressor(audioWin.selectedChannel, value, audioCore.channelCompRatios[audioWin.selectedChannel], audioCore.channelCompMakeups[audioWin.selectedChannel], audioCore.channelCompAttacks[audioWin.selectedChannel], audioCore.channelCompReleases[audioWin.selectedChannel], audioCore.channelCompModes[audioWin.selectedChannel], audioCore.channelCompBypasses[audioWin.selectedChannel])
                                            }
                                            Text { text: Math.round(audioCore.channelCompThresholds[audioWin.selectedChannel]) + "dB"; color: "#ff9500"; font.pixelSize: 8; font.family: "Courier New"; width: 35 }
                                        }

                                        // Ratio
                                        RowLayout {
                                            Layout.fillWidth: true
                                            spacing: 8
                                            Text { text: "RATIO"; color: "#8a8d98"; font.pixelSize: 8; width: 40 }
                                            PremiumSlider {
                                                Layout.fillWidth: true
                                                accentColor: "#ff9500"
                                                from: 1.0; to: 20.0
                                                value: audioCore.channelCompRatios[audioWin.selectedChannel]
                                                onMoved: audioCore.updateChannelCompressor(audioWin.selectedChannel, audioCore.channelCompThresholds[audioWin.selectedChannel], value, audioCore.channelCompMakeups[audioWin.selectedChannel], audioCore.channelCompAttacks[audioWin.selectedChannel], audioCore.channelCompReleases[audioWin.selectedChannel], audioCore.channelCompModes[audioWin.selectedChannel], audioCore.channelCompBypasses[audioWin.selectedChannel])
                                            }
                                            Text { text: audioCore.channelCompRatios[audioWin.selectedChannel].toFixed(1) + ":1"; color: "#ff9500"; font.pixelSize: 8; font.family: "Courier New"; width: 35 }
                                        }

                                        // Makeup
                                        RowLayout {
                                            Layout.fillWidth: true
                                            spacing: 8
                                            Text { text: "MAKEUP"; color: "#8a8d98"; font.pixelSize: 8; width: 40 }
                                            PremiumSlider {
                                                Layout.fillWidth: true
                                                accentColor: "#ff9500"
                                                from: 0.0; to: 24.0
                                                value: audioCore.channelCompMakeups[audioWin.selectedChannel]
                                                onMoved: audioCore.updateChannelCompressor(audioWin.selectedChannel, audioCore.channelCompThresholds[audioWin.selectedChannel], audioCore.channelCompRatios[audioWin.selectedChannel], value, audioCore.channelCompAttacks[audioWin.selectedChannel], audioCore.channelCompReleases[audioWin.selectedChannel], audioCore.channelCompModes[audioWin.selectedChannel], audioCore.channelCompBypasses[audioWin.selectedChannel])
                                            }
                                            Text { text: Math.round(audioCore.channelCompMakeups[audioWin.selectedChannel]) + "dB"; color: "#ff9500"; font.pixelSize: 8; font.family: "Courier New"; width: 35 }
                                        }

                                        // Attack / Release Row
                                        RowLayout {
                                            Layout.fillWidth: true
                                            spacing: 12

                                            RowLayout {
                                                Layout.fillWidth: true
                                                spacing: 4
                                                Text { text: "ATTACK"; color: "#8a8d98"; font.pixelSize: 8; width: 35 }
                                                PremiumSlider {
                                                    Layout.fillWidth: true
                                                    accentColor: "#ff9500"
                                                    from: 0.1; to: 200.0
                                                    value: audioCore.channelCompAttacks[audioWin.selectedChannel]
                                                    onMoved: audioCore.updateChannelCompressor(audioWin.selectedChannel, audioCore.channelCompThresholds[audioWin.selectedChannel], audioCore.channelCompRatios[audioWin.selectedChannel], audioCore.channelCompMakeups[audioWin.selectedChannel], value, audioCore.channelCompReleases[audioWin.selectedChannel], audioCore.channelCompModes[audioWin.selectedChannel], audioCore.channelCompBypasses[audioWin.selectedChannel])
                                                }
                                                Text { text: audioCore.channelCompAttacks[audioWin.selectedChannel].toFixed(1) + "ms"; color: "#ff9500"; font.pixelSize: 8; font.family: "Courier New"; width: 45 }
                                            }

                                            RowLayout {
                                                Layout.fillWidth: true
                                                spacing: 4
                                                Text { text: "RELEASE"; color: "#8a8d98"; font.pixelSize: 8; width: 45 }
                                                PremiumSlider {
                                                    Layout.fillWidth: true
                                                    accentColor: "#ff9500"
                                                    from: 10.0; to: 1000.0
                                                    value: audioCore.channelCompReleases[audioWin.selectedChannel]
                                                    onMoved: audioCore.updateChannelCompressor(audioWin.selectedChannel, audioCore.channelCompThresholds[audioWin.selectedChannel], audioCore.channelCompRatios[audioWin.selectedChannel], audioCore.channelCompMakeups[audioWin.selectedChannel], audioCore.channelCompAttacks[audioWin.selectedChannel], value, audioCore.channelCompModes[audioWin.selectedChannel], audioCore.channelCompBypasses[audioWin.selectedChannel])
                                                }
                                                Text { text: Math.round(audioCore.channelCompReleases[audioWin.selectedChannel]) + "ms"; color: "#ff9500"; font.pixelSize: 8; font.family: "Courier New"; width: 45 }
                                            }
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
                                                text: audioCore.channelDeEsserBypasses[audioWin.selectedChannel] ? "BYPASSED" : "ACTIVE"
                                                implicitWidth: 55; implicitHeight: 16
                                                background: Rectangle { color: audioCore.channelDeEsserBypasses[audioWin.selectedChannel] ? "#ff3b30" : "#11261d"; radius: 3 }
                                                contentItem: Text { text: parent.text; color: "#ffffff"; font.pixelSize: 7; font.bold: true; anchors.centerIn: parent }
                                                onClicked: audioCore.updateChannelDeEsser(audioWin.selectedChannel, audioCore.channelDeEsserFreqs[audioWin.selectedChannel], audioCore.channelDeEsserThresholds[audioWin.selectedChannel], !audioCore.channelDeEsserBypasses[audioWin.selectedChannel])
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
                                                value: audioCore.channelDeEsserFreqs[audioWin.selectedChannel]
                                                onMoved: audioCore.updateChannelDeEsser(audioWin.selectedChannel, value, audioCore.channelDeEsserThresholds[audioWin.selectedChannel], audioCore.channelDeEsserBypasses[audioWin.selectedChannel])
                                            }
                                            Text { text: Math.round(audioCore.channelDeEsserFreqs[audioWin.selectedChannel]) + "Hz"; color: "#00d084"; font.pixelSize: 8; font.family: "Courier New"; width: 40 }
                                        }

                                        RowLayout {
                                            Layout.fillWidth: true
                                            spacing: 6
                                            Text { text: "THRESH"; color: "#8a8d98"; font.pixelSize: 8; width: 35 }
                                            PremiumSlider {
                                                Layout.fillWidth: true
                                                accentColor: "#ff9500"
                                                from: -60.0; to: 0.0
                                                value: audioCore.channelDeEsserThresholds[audioWin.selectedChannel]
                                                onMoved: audioCore.updateChannelDeEsser(audioWin.selectedChannel, audioCore.channelDeEsserFreqs[audioWin.selectedChannel], value, audioCore.channelDeEsserBypasses[audioWin.selectedChannel])
                                            }
                                            Text { text: Math.round(audioCore.channelDeEsserThresholds[audioWin.selectedChannel]) + "dB"; color: "#ff9500"; font.pixelSize: 8; font.family: "Courier New"; width: 40 }
                                        }

                                        // Transient Designer
                                        RowLayout {
                                            Layout.fillWidth: true
                                            Text { text: "TRANSIENT DESIGNER"; color: "#8a8d98"; font.pixelSize: 9; font.bold: true }
                                            Item { Layout.fillWidth: true }
                                            Button {
                                                text: audioCore.channelTransientBypasses[audioWin.selectedChannel] ? "BYPASSED" : "ACTIVE"
                                                implicitWidth: 55; implicitHeight: 16
                                                background: Rectangle { color: audioCore.channelTransientBypasses[audioWin.selectedChannel] ? "#ff3b30" : "#11261d"; radius: 3 }
                                                contentItem: Text { text: parent.text; color: "#ffffff"; font.pixelSize: 7; font.bold: true; anchors.centerIn: parent }
                                                onClicked: audioCore.updateChannelTransient(audioWin.selectedChannel, audioCore.channelTransientAttacks[audioWin.selectedChannel], audioCore.channelTransientSustains[audioWin.selectedChannel], !audioCore.channelTransientBypasses[audioWin.selectedChannel])
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
                                                value: audioCore.channelTransientAttacks[audioWin.selectedChannel]
                                                onMoved: audioCore.updateChannelTransient(audioWin.selectedChannel, value, audioCore.channelTransientSustains[audioWin.selectedChannel], audioCore.channelTransientBypasses[audioWin.selectedChannel])
                                            }
                                            Text { text: (audioCore.channelTransientAttacks[audioWin.selectedChannel] >= 0 ? "+" : "") + Math.round(audioCore.channelTransientAttacks[audioWin.selectedChannel] * 15) + "dB"; color: "#00d084"; font.pixelSize: 8; font.family: "Courier New"; width: 40 }
                                        }
                                    }
                                }
                            }
                        }

                        // Page 4: Gate & Output Limiter
                        ScrollView {
                            visible: dspInspectorPanel.activeDspTab === 3
                            anchors.fill: parent
                            clip: true
                            ColumnLayout {
                                width: parent.width - 20
                                spacing: 10
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
                                                text: audioCore.channelGateBypasses[audioWin.selectedChannel] ? "BYPASSED" : "ACTIVE"
                                                implicitWidth: 55; implicitHeight: 16
                                                background: Rectangle { color: audioCore.channelGateBypasses[audioWin.selectedChannel] ? "#ff3b30" : "#11261d"; radius: 3 }
                                                contentItem: Text { text: parent.text; color: "#ffffff"; font.pixelSize: 7; font.bold: true; anchors.centerIn: parent }
                                                onClicked: audioCore.updateChannelGate(audioWin.selectedChannel, audioCore.channelGateThresholds[audioWin.selectedChannel], audioCore.channelGateRanges[audioWin.selectedChannel], audioCore.channelGateAttacks[audioWin.selectedChannel], audioCore.channelGateReleases[audioWin.selectedChannel], audioCore.channelGateHolds[audioWin.selectedChannel], !audioCore.channelGateBypasses[audioWin.selectedChannel])
                                            }
                                        }

                                        // Threshold
                                        RowLayout {
                                            Layout.fillWidth: true
                                            spacing: 8
                                            Text { text: "THRESH"; color: "#8a8d98"; font.pixelSize: 8; width: 40 }
                                            PremiumSlider {
                                                Layout.fillWidth: true
                                                accentColor: "#00e5ff"
                                                from: -80.0; to: 0.0
                                                value: audioCore.channelGateThresholds[audioWin.selectedChannel]
                                                onMoved: audioCore.updateChannelGate(audioWin.selectedChannel, value, audioCore.channelGateRanges[audioWin.selectedChannel], audioCore.channelGateAttacks[audioWin.selectedChannel], audioCore.channelGateReleases[audioWin.selectedChannel], audioCore.channelGateHolds[audioWin.selectedChannel], audioCore.channelGateBypasses[audioWin.selectedChannel])
                                            }
                                            Text { text: Math.round(audioCore.channelGateThresholds[audioWin.selectedChannel]) + "dB"; color: "#00e5ff"; font.pixelSize: 8; font.family: "Courier New"; width: 35 }
                                        }

                                        // Range
                                        RowLayout {
                                            Layout.fillWidth: true
                                            spacing: 8
                                            Text { text: "RANGE"; color: "#8a8d98"; font.pixelSize: 8; width: 40 }
                                            PremiumSlider {
                                                Layout.fillWidth: true
                                                accentColor: "#00e5ff"
                                                from: -80.0; to: 0.0
                                                value: audioCore.channelGateRanges[audioWin.selectedChannel]
                                                onMoved: audioCore.updateChannelGate(audioWin.selectedChannel, audioCore.channelGateThresholds[audioWin.selectedChannel], value, audioCore.channelGateAttacks[audioWin.selectedChannel], audioCore.channelGateReleases[audioWin.selectedChannel], audioCore.channelGateHolds[audioWin.selectedChannel], audioCore.channelGateBypasses[audioWin.selectedChannel])
                                            }
                                            Text { text: Math.round(audioCore.channelGateRanges[audioWin.selectedChannel]) + "dB"; color: "#00e5ff"; font.pixelSize: 8; font.family: "Courier New"; width: 35 }
                                        }

                                        RowLayout {
                                            Layout.fillWidth: true
                                            spacing: 12

                                            // Attack
                                            RowLayout {
                                                Layout.fillWidth: true
                                                spacing: 4
                                                Text { text: "ATTACK"; color: "#8a8d98"; font.pixelSize: 8; width: 35 }
                                                PremiumSlider {
                                                    Layout.fillWidth: true
                                                    accentColor: "#00e5ff"
                                                    from: 0.1; to: 100.0
                                                    value: audioCore.channelGateAttacks[audioWin.selectedChannel]
                                                    onMoved: audioCore.updateChannelGate(audioWin.selectedChannel, audioCore.channelGateThresholds[audioWin.selectedChannel], audioCore.channelGateRanges[audioWin.selectedChannel], value, audioCore.channelGateReleases[audioWin.selectedChannel], audioCore.channelGateHolds[audioWin.selectedChannel], audioCore.channelGateBypasses[audioWin.selectedChannel])
                                                }
                                                Text { text: audioCore.channelGateAttacks[audioWin.selectedChannel].toFixed(1) + "ms"; color: "#00e5ff"; font.pixelSize: 8; font.family: "Courier New"; width: 40 }
                                            }

                                            // Release
                                            RowLayout {
                                                Layout.fillWidth: true
                                                spacing: 4
                                                Text { text: "RELEASE"; color: "#8a8d98"; font.pixelSize: 8; width: 45 }
                                                PremiumSlider {
                                                    Layout.fillWidth: true
                                                    accentColor: "#00e5ff"
                                                    from: 10.0; to: 2000.0
                                                    value: audioCore.channelGateReleases[audioWin.selectedChannel]
                                                    onMoved: audioCore.updateChannelGate(audioWin.selectedChannel, audioCore.channelGateThresholds[audioWin.selectedChannel], audioCore.channelGateRanges[audioWin.selectedChannel], audioCore.channelGateAttacks[audioWin.selectedChannel], value, audioCore.channelGateHolds[audioWin.selectedChannel], audioCore.channelGateBypasses[audioWin.selectedChannel])
                                                }
                                                Text { text: Math.round(audioCore.channelGateReleases[audioWin.selectedChannel]) + "ms"; color: "#00e5ff"; font.pixelSize: 8; font.family: "Courier New"; width: 45 }
                                            }

                                            // Hold
                                            RowLayout {
                                                Layout.fillWidth: true
                                                spacing: 4
                                                Text { text: "HOLD"; color: "#8a8d98"; font.pixelSize: 8; width: 25 }
                                                PremiumSlider {
                                                    Layout.fillWidth: true
                                                    accentColor: "#00e5ff"
                                                    from: 5.0; to: 1000.0
                                                    value: audioCore.channelGateHolds[audioWin.selectedChannel]
                                                    onMoved: audioCore.updateChannelGate(audioWin.selectedChannel, audioCore.channelGateThresholds[audioWin.selectedChannel], audioCore.channelGateRanges[audioWin.selectedChannel], audioCore.channelGateAttacks[audioWin.selectedChannel], audioCore.channelGateReleases[audioWin.selectedChannel], value, audioCore.channelGateBypasses[audioWin.selectedChannel])
                                                }
                                                Text { text: Math.round(audioCore.channelGateHolds[audioWin.selectedChannel]) + "ms"; color: "#00e5ff"; font.pixelSize: 8; font.family: "Courier New"; width: 40 }
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
                                                text: audioCore.channelLimiterBypasses[audioWin.selectedChannel] ? "BYPASSED" : "ACTIVE"
                                                implicitWidth: 55; implicitHeight: 16
                                                background: Rectangle { color: audioCore.channelLimiterBypasses[audioWin.selectedChannel] ? "#ff3b30" : "#5c1111"; radius: 3 }
                                                contentItem: Text { text: parent.text; color: "#ffffff"; font.pixelSize: 7; font.bold: true; anchors.centerIn: parent }
                                                onClicked: audioCore.updateChannelLimiter(audioWin.selectedChannel, audioCore.channelLimiterThresholds[audioWin.selectedChannel], !audioCore.channelLimiterBypasses[audioWin.selectedChannel])
                                            }
                                        }

                                        RowLayout {
                                            Layout.fillWidth: true
                                            spacing: 8
                                            Text { text: "CEILING"; color: "#ff8585"; font.pixelSize: 8; width: 40 }
                                            PremiumSlider {
                                                Layout.fillWidth: true
                                                accentColor: "#ff3b30"
                                                from: -12.0; to: 0.0
                                                value: audioCore.channelLimiterThresholds[audioWin.selectedChannel]
                                                onMoved: audioCore.updateChannelLimiter(audioWin.selectedChannel, value, audioCore.channelLimiterBypasses[audioWin.selectedChannel])
                                            }
                                            Text { text: audioCore.channelLimiterThresholds[audioWin.selectedChannel].toFixed(1) + "dBFS"; color: "#ff5e5e"; font.pixelSize: 8; font.family: "Courier New"; width: 45 }
                                        }
                                    }
                                }
                            }
                        }}

    }



    // ----------------------------------------------------

    // 3. GPU VIDEO SWITCHER WINDOW

    // ----------------------------------------------------

    Window {

        id: videoWin

        visible: videoWindowOpen

        onVisibleChanged: {

            videoWindowOpen = visible;

        }

        width: 1024

        height: 576

        title: "Video Switcher Console"

        color: "#0a0c10"

        x: 100

        y: 640



        RowLayout {

            anchors.fill: parent

            anchors.margins: 15

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

                                text: "PROGRAM [PGM]: CAM " + (programCameraIdx + 1)

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

                                text: "PREVIEW [PVW]: CAM " + (previewCameraIdx + 1)

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

                                model: 4

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

                                        text: "CAM " + (index + 1)

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

                                model: 4

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

                                        text: "CAM " + (index + 1)

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

    }



    // ----------------------------------------------------

    // 4. SHOW CONTROL SANDBOX WINDOW

    // ----------------------------------------------------

    Window {

        id: sandboxWin

        visible: sandboxWindowOpen

        onVisibleChanged: {

            sandboxWindowOpen = visible;

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
                                    audioWin.uiInputsCount = 16
                                    audioWin.uiBusesCount = 4
                                    audioWin.uiAuxesCount = 4
                                    audioWin.uiDCAsCount = 4
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
                                            onClicked: if (audioWin.uiInputsCount > 1) audioWin.uiInputsCount--
                                        }
                                        Text {
                                            text: audioWin.uiInputsCount
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
                                            onClicked: if (audioWin.uiInputsCount < 24) audioWin.uiInputsCount++
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
                                            onClicked: if (audioWin.uiBusesCount > 0) audioWin.uiBusesCount--
                                        }
                                        Text {
                                            text: audioWin.uiBusesCount
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
                                            onClicked: if (audioWin.uiBusesCount < 8) audioWin.uiBusesCount++
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
                                            onClicked: if (audioWin.uiAuxesCount > 0) audioWin.uiAuxesCount--
                                        }
                                        Text {
                                            text: audioWin.uiAuxesCount
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
                                            onClicked: if (audioWin.uiAuxesCount < 8) audioWin.uiAuxesCount++
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
                                            onClicked: if (audioWin.uiDCAsCount > 0) audioWin.uiDCAsCount--
                                        }
                                        Text {
                                            text: audioWin.uiDCAsCount
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
                                            onClicked: if (audioWin.uiDCAsCount < 8) audioWin.uiDCAsCount++
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
                                    audioCore.configureShowChannels(audioWin.uiInputsCount, audioWin.uiBusesCount, audioWin.uiAuxesCount, audioWin.uiDCAsCount);
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
                                                        var minF = root.getBandMinFreq(grabbedBand);
                                                        var maxF = root.getBandMaxFreq(grabbedBand);
                                                        
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
                                                            value: root.getEQFreqSliderVal(0, rightPanel.selectedChannel)
                                                            onMoved: audioCore.updateChannelEQFreq(rightPanel.selectedChannel, 0, root.getBandMinFreq(0) * Math.pow(root.getBandMaxFreq(0) / root.getBandMinFreq(0), value))
                                                        }
                                                        Text {
                                                            text: {
                                                                var f = root.getEQFreq(0, rightPanel.selectedChannel);
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
                                                            value: root.getEQFreqSliderVal(1, rightPanel.selectedChannel)
                                                            onMoved: audioCore.updateChannelEQFreq(rightPanel.selectedChannel, 1, root.getBandMinFreq(1) * Math.pow(root.getBandMaxFreq(1) / root.getBandMinFreq(1), value))
                                                        }
                                                        Text {
                                                            text: {
                                                                var f = root.getEQFreq(1, rightPanel.selectedChannel);
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
                                                            value: root.getEQFreqSliderVal(2, rightPanel.selectedChannel)
                                                            onMoved: audioCore.updateChannelEQFreq(rightPanel.selectedChannel, 2, root.getBandMinFreq(2) * Math.pow(root.getBandMaxFreq(2) / root.getBandMinFreq(2), value))
                                                        }
                                                        Text {
                                                            text: {
                                                                var f = root.getEQFreq(2, rightPanel.selectedChannel);
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
                                                            value: root.getEQFreqSliderVal(3, rightPanel.selectedChannel)
                                                            onMoved: audioCore.updateChannelEQFreq(rightPanel.selectedChannel, 3, root.getBandMinFreq(3) * Math.pow(root.getBandMaxFreq(3) / root.getBandMinFreq(3), value))
                                                        }
                                                        Text {
                                                            text: {
                                                                var f = root.getEQFreq(3, rightPanel.selectedChannel);
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
                            width: rightPanel.width - 25
                            spacing: 12

                            Text {
                                text: "AUDIO PATCH MATRIX & ROUTING"
                                color: "#00BDD6"
                                font.pixelSize: 11
                                font.bold: true
                                Layout.fillWidth: true
                            }

                            // --- DEVICE CONFIGURATION PANEL ---
                            Rectangle {
                                Layout.fillWidth: true
                                implicitHeight: 120
                                color: "#101216"
                                radius: 8
                                border.color: "#252b36"
                                border.width: 1

                                ColumnLayout {
                                    anchors.fill: parent
                                    anchors.margins: 10
                                    spacing: 8

                                    Text {
                                        text: "ASIO DEVICE CONFIGURATION"
                                        color: "#8a8d98"
                                        font.pixelSize: 9
                                        font.bold: true
                                    }

                                    RowLayout {
                                        Layout.fillWidth: true
                                        spacing: 6
                                        
                                        ColumnLayout {
                                            Layout.fillWidth: true
                                            Text { text: "DRIVER TYPE"; color: "#8a8d98"; font.pixelSize: 8; font.bold: true }
                                            ComboBox {
                                                id: driverCombo
                                                Layout.fillWidth: true
                                                implicitHeight: 24
                                                model: ["ASIO (Professional)", "WASAPI Shared", "DirectSound"]
                                                currentIndex: 0
                                                onCurrentIndexChanged: audioCore.configureDevice(currentText, audioCore.activeDevice, audioCore.activeSampleRate, audioCore.activeBufferSize)
                                            }
                                        }

                                        ColumnLayout {
                                            Layout.fillWidth: true
                                            Text { text: "HARDWARE INTERFACE"; color: "#8a8d98"; font.pixelSize: 8; font.bold: true }
                                            ComboBox {
                                                id: deviceCombo
                                                Layout.fillWidth: true
                                                implicitHeight: 24
                                                model: ["Dante Virtual Soundcard", "ASIO Focusrite USB", "Primary Audio Interface"]
                                                currentIndex: 0
                                                onCurrentIndexChanged: audioCore.configureDevice(driverCombo.currentText, currentText, audioCore.activeSampleRate, audioCore.activeBufferSize)
                                            }
                                        }
                                    }

                                    RowLayout {
                                        Layout.fillWidth: true
                                        spacing: 6

                                        ColumnLayout {
                                            Layout.fillWidth: true
                                            Text { text: "SAMPLE RATE"; color: "#8a8d98"; font.pixelSize: 8; font.bold: true }
                                            ComboBox {
                                                id: rateCombo
                                                Layout.fillWidth: true
                                                implicitHeight: 24
                                                model: ["48000 Hz", "44100 Hz", "96000 Hz"]
                                                currentIndex: 0
                                                onCurrentIndexChanged: {
                                                    var val = parseInt(currentText);
                                                    audioCore.activeSampleRate = val;
                                                }
                                            }
                                        }

                                        ColumnLayout {
                                            Layout.fillWidth: true
                                            Text { text: "BUFFER SIZE"; color: "#8a8d98"; font.pixelSize: 8; font.bold: true }
                                            ComboBox {
                                                id: bufferCombo
                                                Layout.fillWidth: true
                                                implicitHeight: 24
                                                model: ["128 samples", "64 samples", "256 samples", "512 samples"]
                                                currentIndex: 0
                                                onCurrentIndexChanged: {
                                                    var val = parseInt(currentText);
                                                    audioCore.activeBufferSize = val;
                                                }
                                            }
                                        }
                                    }
                                }
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
                                visible: patchBoardScrollView.patchSubTab === 0
                                Layout.fillWidth: true
                                implicitHeight: inputPatchLayout.implicitHeight + 24
                                color: "#0a0c10"
                                radius: 8
                                border.color: "#252b36"
                                border.width: 1

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
                                            spacing: 12
                                            Layout.fillWidth: true
                                            property int channelIdx: index
                                            
                                            // Channel Label (CH 1..24)
                                            Rectangle {
                                                width: 40; height: 24
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
                                                Layout.preferredWidth: 80
                                            }
                                            
                                            // Source Type ComboBox
                                            ComboBox {
                                                id: srcTypeCombo
                                                implicitHeight: 24
                                                Layout.preferredWidth: 130
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
                                                        var processes = Object.keys(audioCore.availableProcesses);
                                                        if (processes.length > 0) {
                                                            var procName = processes[0];
                                                            var pid = audioCore.availableProcesses[procName];
                                                            audioCore.setInputPatch(channelIdx, 3, pid);
                                                            audioCore.startApplicationCapture(channelIdx, procName, pid);
                                                        } else {
                                                            audioCore.setInputPatch(channelIdx, 3, 0);
                                                        }
                                                    } else {
                                                        audioCore.setInputPatch(channelIdx, newType, 0);
                                                    }
                                                }
                                            }
                                            
                                            // Source Detail ComboBox
                                            ComboBox {
                                                id: srcDetailCombo
                                                implicitHeight: 24
                                                Layout.preferredWidth: 150
                                                enabled: srcTypeCombo.currentIndex > 0
                                                
                                                model: {
                                                    var type = srcTypeCombo.currentIndex;
                                                    if (type === 1) {
                                                        return [
                                                            "ASIO Port 1", "ASIO Port 2", "ASIO Port 3", "ASIO Port 4",
                                                            "ASIO Port 5", "ASIO Port 6", "ASIO Port 7", "ASIO Port 8",
                                                            "ASIO Port 9", "ASIO Port 10", "ASIO Port 11", "ASIO Port 12",
                                                            "ASIO Port 13", "ASIO Port 14", "ASIO Port 15", "ASIO Port 16"
                                                        ];
                                                    } else if (type === 2) {
                                                        return ["1kHz Sine Wave", "Pink Noise"];
                                                    } else if (type === 3) {
                                                        return Object.keys(audioCore.availableProcesses);
                                                    } else {
                                                        return ["-"];
                                                    }
                                                }
                                                
                                                currentIndex: {
                                                    var type = srcTypeCombo.currentIndex;
                                                    if (type === 0) return 0;
                                                    if (audioCore.inputPatches && audioCore.inputPatches[channelIdx] !== undefined) {
                                                        var backendType = audioCore.inputPatches[channelIdx].type;
                                                        if (backendType === type) {
                                                            var patch = audioCore.inputPatches[channelIdx];
                                                            if (type === 3) {
                                                                var processes = Object.keys(audioCore.availableProcesses);
                                                                for (var i = 0; i < processes.length; i++) {
                                                                    if (audioCore.availableProcesses[processes[i]] === patch.index) {
                                                                        return i;
                                                                    }
                                                                }
                                                                return -1; // fallback when PID is no longer running
                                                            }
                                                            return patch.index;
                                                        }
                                                    }
                                                    return 0;
                                                }
                                                
                                                onActivated: {
                                                    var type = srcTypeCombo.currentIndex;
                                                    if (type === 1 || type === 2) {
                                                        audioCore.setInputPatch(channelIdx, type, index);
                                                    } else if (type === 3) {
                                                        var processes = Object.keys(audioCore.availableProcesses);
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
                                                    if (srcTypeCombo.currentIndex === 3) {
                                                        var processes = Object.keys(audioCore.availableProcesses);
                                                        var selIdx = srcDetailCombo.currentIndex;
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
                                                    property bool isRouteActive: isBus ? root.checkRouteActive(rIdx, cIdx) : ((audioCore.channelDcaMasks[rIdx] & (1 << dcaIdx)) !== 0)
                                                    property int tapPoint: isBus ? root.getRouteTap(rIdx, cIdx) : 0

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
                                                                root.toggleRoute(rIdx, parent.cIdx);
                                                            } else {
                                                                var active = parent.isRouteActive;
                                                                audioCore.updateChannelDCAMapping(rIdx, parent.dcaIdx, !active);
                                                            }
                                                        }
                                                        onDoubleClicked: {
                                                            if (parent.isBus) {
                                                                var pt = cellMouseArea.mapToItem(root.contentItem, cellMouseArea.width/2, cellMouseArea.height/2);
                                                                root.openRouteEditor(rIdx, parent.cIdx, pt);
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
                                        text: "PHYSICAL OUTPUT CHANNEL PATCHING"
                                        color: "#8a8d98"
                                        font.pixelSize: 9
                                        font.bold: true
                                    }

                                    Repeater {
                                        model: 8
                                        delegate: RowLayout {
                                            spacing: 12
                                            Layout.fillWidth: true
                                            property int portIdx: index

                                            // Label
                                            Rectangle {
                                                width: 120; height: 24
                                                color: "#1a1c1e"
                                                radius: 4
                                                border.color: "#252b36"
                                                Text {
                                                    anchors.centerIn: parent
                                                    text: "ASIO Output " + (portIdx + 1)
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
                                                model: ["Unpatched", "Master L", "Master R", "Aux 1", "Aux 2", "Aux 3", "Aux 4", "Rec L", "Rec R"]
                                                
                                                currentIndex: {
                                                    if (audioCore.outputPatches && audioCore.outputPatches[portIdx] !== undefined) {
                                                        var patch = audioCore.outputPatches[portIdx];
                                                        if (patch.active) {
                                                            return patch.busIdx + 1;
                                                        }
                                                    }
                                                    return 0;
                                                }

                                                onActivated: {
                                                    var active = index > 0;
                                                    var busIdx = index - 1;
                                                    audioCore.setOutputPatch(portIdx, busIdx, active);
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


}

}}}
