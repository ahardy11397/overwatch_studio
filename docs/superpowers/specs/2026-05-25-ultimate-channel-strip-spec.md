# Technical Specification: The Ultimate Console Channel Strip (UDCS-1)

This document specifies the architecture, signal flow, mathematical models, control parameters, and touch-screen user interface paradigms for the **Ultimate DSP Console Channel Strip (UDCS-1)** in Overwatch Studio. It draws inspiration from legendary analog consoles (SSL 4000G, Neve 88RS) and high-end digital live mixers (Allen & Heath dLive RackExtra FX, Behringer WING).

---

## 1. Unified Signal Chain Architecture

The UDCS-1 employs a serial, non-destructive digital processing block layout. The operator has the option to globally swap the position of the **EQ** and **Dynamics** decks.

```
       +-------------------------------------------------------------------------------------------------+
       |                                   INPUT STAGE & PRE-AMP                                         |
       |  [Trim +/-18dB] -> [Phase 180°] -> [24dB/oct Butterworth HPF] -> [LPF] -> [Harmonic Saturation] |
       +-------------------------------------------------------------------------------------------------+
                                                       |
       +-------------------------------------------------------------------------------------------------+
       |                                   DE-ESSER & SHAPER                                             |
       |             [Dual-band De-Esser 4k-10kHz] -> [Transient Attack & Sustain Designer]               |
       +-------------------------------------------------------------------------------------------------+
                                                       |
       +-------------------------------------------------------------------------------------------------+
       |                                    GATE / EXPANDER                                              |
       |                [Sidechain Filtered Downward Expander / Gate with Hold & Hysteresis]             |
       +-------------------------------------------------------------------------------------------------+
                                                       | (Swap-able)
                                       +---------------+---------------+
                                       |                               |
       +---------------------------------------+               +---------------------------------------+
       |             DYNAMIC EQ & EQ           |               |       MULTI-MODE COMPRESSOR           |
       | [4-band Parametric & 2x Dynamic EQ]   |               |   [VCA / FET / Opto Analog Model]     |
       +---------------------------------------+               +---------------------------------------+
                                       |                               |
                                       +---------------+---------------+
                                                       |
       +-------------------------------------------------------------------------------------------------+
       |                                   OUTPUT CEILING STAGE                                          |
       |                   [Zero-Lookahead brickwall Peak Limiter] -> [Output Fader]                      |
       +-------------------------------------------------------------------------------------------------+
```

---

## 2. SSL vs. dLive vs. WING vs. UDCS-1 Comparison

| Module | SSL Native Strip 2 | Allen & Heath dLive | Behringer WING | UDCS-1 (Ultimate Spec) |
| --- | --- | --- | --- | --- |
| **HPF / LPF** | 18dB/oct HPF, 12dB/oct LPF | 12dB/oct HPF & LPF | 12/24dB/oct HPF & LPF | **Selectable 12/24dB/oct Butterworth Filters** |
| **Pre-amp Drive** | None (Clean) | Tube Stage Emulation | 4 Analog Models | **Tube, Tape, and Transistor Harmonics Drive** |
| **Noise Gate** | Basic Gate/Expander | Gate with sidechain HPF | Drawmer-style Gate | **Gate/Expander with full Hysteresis & Sidechain** |
| **De-Esser** | None | Dedicated Rack FX | Channel strip card | **High-frequency band-pass Compressor De-Esser** |
| **Transient Shaper** | None | Transient Controller | Transient Shaper | **Discrete Attack/Sustain Transient Designer** |
| **Parametric EQ** | 4-band constant Q | 4-band asymmetric | 6-band parametric | **4-band parametric + 2 dynamic tracking bands** |
| **Compressor Modes**| SSL G-Master VCA | 6 emulations | 8 emulations | **Selectable VCA (Clean), FET (Aggressive), Opto (Smooth)** |
| **Safety Limiter** | Peak Limiter | Output Limiter | Output Peak Limiter | **Zero-lookahead Brickwall Peak Limiter** |

---

## 3. DSP Mathematical Formulations & Controls

### 3.1. Pre-Amp Harmonic Saturation
Simulates vintage console warm drive by applying non-linear soft clipping:
$$y(t) = (1 - \alpha) \cdot x(t) + \alpha \cdot \tanh(\text{Drive} \cdot x(t))$$
Where:
*   $\text{Drive}$ = Gain multiplier ($1.0$ to $10.0$).
*   $\alpha$ = Dry/Wet blend coefficient ($0.0$ to $1.0$).
*   `tanh(u)` introduces odd-order tube-like harmonics.

### 3.2. Sidechain Downward Expander/Gate
Protects against spill and floor noise using envelope detection and hysteresis:
$$\text{Gain}(t) = \begin{cases} 
      1.0 & \text{Envelope} > T_{\text{open}} \\
      \text{Range}_{\text{dB}} & \text{Envelope} < T_{\text{close}} \\
      \text{interpolate} & T_{\text{close}} \le \text{Envelope} \le T_{\text{open}}
   \end{cases}$$
Where:
*   Hysteresis is established by setting $T_{\text{open}} = T_{\text{close}} + 3\text{ dB}$, preventing gate chatter at threshold crossings.

### 3.3. Transient Designer
Separates transient attacks from sustain tails using fast and slow envelope followers:
$$\begin{aligned}
\text{Env}_{\text{fast}}(t) &= (1 - \beta_{\text{fast}}) \cdot \text{Env}_{\text{fast}}(t-1) + \beta_{\text{fast}} \cdot |x(t)| \\
\text{Env}_{\text{slow}}(t) &= (1 - \beta_{\text{slow}}) \cdot \text{Env}_{\text{slow}}(t-1) + \beta_{\text{slow}} \cdot |x(t)|
\end{aligned}$$
*   **Attack Boost**: Scaled by the ratio $\frac{\text{Env}_{\text{fast}}}{\text{Env}_{\text{slow}}}$ when transients rise.
*   **Sustain Boost**: Compares decaying slow envelopes to maintain longer tail rings.

### 3.4. Parametric & Dynamic EQ
Combines four standard biquad filters with two dynamic tracking bands:
$$H(z) = \frac{b_0 + b_1 z^{-1} + b_2 z^{-2}}{1 + a_1 z^{-1} + a_2 z^{-2}}$$
*   **Dynamic EQ Mode**: The Gain of Mid-Band 1 and Mid-Band 2 is modulated in real-time by a local RMS sidechain detector:
    $$\text{Gain}_{\text{effective}} = \text{Gain}_{\text{target}} \cdot \max\left(0, \frac{\text{SidechainRMS}}{\text{Threshold}}\right)$$

### 3.5. Tri-Mode Analog Compressor Emulations
1.  **VCA Mode (Clean)**: Instantaneous log-domain peak detection with feedforward topology.
2.  **FET Mode (Fast/Colored)**: Simulates feedback FET peak-catchers (like the 1176) with rapid $20\mu\text{s}$ attack time and soft saturation:
    $$y(t) = \text{sign}(x(t)) \cdot \left(1 - e^{-|x(t) \cdot \text{Gain}|}\right)$$
3.  **Opto Mode (Smooth/Slow)**: Emulates photodetector lag. The release curve is modeled as a two-stage exponential decay:
    $$\tau_{\text{release}} = \tau_{\text{initial}} \cdot (1 + \gamma \cdot \text{Attenuation})$$
    Providing smooth, musical compression (LA-2A style).

---

## 4. Touch-Friendly Visual Layout & Gesture Specifications

We will design a majestic, multi-page slide-out **DSP Inspector panel** (`480px` wide) inside the Mixer window, with distinct tabs:

### 4.1. Page 1: Pre-Amp, HPF/LPF & Saturation Drive
*   **Trim & HPF/LPF Circular Dials**: Frosted rotary dials with glowing progress arcs showing input gain, HPF cutoff ($20\text{Hz}$ to $400\text{Hz}$), and LPF cutoff ($2\text{kHz}$ to $20\text{kHz}$).
*   **Harmonic Drive Card**:
    *   A triangular slider selecting the saturation type: `[TUBE]`, `[TAPE]`, `[TRANSISTOR]`.
    *   An interactive visualizer showing a real-time glowing sine-wave shaping distortion plot.

### 4.2. Page 2: EQ & Dynamic EQ Touch Canvas
*   A larger, premium logarithmic grid Canvas with interactive handles:
    *   **Double-tap** a node to toggle between **Static EQ** and **Dynamic EQ** mode. When dynamic mode is engaged, a pulsating cyan outer ring expands and contracts to show the active dynamic expansion/compression depth.
    *   **Pinch-to-zoom gesture**: Touch with two fingers and spread to increase or pinch to decrease the **Q Factor (Bandwidth)** of the parametric band.

### 4.3. Page 3: Triple-Mode Compressor & De-Esser
*   **Analog Model Switch**: A premium sliding toggle selecting between `[VCA]`, `[FET]`, and `[OPTO]`. The background color dynamically shifts:
    *   **VCA**: Clean electric emerald green (`#00d084`).
    *   **FET**: Vibrant warm orange-red (`#ff3b30`).
    *   **OPTO**: Calming retro amber-glow (`#ff9500`).
*   **Compression Knee Canvas**: Plots the exact soft-knee bends and input/output characteristics.
*   **De-Esser Slider Block**: Features frequency sweep dials ($4\text{kHz}$ to $10\text{kHz}$) and active sibilance attenuation meters.

### 4.4. Page 4: Gate, Transient Designer & Output Limiter
*   **Gate Envelope Visualizer**: A scrolling timeline showing active gating (green strip represents open gate, red strip represents closed attenuation).
*   **Transient Designer Sliders**: Sleek vertical faders adjusting **Attack Boost** and **Sustain tail** directly.
*   **Brickwall Safety Limiter**: A bright red ceiling selector slider mapping physical output bounds safely.
