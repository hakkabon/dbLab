# Design-grade enclosure simulation

`DBLabEnclosure` implements the Phase 3 linear small-signal enclosure model. It
is independent of SwiftUI and uses `DBLabDomain` contracts plus `ACComplex` from
the NumericCore integration boundary.

## Driver derivation

The current driver schema contains enough Thiele/Small data to derive the
electromechanical equivalent without inventing `Mms`, `Cms`, `Rms`, or `Bl`:

- `Cms` comes from `Vas`, cone area, air density, and sound speed.
- `Mms` follows from `Fs` and `Cms`.
- `Rms` follows from `Qms`.
- `Bl` follows from `Qes`, `Re`, `Mms`, and `Fs`.

The model combines voice-coil resistance and inductance with the motional
impedance. This complete complex impedance becomes the driver load stamped into
the NumericCore AC network when measured ZMA data is not selected.

## Enclosure networks

- Open baffle uses the free-air mechanical system and a complex dipole
  cancellation term determined by baffle width.
- Sealed boxes add the air-spring compliance and a finite box-loss Q. Alignment
  output includes compliance ratio, system resonance, and estimated `Qtc`.
- Vented boxes use acoustic box compliance in parallel with port acoustic mass
  and resistance. Tuning determines acoustic mass; diameter determines vent
  area and the Helmholtz length estimate.

Every frequency point returns electrical impedance, cone displacement and
velocity per terminal volt, cone pressure, optional port pressure and velocity,
and combined pressure. The crossover applies its solved complex terminal
voltage, converting motion from RMS phasors to peak values so excursion and
vent-speed traces include actual passive-network loading and compare correctly
with one-way peak Xmax.

## Design checks and scope

Simulation results warn when predicted cone excursion exceeds the driver's
linear Xmax or vent speed exceeds Mach 0.10. These are linear design checks, not
nonlinear limiting models. Imported FRD and ZMA data remain authoritative and
are not automatically transformed between free-air, IEC baffle, and installed
enclosure fixtures because that transformation requires measurement metadata
not guaranteed by common FRD/ZMA files.
