---
name: Bench Instrument System
colors:
  surface: '#16121b'
  surface-dim: '#16121b'
  surface-bright: '#3c3741'
  surface-container-lowest: '#100c15'
  surface-container-low: '#1e1a23'
  surface-container: '#221e27'
  surface-container-high: '#2d2832'
  surface-container-highest: '#38333d'
  on-surface: '#e9dfed'
  on-surface-variant: '#dac2b2'
  inverse-surface: '#e9dfed'
  inverse-on-surface: '#332e38'
  outline: '#a28c7f'
  outline-variant: '#544338'
  surface-tint: '#ffb782'
  primary: '#ffb782'
  on-primary: '#4f2500'
  primary-container: '#e88a3c'
  on-primary-container: '#5a2b00'
  inverse-primary: '#934b00'
  secondary: '#b2c9de'
  on-secondary: '#1c3343'
  secondary-container: '#354c5c'
  on-secondary-container: '#a4bbcf'
  tertiary: '#afcfa9'
  on-tertiary: '#1c361c'
  tertiary-container: '#8aa985'
  on-tertiary-container: '#233e22'
  error: '#ffb4ab'
  on-error: '#690005'
  error-container: '#93000a'
  on-error-container: '#ffdad6'
  primary-fixed: '#ffdcc5'
  primary-fixed-dim: '#ffb782'
  on-primary-fixed: '#301400'
  on-primary-fixed-variant: '#703800'
  secondary-fixed: '#cee5fa'
  secondary-fixed-dim: '#b2c9de'
  on-secondary-fixed: '#041e2d'
  on-secondary-fixed-variant: '#33495a'
  tertiary-fixed: '#cbebc4'
  tertiary-fixed-dim: '#afcfa9'
  on-tertiary-fixed: '#062108'
  on-tertiary-fixed-variant: '#324d30'
  background: '#16121b'
  on-background: '#e9dfed'
  surface-variant: '#38333d'
typography:
  display-numeric:
    fontFamily: JetBrains Mono
    fontSize: 40px
    fontWeight: '600'
    lineHeight: 44px
    letterSpacing: -0.02em
  readout-secondary:
    fontFamily: JetBrains Mono
    fontSize: 16px
    fontWeight: '500'
    lineHeight: 20px
    letterSpacing: 0em
  readout-micro:
    fontFamily: JetBrains Mono
    fontSize: 12px
    fontWeight: '500'
    lineHeight: 16px
    letterSpacing: 0em
  panel-title:
    fontFamily: Barlow Condensed
    fontSize: 20px
    fontWeight: '600'
    lineHeight: 24px
    letterSpacing: 0.02em
  body-default:
    fontFamily: Barlow Condensed
    fontSize: 15px
    fontWeight: '400'
    lineHeight: 20px
    letterSpacing: 0.01em
  label-caps:
    fontFamily: Barlow Condensed
    fontSize: 12px
    fontWeight: '600'
    lineHeight: 16px
    letterSpacing: 0.08em
  label-micro:
    fontFamily: Barlow Condensed
    fontSize: 11px
    fontWeight: '600'
    lineHeight: 14px
    letterSpacing: 0.08em
  button-text:
    fontFamily: Barlow Condensed
    fontSize: 13px
    fontWeight: '700'
    lineHeight: 16px
    letterSpacing: 0.06em
rounded:
  sm: 0.125rem
  DEFAULT: 0.25rem
  md: 0.375rem
  lg: 0.5rem
  xl: 0.75rem
  full: 9999px
spacing:
  gutter: 1rem
  margin: 1rem
  space-xs: 0.25rem
  space-sm: 0.5rem
  space-md: 1rem
  space-lg: 1.5rem
  space-xl: 2rem
---

## Brand & Style

This design system establishes an unapologetically utilitarian, high-density control environment modeled after laboratory bench instruments and industrial automation control consoles. Engineered specifically for direct hardware integration with an ESP32-driven packing conveyor, the visual language avoids decorative trends in favor of legibility, spatial determinism, and unambiguous mechanical feedback.

The target operators are technicians, hardware engineers, and plant supervisors who require high-frequency status scanning and error-free actuation under variable factory illumination. The interface prioritizes:
- **Structural Orthogonality:** Everything aligns strictly to an uninterrupted structural grid. Surfaces read as bolted, machined sub-racks rather than floating web containers.
- **Instrument-Grade Restraint:** Zero drop shadows, zero background blurs, zero decorative gradients, and zero simulated skeuomorphic depths. Contrast and physical state changes are expressed solely via discrete color switches, crisp border deltas, and sharp fill transitions.
- **Nameplate Precision:** Dense labels, standardized technical acronyms, uppercase tracking, and tabular numeric readouts ensure rapid parsing without cognitive fatigue.

## Colors

The palette employs an ultra-low-sheen dark instrument chassis scheme designed to preserve dark adaptation and prevent eye strain across long shifts.

### Chassis & Structure
- **Base Canvas (`#141019`):** Deep charcoal navy. Serves as the master backplane and structural floor.
- **Surface Module (`#1D1823`):** Lifted panel tone used for instrument bays, parameter groupings, and meter enclosures.
- **Recessed Inset (`#0D0A11`):** Deep sunken tone for numeric terminal displays and digital readouts.
- **Hairline Division (`#3A3342`):** Crisp 1px structural boundary lines separating all adjacent operator cells.

### Functional Typography
- **Primary Readout (`#EDE8E3`):** High-contrast warm off-white for metrics, real-time telemetry, and active button text.
- **Secondary / Meta (`#A59FAB`):** Muted slate-violet for engineering units, field identifiers, and stationary labels.

### Operational Accents & States
- **Primary Control / Amber (`#E88A3C`):** High-alert mechanical trigger accent (conveyor speed overrides, jog execution, master run toggles). Paired exclusively with `#141019` contrast text.
- **State: Belt Running (`#8FAE8A`):** Low-saturation sage green denoting nominal conveyor operation without harsh optical glare.
- **State: Belt Paused / Standby (`#8A8494`):** Passive grey-violet indicating safe static idle.
- **State: Pusher / Motion (`#7C93A6`):** Slate blue indicating secondary electro-mechanical actuators (diverters, ejectors, indexing gates).
- **State: Fault / Alarm (`#C25B56`):** Controlled brick red indicating jam detections, optical gate interruptions, motor thermal limits, or hardware e-stops.

## Typography

The typographic hierarchy implements an engineering-grade pairing: a condensed DIN/grotesque cadence for headers and operational labels, alongside monospaced tabular numerals for all telemetry and state tracking.

- **Numeric Displays (`JetBrains Mono`):** Enabled with `font-feature-settings: "tnum" 1, "zero" 1`. Telemetry strings, step frequencies, millimeter offsets, and package counts must never shift or oscillate layout widths during high-speed sensor updates.
- **Console Labels (`Barlow Condensed`):** All module markers, unit annotations, switch descriptions, and register states are strictly rendered in uppercase with forced tracking (`+0.08em`).
- **Headlines & Sub-panels:** Sentence case is retained for main system titles at 20px SemiBold to ground the hierarchy without compromising module density.

## Layout & Spacing

Layouts adhere rigidly to an absolute 8px modular baseline grid, with internal subdivisions snapping to 4px. Fluid whitespace is prohibited; every pixel of negative space serves as functional boundary separation.

### Structure & Enclosures
- **Instrument Bay Grid:** A 12-column fixed-density layout. Modules span exact 2, 3, 4, 6, or 12 units. Modules do not expand asynchronously or float on canvas margins.
- **Tiled Adjacency:** Surface modules touch directly along 1px boundary seams (`#3A3342`) or separate by rigid 8px/16px alleys. No overlapping planes, no parallax offsets.
- **Responsive Handling:**
  - **Terminal / Desktop (>= 1024px):** Fixed operational split: System telemetry & belt motor status pinned left (4 cols), center live belt overview & optical array (5 cols), actuator controls & override dials pinned right (3 cols).
  - **Operator Tablet / HMI (600px - 1023px):** Re-flows into 2-column stacked rack panels. Telemetry and live actions maintain equal priority.
  - **Handheld Diagnostic (< 600px):** Single-column stacked instrument banks. All critical buttons increase touch boundary targets to a minimum of 44px height while retaining precise 1px borders.

## Elevation & Depth

This system operates entirely flat across the Z-axis. Spatial hierarchy is communicated through structural enclosure and luminance contrast:

- **Zero Shadows:** `box-shadow: none` is globally enforced. No drop shadows, inset shadows, or peripheral blurs.
- **Zero Gradients:** Gradients are entirely disallowed. Every surface fill is flat and opaque.
- **Zero Glassmorphism:** Opaque `#141019` chassis and `#1D1823` panel fills ensure total contrast preservation against ESP32 signal output delays.
- **1px Hairline Architecture:** Visual containment is achieved entirely through solid, single-pixel borders (`#3A3342`). Modules nest cleanly like brushed-metal racks.
- **Recessed Data Wells:** Digital displays and telemetry graphs drop to `#0D0A11` background fills bordered by `#3A3342` to simulate physical LCD/VFD recessed bezel windows.

## Shapes

The form factor mimics CNC-machined faceplates and pressed-steel instrumentation panels.

- **Corner Radii:** Strict maximum of `4px` (`roundedness: 1`). Buttons, sub-panels, input fields, and indicator chips must never exceed `4px`.
- **Inner Indicators:** Data badges, status lights, and segmented register tags utilize `0px` or `2px` corners to enforce crisp engineering geometry. Circular geometries (`50%` radius) are restricted strictly to miniature LED status beacons (diameter <= 8px).

## Components

### Actuator Buttons
- **Primary / Master Run:** Solid `#E88A3C` background with bold `#141019` uppercase text. Maximum 4px radius. 1px border matches base background. Hover: Brightens slightly (`#F2994E`). Active: Insets text 1px down/right; no drop shadows.
- **Secondary / Step-Jog:** Background `#1D1823`, 1px border `#3A3342`, text `#EDE8E3`. Active/Armed: Border shifts to `#7C93A6`, background shifts to `#26202E`.
- **Emergency / Stop:** Background `#C25B56`, text `#EDE8E3`, border `#C25B56`. Always high-visibility, minimum 48px height.

### Status Indicators & Tally Chips
- Monospace label + uppercase status string encapsulated in a 1px border frame.
- **Running:** Border `#8FAE8A`, text `#8FAE8A`, background `#141019`. Includes an optional 6px solid square glyph (`■ RUN`).
- **Paused:** Border `#8A8494`, text `#8A8494`, background `#141019` (`■ IDLE`).
- **Actuating / Pusher:** Border `#7C93A6`, text `#7C93A6`, background `#141019` (`▲ ENGAGED`).
- **Fault / Sensor Fail:** Border `#C25B56`, text `#C25B56`, background `#231518` (`✖ JAM DETECT`).

### Numeric Readout Bays (VFD / LCD Panel Style)
- Recessed `#0D0A11` background, enclosed with 1px `#3A3342` border.
- Primary number rendered at `40px` (`JetBrains Mono`, SemiBold, `#EDE8E3`).
- Sub-unit label (e.g., `MM/S`, `PPM`, `RPM`) rendered at `11px` (`Barlow Condensed`, bold, `#A59FAB`, uppercase, top-right or bottom-right anchored).

### Input Fields & Stepper Counters
- Monospace numerical values inside an opaque `#141019` field with 1px `#3A3342` border.
- Integrated left/right increment decoders (`-` and `+`) styled as bordered 1px inline boxes rather than smooth arrows.
- Focus state: Border shifts to `#E88A3C` with zero glow/ring effect.

### Instrument Cards & Sub-Racks
- Background `#1D1823` with complete 1px `#3A3342` perimeter border.
- Module Header Bar: Top 28px region with a bottom 1px `#3A3342` border dividing it from the content payload. Contains uppercase 12px panel title in `#A59FAB` alongside a hardware address or index tag (e.g., `MOD-01 // BELT_FEEDER`).

### Segmented Position Gauges
- Horizontal arrays of discrete rectangular block cells representing optical gate paths or conveyor belt segments.
- Idle segment: Flat `#1D1823` fill with 1px `#3A3342` border.
- Triggered / Loaded segment: Solid `#7C93A6` or `#E88A3C` fill, non-blinking, zero illumination halo.