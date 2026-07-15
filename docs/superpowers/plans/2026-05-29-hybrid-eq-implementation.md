# Hybrid EQ Editor Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implement the hybrid interactive parametric EQ editor in Overwatch Studio, featuring a 2D multi-touch node drag canvas and static premium sliders for absolute drag stability and real-time graph animations.

**Architecture:** We will replace the buggy dynamic-repeater EQ faders in both the popup panel and the Show Builder with static fader declarations, preventing QML delegate reconstruction. We will connect the C++ bridge `dspChanged()` signal to QML `onDspChanged()` to trigger canvas repaints, and implement logarithmic-coordinate touch grabbing and dragging.

**Tech Stack:** Qt 6.6.2 QML, C++

---

### Task 1: Repair Canvas Signal Notifications
**Files:**
* Modify: [Main.qml](file:///f:/Drive/scripts/overwatch_studio/src/ui/Main.qml)

- [ ] **Step 1: Replace onChannelDSPChanged in popup EQ Canvas**
  Update the connection target in `eqCanvas` (near line 3099) to bind to the correct C++ notification signal.
  ```qml
  Connections {
      target: audioCore
      function onDspChanged() { eqCanvas.requestPaint(); }
  }
  ```

- [ ] **Step 2: Replace onChannelDSPChanged in popup Pre-Amp Saturation Canvas**
  Update the connection target in `satCanvas` (near line 2600) to bind to `onDspChanged()`.
  ```qml
  Connections {
      target: audioCore
      function onDspChanged() { satCanvas.requestPaint(); }
  }
  ```

- [ ] **Step 3: Replace onChannelDSPChanged in Show Builder EQ Canvas**
  Update the connection target in `eqCanvas_sandbox` (near line 6228) to bind to `onDspChanged()`.
  ```qml
  Connections {
      target: audioCore
      function onDspChanged() { eqCanvas_sandbox.requestPaint(); }
  }
  ```

- [ ] **Step 4: Replace onChannelDSPChanged in Show Builder Saturation Canvas**
  Update the connection target in `satCanvas_sandbox` (near line 5944) to bind to `onDspChanged()`.
  ```qml
  Connections {
      target: audioCore
      function onDspChanged() { satCanvas_sandbox.requestPaint(); }
  }
  ```

- [ ] **Step 5: Verify brace matching**
  Run: `python scratch/check_brackets.py`
  Expected: "All brackets match perfectly!"

---

### Task 2: Build Static 4-Band Layout for Popup EQ Panel
**Files:**
* Modify: [Main.qml](file:///f:/Drive/scripts/overwatch_studio/src/ui/Main.qml)

- [ ] **Step 1: Replace Repeater with Static 4-Band Blocks**
  In `Main.qml` inside `dspInspectorPanel.activeDspTab === 1`, remove the dynamic `Repeater` and replace it with four static, side-by-side or stacked columns in a `RowLayout` or `ColumnLayout` to avoid delegate recreation:
  ```qml
  ColumnLayout {
      Layout.fillWidth: true
      spacing: 6

      // Band 0 (Low Shelf)
      ColumnLayout {
          Layout.fillWidth: true
          spacing: 2
          RowLayout {
              Layout.fillWidth: true
              Text { text: "LOW SHELF"; color: "#00d084"; font.pixelSize: 9; font.bold: true }
              Item { Layout.fillWidth: true }
              Button {
                  text: audioCore.channelEQBand0Dynamics[audioWin.selectedChannel] ? "DYN ON" : "DYN OFF"
                  implicitWidth: 46; implicitHeight: 16
                  background: Rectangle { color: audioCore.channelEQBand0Dynamics[audioWin.selectedChannel] ? "#00d084" : "#1a1f29"; radius: 3 }
                  contentItem: Text { text: parent.text; color: audioCore.channelEQBand0Dynamics[audioWin.selectedChannel] ? "#0a0c10" : "#8a8d98"; font.pixelSize: 7; font.bold: true; anchors.centerIn: parent }
                  onClicked: audioCore.updateChannelEQDynamic(audioWin.selectedChannel, 0, !audioCore.channelEQBand0Dynamics[audioWin.selectedChannel])
              }
          }
          RowLayout {
              Layout.fillWidth: true; spacing: 6
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
              RowLayout {
                  Layout.fillWidth: true; Layout.preferredWidth: 1; spacing: 4
                  Text { text: "F"; color: "#8a8d98"; font.pixelSize: 8; font.bold: true }
                  PremiumSlider {
                      Layout.fillWidth: true; accentColor: "#00d084"
                      from: 0.0; to: 1.0
                      value: root.getEQFreqSliderVal(0, audioWin.selectedChannel)
                      onMoved: {
                          var min = root.getBandMinFreq(0);
                          var max = root.getBandMaxFreq(0);
                          var freq = min * Math.pow(max / min, value);
                          audioCore.updateChannelEQFreq(audioWin.selectedChannel, 0, freq);
                      }
                  }
                  Text { text: (audioCore.channelEQBand0Freqs[audioWin.selectedChannel] >= 1000 ? (audioCore.channelEQBand0Freqs[audioWin.selectedChannel]/1000).toFixed(1) + "k" : Math.round(audioCore.channelEQBand0Freqs[audioWin.selectedChannel])) + "Hz"; color: "#00d084"; font.pixelSize: 8; font.family: "Courier New"; width: 40 }
              }
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

      // Repeat this static design blocks for Band 1 (LOW-MID, #ffc72c), Band 2 (HIGH-MID, #ff9500), and Band 3 (HIGH SHELF, #ff3b30) inside Main.qml
  }
  ```

- [ ] **Step 2: Balance and verify braces**
  Run: `python scratch/check_brackets.py`
  Expected: "All brackets match perfectly!"

---

### Task 3: Interactive EQ Canvas Visuals & Node Dragging
**Files:**
* Modify: [Main.qml](file:///f:/Drive/scripts/overwatch_studio/src/ui/Main.qml)

- [ ] **Step 1: Upgrade Canvas onPaint to Plot Colored Nodes**
  Modify `onPaint` inside `eqCanvas` to dynamically read C++ frequency arrays (`channelEQBand0Freqs` etc.) and plot 4 interactive colored nodes with surrounding circles and white borders representing their exact current $(x, y)$ positions:
  ```javascript
  // (In onPaint)
  var colors = ["#00d084", "#ffc72c", "#ff9500", "#ff3b30"];
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

  for (var i = 0; i < 4; i++) {
      var nx = width * Math.log10(freqs[i] / 20) / 3;
      var ny = (height / 2) - (gains[i] / 15.0) * (height / 2.4);

      // Outer glow
      ctx.fillStyle = colors[i]; ctx.globalAlpha = 0.3;
      ctx.beginPath(); ctx.arc(nx, ny, 8, 0, 2 * Math.PI); ctx.fill();

      // Inner solid
      ctx.globalAlpha = 1.0; ctx.fillStyle = colors[i];
      ctx.beginPath(); ctx.arc(nx, ny, 4, 0, 2 * Math.PI); ctx.fill();

      // White outline
      ctx.strokeStyle = "#ffffff"; ctx.lineWidth = 1.5;
      ctx.beginPath(); ctx.arc(nx, ny, 4, 0, 2 * Math.PI); ctx.stroke();
  }
  ```

- [ ] **Step 2: Add MouseArea Overlay on eqCanvas**
  Overlay a standard `MouseArea` to calculate distance and allow dragging:
  ```qml
  MouseArea {
      anchors.fill: eqCanvas
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

          var bestDist = 999999;
          var bestIndex = -1;

          for (var i = 0; i < 4; i++) {
              var nx = eqCanvas.width * Math.log10(freqs[i] / 20) / 3;
              var ny = (eqCanvas.height / 2) - (gains[i] / 15.0) * (eqCanvas.height / 2.4);
              var dist = Math.hypot(mouse.x - nx, mouse.y - ny);
              if (dist < 20 && dist < bestDist) {
                  bestDist = dist;
                  bestIndex = i;
              }
          }
          grabbedBand = bestIndex;
      }

      onPositionChanged: (mouse) => {
          if (grabbedBand !== -1) {
              var pctX = Math.max(0.0, Math.min(1.0, mouse.x / eqCanvas.width));
              var freq = 20 * Math.pow(1000, pctX);

              var pctY = Math.max(0.0, Math.min(1.0, mouse.y / eqCanvas.height));
              var gain = 15 - 30 * pctY;
              gain = Math.max(-15.0, Math.min(15.0, gain));

              var minF = root.getBandMinFreq(grabbedBand);
              var maxF = root.getBandMaxFreq(grabbedBand);
              freq = Math.max(minF, Math.min(maxF, freq));

              audioCore.updateChannelEQ(audioWin.selectedChannel, grabbedBand, gain);
              audioCore.updateChannelEQFreq(audioWin.selectedChannel, grabbedBand, freq);
          }
      }

      onReleased: {
          grabbedBand = -1;
      }
  }
  ```

---

### Task 4: Port Hybrid Design to Show Builder EQ Tab
**Files:**
* Modify: [Main.qml](file:///f:/Drive/scripts/overwatch_studio/src/ui/Main.qml)

- [ ] **Step 1: Replicate static blocks in rightPanel.activeTab === 2**
  Port the identical 4 static EQ band layout blocks and matching interactive Canvas Node plot and `MouseArea` to `eqCanvas_sandbox` and its sliders.

- [ ] **Step 2: Verify brace matching**
  Run: `python scratch/check_brackets.py`
  Expected: "All brackets match perfectly!"

---

### Task 5: Compilation and Runtime Verification
**Files:**
* System compilation

- [ ] **Step 1: Release Build Compilation**
  Run: `cmake --build build --config Release`
  Expected: Build finishes with 0 errors and creates a functioning `overwatch_studio.exe`.

- [ ] **Step 2: Commit changes**
  Run: `git commit -am "feat: implement interactive EQ canvas and stable static sliders"`
