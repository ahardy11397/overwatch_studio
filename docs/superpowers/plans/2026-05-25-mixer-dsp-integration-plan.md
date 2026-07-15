# Advanced Mixer Widescreen Console with Integrated DSP Edit Panel Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Integrate a professional-grade, interactive, and lock-free touch-drag DSP Selected Channel Inspector directly inside the widescreen Audio Touch Console (Mixer) window.

**Architecture:** We will increase the Mixer window geometry, split the layout to accommodate a right-hand slide-out panel, and implement QML Canvas visualizers for the real-time logarithmic touch-drag EQ and soft-knee compressor knee transfer curve.

**Tech Stack:** Qt 6.6 QML, QML Canvas, C++20, lock-free parameter smoothing.

---

### Task 1: Widescreen Geometry and Bridge Properties Expansion

**Files:**
*   Modify: `src/ui/Main.qml`
*   Modify: `src/ui/AudioEngineBridge.h`
*   Modify: `src/ui/AudioEngineBridge.cpp`

- [ ] **Step 1: Expand Audio Touch Console Window Dimensions**
  Change the Audio Touch Console `Window` geometry inside `src/ui/Main.qml` to a widescreen resolution of `1620` width and `680` height, and declare the selected channel state variables.
  ```qml
  // Inside src/ui/Main.qml around line 445:
  Window {
      id: audioWin
      visible: audioWindowOpen
      onVisibleChanged: {
          audioWindowOpen = visible;
      }
      width: 1620
      height: 680
      title: "Audio Touch Console"
      color: "#0a0c10"
      
      property bool dspPanelOpen: false
      property int selectedChannel: 0
  ```

- [ ] **Step 2: Add dynamic Q_PROPERTIES to C++ bridge**
  Expose `dspPanelOpen` and `selectedChannel` to the bridge for clean synchronization if needed.

- [ ] **Step 3: Modify Fader Strip EDIT click callback**
  Inside the channel strip repeater's `editBtn` in `src/ui/Main.qml`:
  ```qml
  onClicked: {
      audioWin.selectedChannel = chIdx;
      audioWin.dspPanelOpen = true;
  }
  ```

- [ ] **Step 4: Verify build compiles cleanly**
  Run: `cmake --build build --config Release`
  Expected: Build succeeds with 0 errors.

---

### Task 2: Advanced selectedChannelPanel Layout Construction

**Files:**
*   Modify: `src/ui/Main.qml`

- [ ] **Step 1: Construct the slide-out inspector container**
  Place the selected channel DSP panel inside the console `RowLayout` on the far right. Include a `Behavior on width` or standard transition animation to make it slide out smoothly.
  ```qml
  // Far right of main RowLayout in audioWin:
  Rectangle {
      id: dspInspectorPanel
      visible: audioWin.dspPanelOpen
      Layout.fillHeight: true
      Layout.preferredWidth: audioWin.dspPanelOpen ? 440 : 0
      color: "#161920"
      border.color: "#252b36"
      border.width: 1
      radius: 10
      
      Behavior on Layout.preferredWidth {
          NumberAnimation { duration: 250; easing.type: Easing.OutCubic }
      }
  ```

- [ ] **Step 2: Implement header bar with Close button**
  Add a gorgeous, high-contrast title displaying the active channel index and name, along with an amber glow `[X]` button that collapses the panel.
  ```qml
  RowLayout {
      Layout.fillWidth: true
      height: 40
      Text {
          text: "SELECTED CHANNEL: CH " + (audioWin.selectedChannel + 1)
          color: "#00d084"
          font.pixelSize: 12
          font.bold: true
      }
      Item { Layout.fillWidth: true }
      Button {
          text: "CLOSE"
          onClicked: audioWin.dspPanelOpen = false
      }
  }
  ```

- [ ] **Step 3: Build frosted section tabs**
  Create tabs for: `[PRE-AMP/HPF]`, `[EQUALIZER]`, `[DYNAMICS]` utilizing glassmorphism styles.

- [ ] **Step 4: Verify QML syntax is valid**
  Run: `libs/Qt/6.6.2/msvc2019_64/bin/qmlformat.exe -n src/ui/Main.qml`
  Expected: No syntax violations.

---

### Task 3: Interactive Touch-Drag EQ Canvas

**Files:**
*   Modify: `src/ui/Main.qml`

- [ ] **Step 1: Program logarithmic coordinate mathematics**
  Inside the EQ tab component, place a large `Canvas` (`height: 180`) with a grid displaying reference lines at 20Hz, 100Hz, 1kHz, 10kHz, 20kHz, and Gain indicators (+15dB to -15dB).

- [ ] **Step 2: Implement multi-touch node-drag MouseArea**
  Track drag events. Map canvas `x` coordinates logarithmically to frequency, and `y` coordinates linearly to gain, calling `audioCore.updateChannelEQ(channel, band, gain)` on the C++ bridge reactively.
  ```javascript
  function xToFreq(x) {
      return 20 * Math.pow(1000, x / width);
  }
  function freqToX(f) {
      return (Math.log10(f / 20) / Math.log10(1000)) * width;
  }
  function yToGain(y) {
      return 15.0 - (y / height) * 30.0;
  }
  function gainToY(g) {
      return ((15.0 - g) / 30.0) * height;
  }
  ```

- [ ] **Step 3: Draw interactive pulsing nodes and glowing curve**
  Draw the biquad curve with a glowing neon cyan gradient fill under the line, and place four color-coded circles for Low Shelf (cyan), Low-Mid (yellow), High-Mid (orange), and High Shelf (red).

- [ ] **Step 4: Verify touch-drag responsiveness**
  Ensure the nodes update parameters smoothly without zipper noise or lag.

---

### Task 4: Dynamics Compressor soft-knee Visualizer & Custom Touch Dials

**Files:**
*   Modify: `src/ui/Main.qml`

- [ ] **Step 1: Write Compressor Transfer Curve drawing formula**
  Implement the compressor transfer function inside the dynamics visualizer `Canvas.onPaint` mapping signals from $-60\text{ dBFS}$ to $0\text{ dBFS}$ showing the soft-knee bend mathematically.

- [ ] **Step 2: Add vertical reactive reduction level meter**
  Draw a fast, responsive gain reduction level meter bouncing from $0\text{ dB}$ down to $-24\text{ dB}$ in orange, demonstrating active compressor dynamics.

- [ ] **Step 3: Construct the circular frosted Touch Dials**
  Replace standard sliders in the Pre-Amp and HPF card with custom circular knobs. The knobs will sweep values based on vertical drag, rendering glowing value arcs dynamically.

- [ ] **Step 4: Full compilation sweep and validation**
  Run: `cmake --build build --config Release`
  Expected: Build finishes cleanly. Launch tests to verify zero allocations.
