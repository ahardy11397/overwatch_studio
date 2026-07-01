import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Overwatch.Core

Window {
    id: audioWin
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
    property variant busVolumes: [ 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0 ]
    property variant busMutes: [ false, false, false, false, false, false, false, false ]
    property variant auxVolumes: [ 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0 ]
    property variant auxMutes: [ false, false, false, false, false, false, false, false ]
    property variant channelSoloStates: [
        false, false, false, false,   false, false, false, false,
        false, false, false, false,   false, false, false, false,
        false, false, false, false,   false, false, false, false
    ]
    property double masterVolume: 1.0
    property bool masterMute: false
    property int activeBank: 0

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

    function setVolume(idx, val) {
        var temp = channelVolumes;
        temp[idx] = val;
        channelVolumes = temp;
        audioCore.updateChannelVolume(idx, val);
    }

    function logStateBeforeChange() {
        audioCore.captureUndoSnapshot(
            channelVolumes,
            channelMutes,
            masterVolume,
            masterMute,
            audioWin.programCameraIdx,
            audioWin.previewCameraIdx,
            audioCore.fadeToBlack
        );
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



                                property int chIdx: audioWin.activeBank * 8 + index

                                

                                property bool isDCA: audioWin.faderAssignments[audioWin.activeBank][index].type === "dca"

                                property bool isInput: audioWin.faderAssignments[audioWin.activeBank][index].type === "input"

                                property bool isAux: audioWin.faderAssignments[audioWin.activeBank][index].type === "aux"

                                property bool isBus: audioWin.faderAssignments[audioWin.activeBank][index].type === "bus"

                                property bool isFX: audioWin.faderAssignments[audioWin.activeBank][index].type === "fx"

                                

                                property int resolvedIdx: audioWin.faderAssignments[audioWin.activeBank][index].actualIndex



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
                                                var type = audioWin.faderAssignments[audioWin.activeBank][index].type;
                                                var actIdx = audioWin.faderAssignments[audioWin.activeBank][index].actualIndex;
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
                                                
                                                temp[audioWin.activeBank][index] = newObj;
                                                audioWin.faderAssignments = temp;
                                            }
                                        }
                                    }







                                    // DCA & Mute Group Indicator Badges

                                    RowLayout {

                                        Layout.alignment: Qt.AlignHCenter

                                        spacing: 3

                                        height: 12

                                        visible: audioWin.activeBank < 3



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
                                              checked: getMuteForFader(audioWin.faderAssignments[audioWin.activeBank][index].type, resolvedIdx)

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
                                                   var faderType = audioWin.faderAssignments[audioWin.activeBank][index].type;
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
                                              var type = audioWin.faderAssignments[audioWin.activeBank][index].type;
                                              if (type === "input") return "CH " + (resolvedIdx + 1);
                                              return type.toUpperCase() + " " + (resolvedIdx + 1);
                                          }
                                                                                     color: {
                                               var type = audioWin.faderAssignments[audioWin.activeBank][index].type;
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

                                         visible: (audioWin.activeBank < 3) && (chIdx < 24)

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
                                                      var faderType = audioWin.faderAssignments[audioWin.activeBank][index].type;
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
                                                 y: (parent.height - height - 30) * (1.0 - getVolumeForFader(audioWin.faderAssignments[audioWin.activeBank][index].type, resolvedIdx)) + 15

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
                                                             var type = audioWin.faderAssignments[audioWin.activeBank][index].type;
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
                                                     
                                                     var faderType = audioWin.faderAssignments[audioWin.activeBank][index].type;
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
                                        text: Math.round(getVolumeForFader(audioWin.faderAssignments[audioWin.activeBank][index].type, resolvedIdx) * 100) + "%"
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
                                                        var minF = audioWin.getBandMinFreq(grabbedBand);
                                                        var maxF = audioWin.getBandMaxFreq(grabbedBand);
                                                        
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
                                                            value: audioWin.getEQFreqSliderVal(0, audioWin.selectedChannel)
                                                            onMoved: audioCore.updateChannelEQFreq(audioWin.selectedChannel, 0, audioWin.getBandMinFreq(0) * Math.pow(audioWin.getBandMaxFreq(0) / audioWin.getBandMinFreq(0), value))
                                                        }
                                                        Text {
                                                            text: {
                                                                var f = audioWin.getEQFreq(0, audioWin.selectedChannel);
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
                                                            value: audioWin.getEQFreqSliderVal(1, audioWin.selectedChannel)
                                                            onMoved: audioCore.updateChannelEQFreq(audioWin.selectedChannel, 1, audioWin.getBandMinFreq(1) * Math.pow(audioWin.getBandMaxFreq(1) / audioWin.getBandMinFreq(1), value))
                                                        }
                                                        Text {
                                                            text: {
                                                                var f = audioWin.getEQFreq(1, audioWin.selectedChannel);
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
                                                            value: audioWin.getEQFreqSliderVal(2, audioWin.selectedChannel)
                                                            onMoved: audioCore.updateChannelEQFreq(audioWin.selectedChannel, 2, audioWin.getBandMinFreq(2) * Math.pow(audioWin.getBandMaxFreq(2) / audioWin.getBandMinFreq(2), value))
                                                        }
                                                        Text {
                                                            text: {
                                                                var f = audioWin.getEQFreq(2, audioWin.selectedChannel);
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
                                                            value: audioWin.getEQFreqSliderVal(3, audioWin.selectedChannel)
                                                            onMoved: audioCore.updateChannelEQFreq(audioWin.selectedChannel, 3, audioWin.getBandMinFreq(3) * Math.pow(audioWin.getBandMaxFreq(3) / audioWin.getBandMinFreq(3), value))
                                                        }
                                                        Text {
                                                            text: {
                                                                var f = audioWin.getEQFreq(3, audioWin.selectedChannel);
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
            }
        }
    }
