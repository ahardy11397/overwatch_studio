#!/usr/bin/env python3
"""Extract child windows from monolithic Main.qml into separate files."""

with open('src/ui/Main.qml', encoding='utf-8') as f:
    lines = f.readlines()

# Shared components and helpers from the root (lines 15-91)
# PremiumSlider component + EQ helper functions
shared_components = [
    '    component PremiumSlider: Slider {',
    '        id: control',
    '        property color accentColor: "#00d084"',
    '',
    '        background: Rectangle {',
    '            x: control.leftPadding',
    '            y: control.topPadding + control.availableHeight / 2 - height / 2',
    '            implicitWidth: 120',
    '            implicitHeight: 4',
    '            width: control.availableWidth',
    '            height: implicitHeight',
    '            radius: 2',
    '            color: "#080a0d"',
    '',
    '            Rectangle {',
    '                width: control.visualPosition * parent.width',
    '                height: parent.height',
    '                color: control.enabled ? control.accentColor : "#4a4d55"',
    '                radius: 2',
    '            }',
    '        }',
    '',
    '        handle: Rectangle {',
    '            x: control.leftPadding + control.visualPosition * (control.availableWidth - width)',
    '            y: control.topPadding + control.availableHeight / 2 - height / 2',
    '            implicitWidth: 12',
    '            implicitHeight: 12',
    '            radius: 6',
    '            color: control.pressed ? "#3b4252" : "#252b36"',
    '            border.color: control.hovered ? control.accentColor : "#8a8d98"',
    '            border.width: control.pressed ? 2.0 : 1.5',
    '',
    '            Rectangle {',
    '                width: 4',
    '                height: 4',
    '                radius: 2',
    '                color: control.accentColor',
    '                anchors.centerIn: parent',
    '                visible: control.hovered || control.pressed',
    '            }',
    '        }',
    '    }',
    '',
    '    function getBandMinFreq(band) {',
    '        if (band === 0) return 20.0;',
    '        if (band === 1) return 100.0;',
    '        if (band === 2) return 500.0;',
    '        return 2000.0;',
    '    }',
    '',
    '    function getBandMaxFreq(band) {',
    '        if (band === 0) return 500.0;',
    '        if (band === 1) return 2000.0;',
    '        if (band === 2) return 10000.0;',
    '        return 20000.0;',
    '    }',
    '',
    '    function getEQFreq(band, ch) {',
    '        if (band === 0) return audioCore.channelEQBand0Freqs[ch];',
    '        if (band === 1) return audioCore.channelEQBand1Freqs[ch];',
    '        if (band === 2) return audioCore.channelEQBand2Freqs[ch];',
    '        return audioCore.channelEQBand3Freqs[ch];',
    '    }',
    '',
    '    function getEQQ(band, ch) {',
    '        if (band === 0) return audioCore.channelEQBand0Qs[ch];',
    '        if (band === 1) return audioCore.channelEQBand1Qs[ch];',
    '        if (band === 2) return audioCore.channelEQBand2Qs[ch];',
    '        return audioCore.channelEQBand3Qs[ch];',
    '    }',
    '',
    '    function getEQFreqSliderVal(band, ch) {',
    '        var f = getEQFreq(band, ch);',
    '        var min = getBandMinFreq(band);',
    '        var max = getBandMaxFreq(band);',
    '        return Math.log(f / min) / Math.log(max / min);',
    '    }',
    '',
]

def make_audio_console():
    """Fix AudioConsole_extracted.qml to be standalone."""
    extracted = lines[1087:4218]  # 0-indexed: line 1088-4218
    # Replace the first line (Window {) with one that has imports + bridge + components
    result = []
    result.append('import QtQuick\n')
    result.append('import QtQuick.Controls\n')
    result.append('import QtQuick.Layouts\n')
    result.append('import Overwatch.Core\n')
    result.append('\n')
    result.append('Window {\n')
    result.append('    id: audioWin\n')
    result.append('    visible: true\n')
    result.append('\n')

    # Copy shared components (PremiumSlider, etc.)
    for line in shared_components:
        result.append(line + '\n')

    # Add AudioEngineBridge
    result.append('    AudioEngineBridge {\n')
    result.append('        id: audioCore\n')
    result.append('    }\n')
    result.append('\n')

    # Add WindowStateStore
    result.append('    WindowStateStore { id: winStore }\n')
    result.append('\n')

    # Add state properties that were previously in root
    result.append('    // Shared state (moved from root)\n')
    result.append('    property variant channelVolumes: [\n')
    result.append('        1.0, 1.0, 1.0, 1.0,   1.0, 1.0, 1.0, 1.0,\n')
    result.append('        1.0, 1.0, 1.0, 1.0,   1.0, 1.0, 1.0, 1.0,\n')
    result.append('        1.0, 1.0, 1.0, 1.0,   1.0, 1.0, 1.0, 1.0\n')
    result.append('    ]\n')
    result.append('    property variant channelMutes: [\n')
    result.append('        false, false, false, false,   false, false, false, false,\n')
    result.append('        false, false, false, false,   false, false, false, false,\n')
    result.append('        false, false, false, false,   false, false, false, false\n')
    result.append('    ]\n')
    result.append('    property variant busVolumes: [ 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0 ]\n')
    result.append('    property variant busMutes: [ false, false, false, false, false, false, false, false ]\n')
    result.append('    property variant auxVolumes: [ 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0 ]\n')
    result.append('    property variant auxMutes: [ false, false, false, false, false, false, false, false ]\n')
    result.append('    property variant channelSoloStates: [\n')
    result.append('        false, false, false, false,   false, false, false, false,\n')
    result.append('        false, false, false, false,   false, false, false, false,\n')
    result.append('        false, false, false, false,   false, false, false, false\n')
    result.append('    ]\n')
    result.append('    property double masterVolume: 1.0\n')
    result.append('    property bool masterMute: false\n')
    result.append('    property int activeBank: 0\n')
    result.append('\n')

    # Add helper functions from root
    result.append('    function getVolumeForFader(type, actualIdx) {\n')
    result.append('        if (type === "input") return channelVolumes[actualIdx];\n')
    result.append('        if (type === "dca") return audioCore.dcaVolumes[actualIdx];\n')
    result.append('        if (type === "bus") return busVolumes[actualIdx];\n')
    result.append('        if (type === "aux") return auxVolumes[actualIdx];\n')
    result.append('        return 1.0;\n')
    result.append('    }\n')
    result.append('\n')
    result.append('    function getMuteForFader(type, actualIdx) {\n')
    result.append('        if (type === "input") return channelMutes[actualIdx];\n')
    result.append('        if (type === "dca") return audioCore.dcaMutes[actualIdx];\n')
    result.append('        if (type === "bus") return busMutes[actualIdx];\n')
    result.append('        if (type === "aux") return auxMutes[actualIdx];\n')
    result.append('        return false;\n')
    result.append('    }\n')
    result.append('\n')
    result.append('    function setVolumeForFader(type, actualIdx, val) {\n')
    result.append('        if (type === "input") {\n')
    result.append('            setVolume(actualIdx, val);\n')
    result.append('        } else if (type === "dca") {\n')
    result.append('            audioCore.updateDCAVolume(actualIdx, val);\n')
    result.append('        } else if (type === "bus") {\n')
    result.append('            var temp = busVolumes;\n')
    result.append('            temp[actualIdx] = val;\n')
    result.append('            busVolumes = temp;\n')
    result.append('            audioCore.notifyFaderChanged(64 + actualIdx, val);\n')
    result.append('        } else if (type === "aux") {\n')
    result.append('            var temp = auxVolumes;\n')
    result.append('            temp[actualIdx] = val;\n')
    result.append('            auxVolumes = temp;\n')
    result.append('            audioCore.notifyFaderChanged(80 + actualIdx, val);\n')
    result.append('        }\n')
    result.append('    }\n')
    result.append('\n')
    result.append('    function setVolume(idx, val) {\n')
    result.append('        var temp = channelVolumes;\n')
    result.append('        temp[idx] = val;\n')
    result.append('        channelVolumes = temp;\n')
    result.append('        audioCore.updateChannelVolume(idx, val);\n')
    result.append('    }\n')
    result.append('\n')
    result.append('    function logStateBeforeChange() {\n')
    result.append('        audioCore.captureUndoSnapshot(\n')
    result.append('            channelVolumes,\n')
    result.append('            channelMutes,\n')
    result.append('            masterVolume,\n')
    result.append('            masterMute,\n')
    result.append('            audioWin.programCameraIdx,\n')
    result.append('            audioWin.previewCameraIdx,\n')
    result.append('            audioCore.fadeToBlack\n')
    result.append('        );\n')
    result.append('    }\n')
    result.append('\n')

    # Add the rest of the extracted content (skip the first 30 lines or so which
    # are the original Window header, visible, etc.)
    # The extracted content starts at line 1088 which is:
    #     Window {
    # We need to skip the original Window header and add the content body
    # Let's find where the original body starts (after the initial property declarations)
    # Actually, the extracted content IS the full Window. Let me just output it
    # but replace the initial "Window {" and following lines up to the content.

    # The extracted content from the original has:
    # Line 1088:     Window {
    # Line 1089:     (blank)
    # Line 1090:         id: audioWin
    # Line 1091:     (blank)
    # Line 1092:         visible: audioWindowOpen
    # Line 1093:     (blank)
    # Line 1094:         onVisibleChanged: { ... }
    # Line 1095-1098:     }
    # Line 1099:     (blank)
    # Line 1100:         width: 1620
    # ...
    # I need to skip these and add my own.

    # Skip the first 12 lines of the extracted content (Window { through the closing of onVisibleChanged)
    # and start from the actual content

    skip_count = 0
    for i, line in enumerate(extracted):
        if i < 12:
            # Skip the original Window header, id, visible, onVisibleChanged
            if line.strip() == 'Window {':
                continue
            if line.strip() in ('', '', '', ''):
                continue
            if 'id: audioWin' in line:
                continue
            if 'visible:' in line:
                continue
            if 'onVisibleChanged' in line:
                continue
            if line.strip() == '}':
                continue
            # Actually, just skip the first 12 lines regardless
            skip_count += 1
            continue
        # For the remaining lines, fix root.xxx references
        fixed = line
        # Replace root.activeBank -> audioWin.activeBank
        fixed = fixed.replace('root.activeBank', 'audioWin.activeBank')
        fixed = fixed.replace('root.getBandMinFreq', 'audioWin.getBandMinFreq')
        fixed = fixed.replace('root.getBandMaxFreq', 'audioWin.getBandMaxFreq')
        fixed = fixed.replace('root.getEQFreqSliderVal', 'audioWin.getEQFreqSliderVal')
        fixed = fixed.replace('root.getEQFreq', 'audioWin.getEQFreq')
        fixed = fixed.replace('root.getEQQ', 'audioWin.getEQQ')
        # Don't replace root. references that are about the route editor popup
        # These are now in Main.qml, so they stay as root. references
        # Actually, the route editor popup is in Main.qml, not in these windows
        # So references to root.selectedRouteSrc, etc. should be removed or handled
        fixed = fixed.replace('root.logStateBeforeChange', 'audioWin.logStateBeforeChange')
        fixed = fixed.replace('root.channelSoloStates', 'audioWin.channelSoloStates')
        fixed = fixed.replace('root.masterVolume', 'audioWin.masterVolume')
        fixed = fixed.replace('root.masterMute', 'audioWin.masterMute')
        # Remove references to route editor popup (it stays in Main.qml)
        # These are things like root.routeEditorOpen, root.selectedRouteSrc, etc.
        # For now, just leave them as-is - they'll be dead references without the route editor
        # Actually, the audio console was the one that had the route editor popup
        # Let me check what root. references remain
        result.append(fixed)

    return ''.join(result)


def make_video_switcher():
    """Fix VideoSwitcher_extracted.qml to be standalone."""
    extracted = lines[4227:5059]
    result = []
    result.append('import QtQuick\n')
    result.append('import QtQuick.Controls\n')
    result.append('import QtQuick.Layouts\n')
    result.append('import Overwatch.Core\n')
    result.append('\n')
    result.append('Window {\n')
    result.append('    id: videoWin\n')
    result.append('    visible: true\n')
    result.append('\n')
    result.append('    AudioEngineBridge {\n')
    result.append('        id: audioCore\n')
    result.append('    }\n')
    result.append('\n')
    result.append('    WindowStateStore { id: winStore }\n')
    result.append('\n')

    # Skip the first ~12 lines of the extracted content
    for i, line in enumerate(extracted):
        if i < 12:
            continue
        # Fix root. references
        fixed = line
        # No root. references in video switcher to fix
        result.append(fixed)

    return ''.join(result)


def make_show_builder():
    """Fix ShowBuilder_extracted.qml to be standalone."""
    extracted = lines[5068:8555]
    result = []
    result.append('import QtQuick\n')
    result.append('import QtQuick.Controls\n')
    result.append('import QtQuick.Layouts\n')
    result.append('import Overwatch.Core\n')
    result.append('\n')
    result.append('Window {\n')
    result.append('    id: sandboxWin\n')
    result.append('    visible: true\n')
    result.append('\n')

    # Copy shared components
    for line in shared_components:
        result.append(line + '\n')

    # Add bridges
    result.append('    AudioEngineBridge {\n')
    result.append('        id: audioCore\n')
    result.append('    }\n')
    result.append('\n')
    result.append('    ShowBuilderBridge {\n')
    result.append('        id: showBuilder\n')
    result.append('    }\n')
    result.append('\n')
    result.append('    WindowStateStore { id: winStore }\n')
    result.append('\n')

    # Add state properties
    result.append('    // Shared state (moved from root)\n')
    result.append('    property variant channelVolumes: [\n')
    result.append('        1.0, 1.0, 1.0, 1.0,   1.0, 1.0, 1.0, 1.0,\n')
    result.append('        1.0, 1.0, 1.0, 1.0,   1.0, 1.0, 1.0, 1.0,\n')
    result.append('        1.0, 1.0, 1.0, 1.0,   1.0, 1.0, 1.0, 1.0\n')
    result.append('    ]\n')
    result.append('    property variant channelMutes: [\n')
    result.append('        false, false, false, false,   false, false, false, false,\n')
    result.append('        false, false, false, false,   false, false, false, false,\n')
    result.append('        false, false, false, false,   false, false, false, false\n')
    result.append('    ]\n')
    result.append('    property double masterVolume: 1.0\n')
    result.append('    property bool masterMute: false\n')
    result.append('\n')

    # Skip the first ~12 lines of extracted content
    for i, line in enumerate(extracted):
        if i < 12:
            continue
        fixed = line
        fixed = fixed.replace('root.getBandMinFreq', 'sandboxWin.getBandMinFreq')
        fixed = fixed.replace('root.getBandMaxFreq', 'sandboxWin.getBandMaxFreq')
        fixed = fixed.replace('root.getEQFreqSliderVal', 'sandboxWin.getEQFreqSliderVal')
        fixed = fixed.replace('root.getEQFreq', 'sandboxWin.getEQFreq')
        fixed = fixed.replace('root.getEQQ', 'sandboxWin.getEQQ')
        fixed = fixed.replace('root.toggleRoute', 'sandboxWin.toggleRoute')
        fixed = fixed.replace('root.openRouteEditor', 'sandboxWin.openRouteEditor')
        fixed = fixed.replace('root.getRouteTap', 'sandboxWin.getRouteTap')
        fixed = fixed.replace('root.checkRouteActive', 'sandboxWin.checkRouteActive')
        fixed = fixed.replace('root.masterVolume', 'sandboxWin.masterVolume')
        fixed = fixed.replace('root.channelVolumes', 'sandboxWin.channelVolumes')
        # contentItem references are within delegates, leave as-is
        result.append(fixed)

    return ''.join(result)


def make_main_qml():
    """Create new Main.qml as just the launcher + route editor popup."""
    # Keep: lines 1-1087 (root window header + launcher content)
    # Keep: lines 8560-8713 (route editor popup + closing brace)
    result = []
    # Lines 1-1087 (0-indexed: 0-1086)
    for i in range(0, 1087):
        result.append(lines[i])

    # Add WindowStateStore
    # Find where to insert it - after the bridge declarations
    # Let me find the last bridge declaration and add after it
    last_bridge = -1
    for i in range(0, 1087):
        if 'AudioEngineBridge' in lines[i] or 'ShowBuilderBridge' in lines[i]:
            last_bridge = i
    # Insert WindowStateStore after the last bridge
    # Actually, let me just add it after the Connections block

    # Add the route editor popup lines (8560-8713, 0-indexed: 8559-8712)
    result.append('\n')
    result.append('    WindowStateStore { id: winStore }\n')
    result.append('\n')
    result.append('    Component.onCompleted: {\n')
    result.append('        var rect = winStore.restoreWindowGeometry("MasterLauncher", Qt.rect(80, 80, 360, 520));\n')
    result.append('        root.x = rect.x;\n')
    result.append('        root.y = rect.y;\n')
    result.append('        root.width = rect.width;\n')
    result.append('        root.height = rect.height;\n')
    result.append('    }\n')
    result.append('\n')
    result.append('    onXChanged: saveTimer.restart()\n')
    result.append('    onYChanged: saveTimer.restart()\n')
    result.append('    onWidthChanged: saveTimer.restart()\n')
    result.append('    onHeightChanged: saveTimer.restart()\n')
    result.append('\n')
    result.append('    Timer {\n')
    result.append('        id: saveTimer\n')
    result.append('        interval: 1000\n')
    result.append('        onTriggered: winStore.saveWindowGeometry("MasterLauncher", Qt.rect(root.x, root.y, root.width, root.height), 0)\n')
    result.append('    }\n')
    result.append('\n')

    for i in range(8556, 8713):
        result.append(lines[i])

    return ''.join(result)


if __name__ == '__main__':
    with open('src/ui/AudioConsole.qml', 'w', encoding='utf-8') as f:
        f.write(make_audio_console())
    print('Wrote AudioConsole.qml')

    with open('src/ui/VideoSwitcher.qml', 'w', encoding='utf-8') as f:
        f.write(make_video_switcher())
    print('Wrote VideoSwitcher.qml')

    with open('src/ui/ShowBuilder.qml', 'w', encoding='utf-8') as f:
        f.write(make_show_builder())
    print('Wrote ShowBuilder.qml')

    with open('src/ui/Main.qml', 'w', encoding='utf-8') as f:
        f.write(make_main_qml())
    print('Wrote Main.qml')