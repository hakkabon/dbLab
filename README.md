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
*   **Two-way acoustic response:** Plot woofer, tweeter, and combined SPL with idealized Butterworth or Linkwitz–Riley crossover slopes.
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
3. Export the complete local library as JSON for backup or transfer.

The library is stored in `Application Support/db-Lab/speaker-drivers.json`. JSON import/export uses an array of driver records with the `SpeakerDriver` fields shown in the editor; imports merge records by ID.

### Speaker System
1. Create a crossover project and select a woofer and tweeter from the library.
2. Choose each driver's open-baffle, closed-box, or ported-box alignment and enter the required dimensions. For a ported box, enter diameter and tuning; the app estimates port length.
3. Set the crossover frequency and idealized Butterworth (6–24 dB/octave) or Linkwitz–Riley (12 or 24 dB/octave) alignment, then choose **Simulate acoustic response**.
4. Review the individual branch and combined estimated SPL curves. Design the passive LCR network separately in the schematic.

The acoustic model is an initial Thiele/Small low-frequency approximation, not a measurement-matched prediction. It assumes the entered driver sensitivity is flat outside the modeled enclosure behavior, idealized electrical crossover filters, equal acoustic-center timing, and no room effects, diffraction, port losses, cone breakup, or excursion limiting. Port length uses a conventional Helmholtz estimate with a simple end correction. For a 12 dB/octave Linkwitz–Riley alignment, the tweeter branch is polarity-inverted. The response plot does not yet solve the custom LCR schematic against a driver's complex impedance; Bessel crossovers and automatic passive-component synthesis are also not yet available.

Crossover projects are automatically saved to `Application Support/db-Lab/crossover-projects.json` using a versioned JSON archive. Project snapshots include crossover and enclosure settings, driver IDs, and schematic symbols and wires.

## Requirements
- macOS 14+
- iPadOS 17+
- Xcode 15+ / Swift 6
The Swift package declares macOS 14+ and iOS 17+ deployment targets. The iOS target is intended for iPadOS; the app uses SwiftUI's adaptive split navigation for tablet layouts.
