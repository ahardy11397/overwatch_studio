# QML Layout and Syntax Fixes Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix the trailing syntax braces and the horizontal layout clipping on the patch/routing board in `src/ui/Main.qml`.

**Architecture:** Make the `patchBoardScrollView`'s child layout dynamically adapt to the content's implicit width rather than being hard-constrained to the right panel's width. Define explicit implicit widths on the sub-tab panels so they bubble up their actual width demands. Remove syntax errors causing engine parsing failures.

**Tech Stack:** Qt 6 QML, CMake

---

### Task 1: Fix QML Syntax Error (Trailing Braces)

**Files:**
- Modify: [Main.qml](file:///f:/Drive/scripts/overwatch_studio/src/ui/Main.qml#L8575-L8583)

- [ ] **Step 1: Locate and remove extra trailing braces**
  Open `src/ui/Main.qml` and locate the end of the file (lines 8575-8583). Keep the closing brace for the root `Window` block on line 8577, and delete all characters and braces below it:
  ```diff
  - }
  - 
  - 
  - }
  - 
  - }}}
  ```

- [ ] **Step 2: Verify compilation of the project**
  Run: `cmake --build build --config Release`
  Expected: Successful compilation of the project binary and resource generation without compiler errors.

- [ ] **Step 3: Commit the changes**
  Run:
  ```bash
  git add src/ui/Main.qml
  git commit -m "fix(ui-qml): remove extra trailing braces at end of file"
  ```

---

### Task 2: Implement Dynamic Scroll Sizing and Implicit Width Propagation

**Files:**
- Modify: [Main.qml](file:///f:/Drive/scripts/overwatch_studio/src/ui/Main.qml#L7845-L8415)

- [ ] **Step 1: Update the ScrollView child ColumnLayout width**
  Locate `patchBoardScrollView` (around line 7847) and its inner `ColumnLayout` (around line 7854). Update the width constraint of the `ColumnLayout` to:
  ```qml
                          ColumnLayout {
                              width: Math.max(rightPanel.width - 25, implicitWidth)
                              spacing: 12
  ```

- [ ] **Step 2: Set implicitWidth on the Input Patch panel Rectangle**
  Locate the `inputPatchPanel` Rectangle (around line 7901). Add the `implicitWidth` property:
  ```qml
                              Rectangle {
                                  id: inputPatchPanel
                                  visible: patchBoardScrollView.patchSubTab === 0
                                  Layout.fillWidth: true
                                  implicitWidth: inputPatchLayout.implicitWidth + 24
                                  implicitHeight: inputPatchLayout.implicitHeight + 24
  ```

- [ ] **Step 3: Set implicitWidth on the Internal Routing matrix Rectangle**
  Locate the internal routing matrix Rectangle (around line 8164). Add the `implicitWidth` property:
  ```qml
                              Rectangle {
                                  visible: patchBoardScrollView.patchSubTab === 1
                                  Layout.fillWidth: true
                                  implicitWidth: routingMatrixLayout.implicitWidth + 24
                                  implicitHeight: routingMatrixLayout.implicitHeight + 24
  ```

- [ ] **Step 4: Set implicitWidth on the Output Patch panel Rectangle**
  Locate the output patch panel Rectangle (around line 8336). Add the `implicitWidth` and `implicitHeight` properties:
  ```qml
                              Rectangle {
                                  visible: patchBoardScrollView.patchSubTab === 2
                                  Layout.fillWidth: true
                                  implicitWidth: outputPatchLayout.implicitWidth + 24
                                  implicitHeight: outputPatchLayout.implicitHeight + 24
  ```

- [ ] **Step 5: Verify project compilation and run unit tests**
  Run: `cmake --build build --config Release`
  Expected: Clean build.
  Run: `build/bin/Release/AudioEngineTests.exe`
  Expected: All 26 unit tests pass.

- [ ] **Step 6: Commit the changes**
  Run:
  ```bash
  git add src/ui/Main.qml
  git commit -m "fix(ui-qml): enable horizontal scrolling and propagate panel implicit widths"
  ```
