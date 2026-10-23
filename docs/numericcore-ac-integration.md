# NumericCore AC integration

`DBLabNumeric` is the numerical boundary between loudspeaker-domain code and
Swift-NumericCore. It intentionally contains no SwiftUI or persistence code.

## Contracts

- `ACNetwork` describes a fixed-voltage source, reference node, and passive
  two-terminal elements.
- `ACImpedanceModel` supports ideal R/C/L elements, inductor DCR, and tabulated
  complex impedance. Tables interpolate on log frequency and log magnitude and
  unwrap phase along the shortest arc.
- `PreparedACNetwork` validates and indexes topology once. It stamps complex
  nodal equations into the equivalent real sparse block matrix.
- `ACSolutionPoint` exposes node voltages, named element currents, source input
  impedance, and numerical diagnostics.

## Sweep execution

The structural matrix is analyzed once with NumericCoreSparse's
`SparseSymbolicAnalysis`. Each frequency updates only numerical values and calls
`SparseLUFactorization.refactor(with:)`, followed by iterative refinement. This
preserves a fixed sparsity pattern even when a real or imaginary entry happens
to be zero at an individual frequency.

The crossover adapter converts measured or modeled driver impedances to tables
on the requested sweep, solves the network in one prepared operation, and
propagates relative residuals and the backend identifier into the domain-level
simulation diagnostics.

## Verification

Tests cover an analytic RC network over a sweep, tabulated impedance
interpolation and phase wrapping, existing loudspeaker crossover behavior, and
agreement between reusable sparse LU and Rust-NumericCore's direct sparse LU
path exposed by Swift-NumericCore.
