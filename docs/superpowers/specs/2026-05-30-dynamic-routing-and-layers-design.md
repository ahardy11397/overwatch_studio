# Overwatch Studio: Dynamic Audio Routing & Console Layer Reassignment Specification

## 1. Goal & Product Context
In high-end live audio production, engineers require maximum flexibility to configure and route audio signals. Overwatch Studio is upgrading its Software-Defined Sound Console (SDSC) to support a **Fairlight-style Dynamic Audio summing engine** coupled with a fully **reassignable console layout fader bank**. 

This system will replace hardcoded input/output arrays with a dynamically configurable track pool (Inputs, Auxes, Mix Buses, FX channels, DCA groups) and enable discrete, hardware-free process loopback capturing on Windows.

### Success Criteria:
* **Real Audio Device Binding:** Query real ASIO/WASAPI drivers, listing actual physical endpoints and opening devices at active sample rates/buffer sizes via JUCE.
* **Process-Level Loopback Capture:** Pull discrete system process audio (e.g., Discord, Spotify, Chrome) directly using the Windows 10/11 Application Loopback APIs (`AUDIOCAPTURE_MONITOR` via WASAPI) and route them to virtual input channels.
* **Polymorphic Summing Engine:** Dynamically adjust inputs, auxes, mix buses, and FX returns without heap allocations in the real-time callback thread.
* **Preserved & Re-ordered Layout:** Keep the styling, meters, and faders of the existing console deck, but update buttons sizing (full-sized EDIT button stacked with Mute/Solo) and re-order the channel label below the buttons block.
* **Tactile 3D Fader Caps:** Implement high-precision, 3D brushed-metal console fader head aesthetics in QML.

---

## 2. Technical Architecture & Data Flow

### A. Pre-allocated Polymorphic Track Pools (C++ Backend)
To enforce the **strictly zero runtime allocations** real-time DSP constraint, the engine pre-allocates maximum-capacity contiguous pools of specific channel strips upon initialization:
* **Max Input Strips:** 64 strips
* **Max Aux Outputs:** 16 strips
* **Max Mix Buses:** 16 strips
* **Max FX Returns:** 8 strips
* **Max DCA Groups:** 32 groups

```
[Physical Inputs / Loopbacks] ---> [Dynamic Input Strips Pool (max 64)]
                                        │
                                        ├─► [Aux Sends Pool (max 16)] ──► [HW Outputs]
                                        ├─► [Mix Buses Pool (max 16)] ──► [HW Outputs]
                                        ├─► [FX Returns Pool (max 8)]  ──► [Mix Buses/HW]
                                        └─► [DCA Master Gain (max 32)] (Control Scale)
```

Instead of using virtual function overhead inside the audio loop, we define a common interface structure, and the real-time processing loop sequentially executes pointer blocks in an cache-aligned SPSC execution queue. If the user decreases "Mix Buses" from 4 to 2, the pointers to Bus 3 and Bus 4 are simply removed from the active real-time summation loop using lock-free index updates.

### B. Windows Process Loopback Capture (`AUDIOCAPTURE_MONITOR`)
A background service handles process capture. It queries running Windows Process IDs (PIDs) using the Windows Toolhelp32 API:
1. **Enumeration:** We query active processes and expose a name-to-PID map to QML (e.g. `{"Discord.exe": 14322}`, `{"chrome.exe": 9534}`).
2. **Loopback Initialization:** We initialize WASAPI shared loopback via `IAudioClient3::InitializeSharedLoopback` by providing `AUDIOCAPTUREPARAMS` with the `AUDIOCAPTURE_MONITOR` tag and the target process ID.
3. **SPSC Buffer Push:** Captured floating-point audio samples are written into a lock-free Single-Producer Single-Consumer (`SPSCQueue<float>`) ring buffer representing the target virtual input channel strip.
4. **Real-time Summing Consume:** The audio callback consumes samples from the loopback ring buffer. If no samples are queued, it safely drops in silence, maintaining $< 2\text{ms}$ processing latency.

---

## 3. QML UI Layout Adaptations

We maintain the exact, highly refined 8-fader visual structure from the existing console center deck, applying the following precise structural updates:

### A. Dynamic Fader Mapping
Instead of hardcoding a strip's target index to `activeBank * 8 + index`, we resolve visual bindings using a lookup index:
```qml
property var slotAssignment: audioCore.getFaderMapping(activeBank, index)
// slotAssignment returns: { type: "input" | "bus" | "aux" | "fx" | "dca", actualIndex: 0..63 }
```

### B. Vertical Control Strip Re-ordering
We stack Mute, Solo, and Edit buttons as a uniform vertical panel, making the **EDIT button full-sized** matching Mute/Solo exactly, and move the **Channel Label directly below the buttons block** and above the fader well:

```
┌──────────────────────────────────────┐
│  Fader Source Selector (Dropdown)    │
│  [ INPUT 2: Discord Capture     ▼ ]  │
├──────────────────────────────────────┤
│  MUTE Button (Width 68px, H 28px)    │
├──────────────────────────────────────┤
│  SOLO Button (Width 68px, H 28px)    │
├──────────────────────────────────────┤
│  EDIT Button (Width 68px, H 28px)    │
├──────────────────────────────────────┤
│  Channel Label (e.g., "CH 2")        │
├──────────────────────────────────────┤
│                                      │
│  [Dual Peak Meter]  [Fader Well]     │
│  [                ] [ ( FADER CAP ) ]│
│  [                ] [       │       ]│
│  [                ] [       │       ]│
│                                      │
├──────────────────────────────────────┤
│  Footer Name: "Discord Audio"        │
└──────────────────────────────────────┘
```

### C. Realistic 3D Brushed-Metal Fader Cap Styling
The fader caps are styled in QML using curved multi-stop vertical gradients, an inner vertical alignment slot indentation, and color-coded db scale alignment stripes matching the channel type:
* **Inputs:** Emerald Green (`#00d084`)
* **Mix Buses:** Warm Orange (`#ff9500`)
* **Aux Sends:** Cool Cyan (`#00BDD6`)
* **DCA Masters:** Bright Yellow (`#ffc72c`)

---

## 4. Verification Plan

### A. Automated Tests:
* Add a GTest module `tests/DynamicAudioEngineTests.cpp` to verify polymorphic SPSC pointer-swapping, ensuring zero allocations during track bank changes.
* Add mock WASAPI capture tests ensuring process loopback packets write to SPSC queues without thread blockages.

### B. Manual Visual Checks:
* Open `overwatch_studio` in QML runtime and verify that fader strips update instantly to represent different channels.
* Toggle the **Edit Layer Assignments** mode and verify that changing a dropdown shifts the fader's channel association, name, and metering lines instantly.
* Run `python scratch/check_brackets.py` to confirm that all QML braces are fully balanced before committing.
