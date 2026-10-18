# db-Lab

**db-Lab** is a loudspeaker design application targeting macOS 14+ and iPadOS 17+. It includes a local loudspeaker driver library, two-way system setup, first-pass acoustic response estimates for open-baffle, closed-box, and ported-box enclosures, and a custom schematic editor for passive LCR crossovers.

## Architecture

The **Schematic is the document**: it contains component placement, wires, connections, and parameters.

### Layer 1: The Schematic Model (Source of Truth)
This layer represents the visual design and its geometric context:
*   **Symbols:** Component references, grid-aligned positions, rotations, and mirroring.
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
*   **Speaker driver library:** Create, edit, delete, import, and export driver records, including Thiele/Small values and a source reference.
*   **Enclosure response estimates:** Compare open-baffle, sealed, and ported low-frequency alignments using each driver's parameters.
*   **Two-way acoustic response:** Solve the passive LCR schematic using driver impedance and combine electrical branch voltages with measured or modeled acoustic response.
*   **Measured driver data:** Import FRD frequency response and ZMA impedance files, retain provenance, and select datasets per driver in a crossover project.
*   **Schematic Editor:** Place and rotate LCR components, edit their values, and draw orthogonal wires.
*   **Connectivity model:** Derive electrical nets from component pins and wires.

## Project Structure

```text
Sources/db-Lab/
├── Shared/                       # App state and navigation
├── Crossover/                    # Driver library, acoustic model, project workspace
├── Schematic/                    # Schematic document and connectivity
│   ├── Models.swift              # Layer 1: Schematic Document
│   ├── ConnectivityBuilder.swift # Layer 2: Union-Find
│   ├── ComponentRegistry.swift   # Data-driven descriptors
│   └── Views/                    # Custom NSView/UIView Canvas
```

## Quick Start (UI development without Rust)

```bash
cd db-Lab
swift run
```

The app compiles and runs without a Rust build.

## Workflows

### Driver Library
1. Open **Speaker Drivers** in the sidebar and add manufacturer data or import a JSON library.
2. Record the source (manufacturer datasheet URL or reference) with each driver. `Qts` is calculated from `Qes` and `Qms`.
3. In a driver's editor, import frequency response (`.frd`) or impedance (`.zma`) data as UTF-8 text with two or three columns: frequency (Hz), magnitude (dB SPL for FRD or Ω for ZMA), and optional phase (degrees). Commas, tabs, and whitespace are accepted; comment lines starting with `#`, `;`, `*`, or `//` are ignored.
4. Record a source URL/reference or measurement conditions before importing. Each dataset retains its filename, source reference, import date, frequency points, and whether phase was supplied. Data must contain at least two finite, positive-frequency rows; duplicate frequencies and non-positive impedance magnitudes are rejected.
5. Export the complete local library as JSON for backup or transfer.

The library is stored in `Application Support/db-Lab/speaker-drivers.json`. JSON import/export uses an array of driver records with the `SpeakerDriver` fields shown in the editor; imports merge records by ID.

### Speaker System
1. Create a crossover project and select a woofer and tweeter from the library.
2. Select each driver's measured FRD/ZMA datasets, or leave the selectors on the estimated/modelled options. A measured FRD is used as the complete acoustic response for that driver; the enclosure model is used when no FRD is selected.
3. Choose an enclosure and enter its dimensions for branches using the modeled response. For a ported box, enter diameter and tuning; the app estimates port length.
4. Build the passive network in the schematic. Select the source input net and each driver's output net below the schematic. Place a ground symbol on the common return; the simulator treats each driver as a load from its selected output to ground.
5. Choose **Simulate electrical + acoustic response**. The simulator applies a 2.83 V RMS AC source to the input net, solves the passive network over frequency, and plots woofer, tweeter, and coherently summed response.

The network solver supports passive resistors, capacitors, inductors, and inductors with series resistance, using complex nodal analysis and the selected drivers as loads. Selected ZMA data supplies the complex load; otherwise the solver approximates it as `Re + jωLe`. Selected FRD data supplies SPL magnitude and phase; absent FRD, the simulator uses the initial Thiele/Small low-frequency enclosure approximation. Phase-less measurements are treated as zero phase and identified in simulation warnings. Measured data limits the plotted sweep to the common frequency range covered by all selected datasets.

This remains a first-pass on-axis estimate, not a measurement-matched full loudspeaker simulation. The virtual source is ideal (no source/output resistance); measured FRD is assumed to represent the complete driver response at 2.83 V / 1 m; the enclosure approximation does not add to measured FRD. Acoustic-center offsets, baffle diffraction, room effects, port losses, cone breakup, power compression, and excursion limits are not modeled. Port length uses a conventional Helmholtz estimate with a simple end correction. The reference crossover frequency is a design note and does not alter the solved network; Bessel filter synthesis and automatic component selection are not implemented.

Crossover projects are automatically saved to `Application Support/db-Lab/crossover-projects.json` using a versioned JSON archive. Project snapshots include crossover and enclosure settings, driver IDs, measurement selections, stable schematic pin references for node assignments, and schematic symbols and wires.

## Requirements
- macOS 14+
- iPadOS 17+
- Xcode 15+ / Swift 6
The Swift package declares macOS 14+ and iOS 17+ deployment targets. The iOS target is intended for iPadOS; the app uses SwiftUI's adaptive split navigation for tablet layouts.
