# Phase 6 — Spatial and advanced acoustics

Phase 6 adds a reusable `DBLabAcoustics` layer after the NumericCore-backed
electrical solve. It preserves each driver's complex pressure and applies
geometry before summing the system response.

## Model

- Driver acoustic-center offsets in horizontal, vertical, and depth axes.
- Propagation delay and inverse-distance attenuation from every driver to the listener.
- Frequency-dependent circular-piston directivity derived from effective radiating diameter (`Sd`).
- Optional frequency-dependent air attenuation.
- Optional floor bounce through an image source and signed reflection coefficient.
- Horizontal polar curves, a ±30° listening-window average, approximate front-hemisphere sound power, and directivity index.

Complex electrical voltages still come from `DBLabNumeric` and Swift-NumericCore's
sparse solver. `DBLabAcoustics` uses `ACComplex` for phase-safe propagation and
summation, keeping the numerical boundary shared with AC and crossover analysis.

## Scope

This is a deterministic free-field/design model. Piston directivity is inferred
from diaphragm area, so imported off-axis manufacturer data should supersede it
in a future measurement-directivity phase. Floor reflection is a single image
source; full room modes, diffraction meshes, boundary-element analysis, and
measured spinorama ingestion remain outside this phase.
