# Robust crossover design

Phase 5 extends `DBLabSynthesis` from nominal optimization to manufacturing and
load uncertainty. It operates on the exact E24 network produced by Phase 4 and
continues to evaluate circuits through `DBLabNumeric` and NumericCore's sparse
AC factorization.

## Uncertainty model

Each analysis specifies:

- symmetric component-value tolerance;
- coherent driver-load magnitude variation;
- coherent driver-load phase variation;
- allowed magnitude-response error;
- minimum system input impedance inherited from synthesis;
- sample count and deterministic seed.

Sampling is stratified independently by dimension and driven by a recorded
SplitMix64 seed. Results are reproducible for the same design, options, and
NumericCore revision.

## Robust refinement

Before statistical analysis, a discrete coordinate search examines adjacent
E24 values. Candidates are scored at nominal conditions and coordinated
tolerance corners. The recommended design therefore remains buildable rather
than returning idealized continuous values.

## Reported results

- 5th, median, and 95th percentile electrical response envelopes;
- yield against response-error and minimum-impedance requirements;
- worst sampled response error and input impedance;
- ranked component sensitivity from symmetric tolerance perturbations;
- number of E24 values changed by robust refinement;
- sample count, seed, and backend identifier.

The robust recommendation is applied through the same explicit schematic
replacement confirmation as nominal synthesis. It remains an editable network
and should be followed by the full electrical, acoustic, excursion, and vent
simulation.

## Interpretation

This is a linear tolerance study. It does not replace measured production
statistics, thermal/nonlinear simulation, aging tests, or a tolerance model
with part-specific probability distributions and correlations. The deterministic
envelope is intended to expose fragile designs early and make tradeoffs visible.
