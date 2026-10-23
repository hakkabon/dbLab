# Phase 7 — Large-signal and multiphysics

Phase 7 adds `DBLabMultiphysics`, a deterministic large-signal layer built on
the complex driver traces produced by the NumericCore sparse AC solution.

## Coupled model

For every requested RMS input voltage, the simulator:

1. scales the solved driver voltage, current, pressure, displacement, and vent velocity;
2. iterates copper loss, coil temperature, and temperature-dependent DC resistance to convergence;
3. applies the resulting thermal power compression;
4. evaluates excursion-relative motor and suspension softening;
5. estimates nonlinear distortion from the motor/compliance gain deficit;
6. applies smooth vent compression as air speed approaches the configured Mach limit; and
7. reports the first thermal, excursion, or vent-velocity operating limit.

The workspace presents maximum compression and voice-coil temperature against
input voltage, plus the frequency-dependent estimated distortion at the highest
drive level. Project archives retain the sweep and thermal assumptions.

## Interpretation and limits

The model is intended for design comparison and limit discovery. Generic
thermal and nonlinear coefficients are used because conventional Thiele/Small
records do not include thermal impedance, `Bl(x)`, `Kms(x)`, or `Le(x)` curves.
Measured large-signal parameter curves and multi-node thermal networks can be
added without changing the result contract. This phase does not claim Klippel-
grade distortion prediction or transient diaphragm finite-element analysis.
