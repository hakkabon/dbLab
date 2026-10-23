# DBLab domain foundation

`DBLabDomain` is the headless contract shared by interactive UI, tests, future
command-line tools, and numerical backends. It deliberately contains no
SwiftUI, AppKit, UIKit, persistence location, or NumericCore backend policy.

## Ownership

- `DBLabDomain` owns loudspeaker terminology, immutable driver revisions,
  measurement calibration, N-way system configuration, and simulation data.
- `DBLabCore` owns the current SwiftUI workflow, schematic editor, persistence
  coordination, and adapters from the prototype's two-way document.
- Swift-NumericCore owns matrix assembly/factorization and optimization APIs.
- Rust-NumericCore remains available behind Swift-NumericCore for portable and
  high-throughput implementations.

## Migration boundary

The current UI still exposes woofer and tweeter controls. Every saved project
also carries a `LoudspeakerSystem` assembled from those controls, and preserves
non-woofer/tweeter instances already present in the domain model. This allows a
future N-way editor to replace the compatibility fields incrementally without
another numerical or persistence redesign.

## Calibration convention

Original measurement samples are immutable. Frequency-response calibration is
applied when a simulation consumes a dataset. The current normalization target
is 2.83 V RMS at 1 metre:

`gain_dB = 20 log10(Vtarget / Vsource) + 20 log10(Dsource / Dtarget)`

Missing calibration fields contribute no correction and remain visible as
unknown metadata rather than being invented.
