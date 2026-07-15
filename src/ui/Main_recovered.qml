                                                RowLayout {
                                                    Layout.fillWidth: true
                                                    spacing: 4
                                                    Repeater {
                                                        model: 4
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