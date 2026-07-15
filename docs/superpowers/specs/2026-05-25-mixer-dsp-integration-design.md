# Spec: Advanced Widescreen Console with Integrated DSP Channel Edit Panel

This specification outlines the architecture, components, visual layouts, and math formulas for integrating a professional-grade, interactive, and lock-free **Touchscreen DSP Selected Channel Edit Inspector** directly inside the widescreen Audio Touch Console window in Overwatch Studio.

---

## 1. Geometric & Visual Console Design

The Audio Touch Console window will be expanded to a premium widescreen format (`1620px` width by `680px` height) to house a side-by-side split layout:

*   **Left Deck**: Fader bank select buttons (110px).
*   **Center Deck**: 8 Swappable Fader Channels (Layout.fillWidth: true).
*   **Right Deck (Master)**: Dedicated Master Fader Bay (110px).
*   **DSP Inspector Deck**: Selected Channel DSP panel (440px wide, visible only when `dspPanelOpen` is true).

```
+--------------------------------------------------------------------------------------------------------------------------------+
|  [Fader Banks]   |  [CH 1]   [CH 2]   [CH 3]   [CH 4]   [CH 5]   [CH 6]   [CH 7]   [CH 8]  |  [Master]   |  [SELECTED CHANNEL DSP]     |
|   CH 1 - 8       |                                                                       |             |   CH 03: LEAD VOCALS        |
|   CH 9 - 16      |   EDIT     EDIT     EDIT     EDIT     EDIT     EDIT     EDIT     EDIT  |   MUTE      |   +-----------------------+ |
|   CH 17 - 24     |   MUTE     MUTE     MUTE     MUTE     MUTE     MUTE     MUTE     MUTE  |             |   |      EQ PLOT          | |
|   DCA 1 - 8      |   SOLO     SOLO     SOLO     SOLO     SOLO     SOLO     SOLO     SOLO  |   (Fader)   |   +-----------------------+ |
|                  |                                                                       |             |   | PRE-AMP | DYN | EQ    | |
|                  |   (Fader)  (Fader)  (Fader)  (Fader)  (Fader)  (Fader)  (Fader)  (Fader)|             |   |                         | |
|   (Latency-Stat) |                                                                       |             |   | (Advanced Knobs & Dials)| |
+--------------------------------------------------------------------------------------------------------------------------------+
```

---

## 2. Dynamic Control Toggles

We will declare the following dynamic properties inside the Audio Touch Console `Window` in `Main.qml`:
*   `property bool dspPanelOpen: false`
*   `property int selectedChannel: 0`

When an operator taps the **EDIT** button on any channel strip:
1. `selectedChannel` is updated to `chIdx`.
2. `dspPanelOpen` is set to `true`.
3. The panel slides out from the right using a `NumberAnimation` with an Easing curve (`Easing.OutCubic`, 250ms).

---

## 3. Interactive Touch-Drag EQ Canvas Mathematics

The Parametric EQ Canvas will render a grid of standard audiophile reference lines and support touch-dragging for the low-shelf, low-mid bell, high-mid bell, and high-shelf bands.

### Coordinate Conversion Formulas
Given Canvas coordinates `x` and `y` where $x \in [0, \text{width}]$ and $y \in [0, \text{height}]$:

1.  **Frequency (Logarithmic)**:
    $$f(x) = f_{\min} \cdot \left(\frac{f_{\max}}{f_{\min}}\right)^{\frac{x}{\text{width}}}$$
    Where $f_{\min} = 20\text{ Hz}$ and $f_{\max} = 20000\text{ Hz}$.

2.  **Gain (Linear)**:
    $$\text{Gain}(y) = G_{\max} - \left(\frac{y}{\text{height}}\right) \cdot (G_{\max} - G_{\min})$$
    Where $G_{\max} = +15\text{ dB}$ and $G_{\min} = -15\text{ dB}$.

### Visual EQ Line Plotting Approximation
To draw the biquad response curve in QML `Canvas.onPaint`, we evaluate the filter transfer function at horizontal pixel intervals `x` by mapping it back to frequency $f$ and summing the individual gains of each band:
$$\text{Response}(f) = H_{\text{HPF}}(f) + \sum_{i=0}^{3} H_{\text{Band } i}(f)$$
*   **HPF**: A high-pass filter curve attenuation below the cutoff frequency.
*   **Shelving Filter**: Evaluated using a linear ramp approximation.
*   **Peaking/Bell EQ Bands**: Approximated using dynamic exponential distance:
    $$H_{\text{Bell}}(f) = \text{Gain} \cdot \exp\left(-\left(\frac{\log_{10}(f / f_{\text{center}})}{\text{Bandwidth}}\right)^2\right)$$

---

## 4. Advanced Dynamics Visualization

The Dynamics card features a dual-visualizer mapping Gate and Compressor activity.

### Compressor Knee & Soft Curve Plotting
The transfer function shows input level vs output level ($x, y$ mapped from $-60\text{ dBFS}$ to $0\text{ dBFS}$):
$$\text{Output}(x) = \begin{cases} 
      x & x < T - \frac{W}{2} \\
      x + \frac{(x - T + W/2)^2}{2W} \cdot \left(\frac{1}{R} - 1\right) & T - \frac{W}{2} \le x \le T + \frac{W}{2} \\
      T + \frac{x - T}{R} & x > T + \frac{W}{2}
   \end{cases}$$
Where:
*   $T$ = Threshold (dB)
*   $R$ = Compression Ratio (e.g. 4.0)
*   $W$ = Knee Width (e.g. $10\text{ dB}$ for soft-knee smoothing)

### Real-Time Attenuation Metering
A vertical scale representing Attenuation ($0\text{ dB}$ to $-24\text{ dB}$) bounces dynamically based on the compressor's computed gain reduction. We will mock this reduction with a reactive envelope follower linked to input peaks.

---

## 5. Touch-Dial Circular Controls

Circular rotary dials will replace linear sliders for Trim and HPF Cutoff.

*   **Geometry**: Frosted circular track (`radius: 40`) with an outer active arc drawn using a Canvas arc path:
    ```javascript
    ctx.arc(centerX, centerY, radius, startAngle, endAngle);
    ```
*   **Touch Mechanics**: A `MouseArea` captures vertical movement $\Delta y$. Moving the touch position up increases the value, and moving down decreases it, wrapping cleanly within boundary bounds.

---

## 6. Verification Metrics
*   Verify that touch drag events are processed within $<5\text{ms}$ in QML to maintain 60fps rendering sweeps.
*   Verify C++ core parameter stores are lock-free and do not invoke memory allocations.
