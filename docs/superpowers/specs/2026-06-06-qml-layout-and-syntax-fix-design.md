# Spec: QML Layout and Syntax Fixes

## Overview
This specification addresses the syntax and layout layout bugs identified in `src/ui/Main.qml`. These issues include:
1. Extra closing braces at the end of `src/ui/Main.qml` causing a QML engine parsing failure.
2. Layout overflow clipping in the right panel tabs ("INPUT PATCH" and "INTERNAL ROUTING") where width exceeds the panel's default dimensions.

## Proposed Changes

### [MODIFY] [Main.qml](file:///f:/Drive/scripts/overwatch_studio/src/ui/Main.qml)

1. **Remove Trailing Braces**: Delete the trailing extra braces at the end of the file:
   ```qml
   // Keep the closing brace for the root Window block (root)
   }
   
   // Remove everything below that:
   // }
   // }}}
   ```

2. **Enable Horizontal Scroll Sizing**: Update the `ColumnLayout` inside `patchBoardScrollView` to expand horizontally if the content size requires it, enabling ScrollView to naturally display horizontal scrollbars:
   ```qml
   ColumnLayout {
       width: Math.max(rightPanel.width - 25, implicitWidth)
       spacing: 12
   ```

3. **Propagate Sub-Panel Implicit Widths**: Define `implicitWidth` for the three patch/routing rectangles, enabling them to bubble up their required size to the ScrollView layout:
   - **Input Patch Rectangle**:
     ```qml
     Rectangle {
         id: inputPatchPanel
         visible: patchBoardScrollView.patchSubTab === 0
         Layout.fillWidth: true
         implicitWidth: inputPatchLayout.implicitWidth + 24
         implicitHeight: inputPatchLayout.implicitHeight + 24
     ```
   - **Internal Routing Rectangle**:
     ```qml
     Rectangle {
         visible: patchBoardScrollView.patchSubTab === 1
         Layout.fillWidth: true
         implicitWidth: routingMatrixLayout.implicitWidth + 24
         implicitHeight: routingMatrixLayout.implicitHeight + 24
     ```
   - **Output Patch Rectangle**:
     ```qml
     Rectangle {
         visible: patchBoardScrollView.patchSubTab === 2
         Layout.fillWidth: true
         implicitWidth: outputPatchLayout.implicitWidth + 24
         implicitHeight: outputPatchLayout.implicitHeight + 24
     ```

## Verification Plan
1. **Compilation**: Run `cmake --build build --config Release` to ensure resource compilation is successful.
2. **Unit Tests**: Run `build/bin/Release/AudioEngineTests.exe` to verify all 26 unit tests still pass.
