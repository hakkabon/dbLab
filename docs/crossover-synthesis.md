# Passive crossover synthesis

`DBLabSynthesis` implements Phase 4 as a headless package layered on
`DBLabNumeric` and `NumericCoreOptimization`.

## Synthesis workflow

1. Create classical equal-termination ladder seeds for the requested
   Butterworth or Linkwitz–Riley alignment and order.
2. Sample selected measured ZMA data, or the Phase 3 enclosure-modified
   impedance, over two octaves on either side of crossover.
3. Represent component values in logarithmic coordinates so every candidate
   remains positive and scale-independent.
4. Use NumericCore's bounded L-BFGS-B implementation to minimize low-pass and
   high-pass magnitude error. Every objective evaluation uses the same sparse
   complex AC solver as the main application.
5. Penalize combined input impedance below the requested design floor.
6. Round the optimized result to practical E24 values and reevaluate the final
   response and diagnostics using those values.

The result records both continuous optimized values and applied E24 values,
response traces, RMS magnitude error, minimum system input impedance,
optimizer termination, iteration/evaluation counts, and backend identity.

## Schematic application

dbLab displays proposed values and electrical response before making a change.
Applying synthesis requires an explicit replacement confirmation. Generated
low-pass and high-pass ladders share an input and ground, receive stable
component references, and automatically assign input, woofer-output, and
tweeter-output nets. The result remains an ordinary editable schematic;
simulation is still the authority for final electrical, acoustic, excursion,
and vent-speed behavior.

## Scope

The optimizer currently fits electrical transfer magnitudes and an impedance
floor. It does not yet choose among arbitrary graph topologies, optimize driver
offset/directivity, model component parasitics or tolerance Monte Carlo, or
perform mixed-integer stock-bin selection.
