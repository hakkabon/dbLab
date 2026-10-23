# db-Lab

**db-Lab** is a loudspeaker design application targeting macOS 14+ and iPadOS 17+. It includes a local loudspeaker driver library, two-way system setup, first-pass acoustic response estimates for open-baffle, closed-box, and ported-box enclosures, and a custom schematic editor for passive LCR crossovers.

## Architecture

The **Schematic is the document**: it contains component placement, wires, connections, and parameters.

### Layer 1: The Schematic Model (Source of Truth)
This layer represents the visual design and its geometric context:
*   **Symbols:** Component references, grid-aligned positions, rotations, and typed SI parameters.
*   **Wires:** Orthogonal, grid-aligned point arrays representing physical traces.
*   **Parameters:** Typed SI values stored on each component instance, with engineering-unit labels shown in the editor.

### Layer 2: The Connectivity Model (The Graph)
Derived entirely from Layer 1, this layer answers the question: *"What is electrically connected to what?"*
*   **Union-Find Engine:** Evaluates connectivity by spatially hashing pin endpoints and wire vertices onto a grid.
*   **Nets:** Disjoint sets of pins that share the same electrical node.
*   **Ground Detection:** Automatically identifies the `Node 0` reference based on Ground symbols.
*   *Note: Visual wire crossings without an explicit junction or endpoint-to-wire connection are intentionally ignored, preventing accidental shorts.*

---

## Key Frontend Features

*   **Custom Native Canvas:** Uses native Core Graphics drawing for the grid, wires, and symbols, with pan and zoom on both macOS and iPadOS.
*   **Crossover projects:** Set a target crossover frequency, select two drivers, and model woofer/tweeter branches.
*   **Passive-only component palette:** Design custom networks using resistors, capacitors, inductors, and inductors with series resistance.
*   **Crossover synthesis:** Optimize Butterworth or Linkwitz–Riley passive ladders against complex driver loads, standardize them to E24 values, inspect fit and minimum impedance, and apply them to the editable schematic.
*   **Robust design:** Analyze component and driver-load tolerances with reproducible stratified sampling, inspect percentile response envelopes and yield, identify sensitive components, and apply a tolerance-resistant E24 refinement.
*   **Spatial acoustics:** Model driver acoustic-center offsets, propagation delay, piston directivity, air loss, and floor bounce; inspect listening-window, sound-power, directivity-index, and horizontal polar results.
*   **Speaker driver library:** Create, edit, delete, import, and export driver records, including Thiele/Small values and a source reference.
*   **Design-grade enclosure simulation:** Compare open-baffle, sealed, and vented alignments with enclosure-modified impedance, complex acoustic pressure, cone excursion, and vent air speed.
*   **Two-way acoustic response:** Solve the passive LCR schematic using driver impedance and combine electrical branch voltages with measured or modeled acoustic response.
*   **Measured driver data:** Import FRD frequency response and ZMA impedance files, retain provenance, and select datasets per driver in a crossover project.
*   **Schematic Editor:** Place and rotate LCR components, edit their values, and draw orthogonal wires.
*   **Connectivity model:** Derive electrical nets from component pins and wires.

## Project Structure

```text
Sources/
├── DBLabDomain/                  # SwiftUI-free domain and simulation contracts
├── db-LabApp/                    # Thin executable/application entry point
└── db-Lab/                       # Reusable DBLabCore target
    ├── Shared/                   # App state and navigation
    ├── Crossover/                # Driver library, acoustic model, project workspace
    └── Schematic/                # Schematic document and connectivity
        ├── Models.swift          # Layer 1: Schematic Document
        ├── ConnectivityBuilder.swift
        ├── ComponentRegistry.swift
        └── Views/                # Custom NSView/UIView Canvas
```

`DBLabDomain` contains immutable driver revisions, calibrated measurement datasets, N-way loudspeaker-system models, and backend-neutral simulation request/result types without importing SwiftUI. `DBLabNumeric` is the AC-analysis boundary: it models complex two-terminal networks, frequency-dependent tabulated impedances, sparse nodal assembly, and solver diagnostics. `DBLabCore` adapts the current two-way workspace to those packages. Complex systems are converted to equivalent real sparse block systems and solved through NumericCoreSparse; symbolic topology analysis is reused while numerical values are refactored across a sweep. The application target contains no numerical engine of its own.

## Quick Start

```bash
cd db-Lab
swift run
```

Swift Package Manager resolves the pinned NumericCore revision and its matching binary artifact automatically.

## Workflows

### Driver Library
1. Open **Speaker Drivers** in the sidebar and add manufacturer data or import a JSON library.
2. Record the source (manufacturer datasheet URL or reference) with each driver. `Qts` is calculated from `Qes` and `Qms`.
3. In a driver's editor, import frequency response (`.frd`) or impedance (`.zma`) data as UTF-8 text with two or three columns: frequency (Hz), magnitude (dB SPL for FRD or Ω for ZMA), and optional phase (degrees). Commas, tabs, and whitespace are accepted; comment lines starting with `#`, `;`, `*`, or `//` are ignored.
4. Record a source URL/reference or measurement conditions before importing. Calibration fields capture reference voltage, distance, angle, fixture, smoothing, and phase reference. Each dataset retains its filename, source reference, import date, SHA-256 source hash, byte count, frequency points, and whether phase was supplied. Data must contain at least two finite, positive-frequency rows; duplicate frequencies and non-positive impedance magnitudes are rejected. FRD levels are normalized non-destructively to 2.83 V / 1 m during simulation.
5. Export the complete local library as JSON for backup or transfer.

The library is stored in `Application Support/db-Lab/speaker-drivers.json` as a versioned archive; the previous unversioned array format migrates automatically. Editing a driver creates a new immutable revision and preserves its preceding revisions in the archive. JSON interchange continues to use an array of current driver records and imports merge records by ID.

### Speaker System
1. Create a crossover project and select a woofer and tweeter from the library.
2. Select each driver's measured FRD/ZMA datasets, or leave the selectors on the estimated/modelled options. A measured FRD is used as the complete acoustic response for that driver; the enclosure model is used when no FRD is selected.
3. Choose an enclosure and enter its dimensions for branches using the modeled response. For a ported box, enter diameter and tuning; the app estimates port length.
4. Build the passive network in the schematic. Select the source input net and each driver's output net below the schematic. Place a ground symbol on the common return; the simulator treats each driver as a load from its selected output to ground.
5. Choose **Simulate electrical + acoustic response**. The simulator applies a 2.83 V RMS AC source to the input net, solves the passive network over frequency, and plots woofer, tweeter, and coherently summed response.

The network solver supports passive resistors, capacitors, inductors, and inductors with series resistance, using sparse complex nodal analysis and the selected drivers as loads. Matrix factorization and iterative refinement are provided by NumericCore. Without ZMA data, `DBLabEnclosure` derives `Cms`, `Mms`, `Rms`, and `Bl` from the driver's Thiele/Small data and reflects the sealed or vented acoustic load back into electrical impedance. Selected ZMA data remains the source of truth when present. The same small-signal model predicts complex cone/vent pressure, diaphragm excursion, and vent air speed at the terminal voltage solved by the crossover. Selected FRD data supplies SPL magnitude and phase; otherwise the physical enclosure response is used. Phase-less measurements are treated as zero phase and identified in simulation warnings. Measured data limits the plotted sweep to the common frequency range covered by all selected datasets. Per-frequency residual and sparse-factor diagnostics are retained in the simulation result.

This is a linear lumped-parameter design simulation, not a boundary-element or measurement-matched full loudspeaker simulation. The virtual source is ideal (no source/output resistance). Measured FRD is assumed to represent the complete driver response at 2.83 V / 1 m and is not reshaped by the enclosure; measured ZMA is likewise treated as the complete installed load. The physical fallback includes configurable representative box and vent loss Q values, but not panel vibration, detailed baffle diffraction, room effects, higher vent modes, cone breakup, thermal compression, suspension nonlinearity, or turbulent port compression. Xmax and Mach 0.10 checks are warnings rather than nonlinear clipping models. Port length uses a conventional Helmholtz estimate with a simple end correction. The reference crossover frequency is a design note and does not alter the solved network; Bessel filter synthesis and automatic component selection are not implemented.

Crossover projects are automatically saved to `Application Support/db-Lab/crossover-projects.json` using a versioned JSON archive. Project snapshots include crossover and enclosure settings, an N-way domain-system representation, immutable snapshots of selected driver revisions and measurements, stable schematic pin references for node assignments, and schematic symbols and wires. The current workspace remains a two-way compatibility UI while the persisted domain model supports arbitrary driver instances. Simulations run from an immutable request off the main actor and can be cancelled by starting a new run. Results retain complex input impedance, terminal voltage, current, per-driver acoustic pressure, combined pressure, warnings, and backend identity in addition to the displayed SPL curves.

## Requirements
- macOS 14+
- iPadOS 17+
- Xcode 15+ / Swift 6
The Swift package declares macOS 14+ and iOS 17+ deployment targets. The iOS target is intended for iPadOS; the app uses SwiftUI's adaptive split navigation for tablet layouts.
