# Spec: 2026-05-29 Hybrid EQ Design & Interactive Touch Node Graph

## 1. Architectural Goal
Provide a premium, high-density, professional live sound mixing parametric EQ layout inside Overwatch Studio. The interface combines a 2D interactive touch-draggable graphical node editor (Canvas) with 4 statically declared, tactile premium sliders, inspired by Yamaha RIVAGE PM and Allen & Heath Avantis digital audio workstations.

## 2. Solved Bug Root Causes

### 2.1 Slider Drag Termination Bug
* **Cause:** The previous EQ faders were rendered inside a QML `Repeater` bound to a dynamic JavaScript array literal model (`model: [ { val: audioCore.prop }, ... ]`). Moving a slider updated C++, which emitted `dspChanged()`. This forced QML to re-evaluate the array literal and recreate the `Repeater` model, destroying all active slider delegates under the cursor and terminating the mouse-drag gesture.
* **Solution:** We explicitly write out the 4 EQ band layout columns statically in QML. This removes the `Repeater` completely, ensuring that QML never destroys or recreates fader delegates during dragging, providing absolute touch-drag stability.

### 2.2 Static Curve Visualizer Bug
* **Cause:** The EQ and Saturation `Canvas` elements used `Connections` looking for a signal handler named `onChannelDSPChanged()`. The C++ bridge property notifier signal is actually named `dspChanged()`.
* **Solution:** Rename the QML signal handler in all visual canvases to the correct derived name `onDspChanged()`. Any C++ value updates immediately trigger `requestPaint()`, making the graph trace animate smoothly in real-time.

## 3. Mathematical Mapping Specifications

### 3.1 Horizontal Logarithmic Frequency Sweep (20Hz - 20kHz)
The horizontal X-coordinate maps logarithmically across the full graph canvas:
$$f(x) = 20 \cdot 1000^{x / W}$$
Where $W$ is the Canvas `width`.

To plot active node positions on the X-axis from a known frequency $f$:
$$x(f) = W \cdot \frac{\log_{10}(f / 20)}{3}$$

### 3.2 Vertical Linear Gain Sweep (±15dB)
The vertical Y-coordinate maps linearly across the full graph height:
$$g(y) = 15 - 30 \cdot \frac{y}{H}$$
Where $H$ is the Canvas `height`.

To plot active node positions on the Y-axis from a known gain $g$:
$$y(g) = H \cdot \frac{15 - g}{30}$$

## 4. UI Component & Interaction Design

### 4.1 Interactive EQ Canvas & 2D MouseArea
A transparent `MouseArea` overlay handles touch and drag gestures:
* **Node Circles:** Drawn as 14px circles centered on each band's mapped $(x, y)$ coordinate with 2px white borders, glowing center cores, and matching band colors:
  * Band 0 (Low Shelf): Neon Green (`#00d084`)
  * Band 1 (Low-Mid): Yellow (`#ffc72c`)
  * Band 2 (High-Mid): Orange (`#ff9500`)
  * Band 3 (High Shelf): Red (`#ff3b30`)
* **Grab Threshold:** On `onPressed`, calculate Euclidean distance to each of the 4 coordinates. If `dist <= 16` pixels, grab that band: `activeGrabbedBand = bandIndex`.
* **Crossover Bounds Clamping:** During dragging (`onPositionChanged`), the calculated frequency is clamped to its band bounds to prevent overlapping:
  * Band 0 (Low Shelf): $20\text{ Hz}$ to $500\text{ Hz}$
  * Band 1 (Low-Mid): $100\text{ Hz}$ to $2000\text{ Hz}$
  * Band 2 (High-Mid): $500\text{ Hz}$ to $10000\text{ Hz}$
  * Band 3 (High Shelf): $2000\text{ Hz}$ to $20000\text{ Hz}$

### 4.2 Static High-Density Sliders (4 Bands)
Below the interactive Canvas, the 4 bands are laid out side-by-side or stacked statically using standard rows. Each band exposes three parameter sliders:
1. **Gain (G):** Linear slider ($\pm 15.0\text{ dB}$)
2. **Frequency (F):** Logarithmic slider ($0.0$ to $1.0$)
3. **Q-factor (Q):** Linear slider ($0.5$ to $10.0$)

---
*Verified Design Spec approved by USER on 2026-05-29.*
