import Charts
import SwiftUI

struct CrossoverWorkspaceView: View {
    @ObservedObject var document: CrossoverDocument
    @ObservedObject var driverLibrary: DriverLibrary

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 6) {
                    TextField("Crossover name", text: $document.name)
                        .font(.largeTitle.weight(.semibold))
                        .textFieldStyle(.plain)
                        .frame(maxWidth: 520)
                    Text("Passive loudspeaker system")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }

                crossoverSettings

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 330), alignment: .top)], alignment: .leading, spacing: 16) {
                    driverBranch(
                        title: "Woofer",
                        driverID: $document.wooferDriverID,
                        enclosure: $document.wooferEnclosure,
                        volume: $document.wooferBoxVolumeLiters,
                        tuning: $document.wooferPortTuningHz,
                        portDiameter: $document.wooferPortDiameterCentimeters,
                        baffleWidth: $document.wooferBaffleWidthMeters,
                        band: .lowPass
                    )
                    driverBranch(
                        title: "Tweeter",
                        driverID: $document.tweeterDriverID,
                        enclosure: $document.tweeterEnclosure,
                        volume: $document.tweeterBoxVolumeLiters,
                        tuning: $document.tweeterPortTuningHz,
                        portDiameter: $document.tweeterPortDiameterCentimeters,
                        baffleWidth: $document.tweeterBaffleWidthMeters,
                        band: .highPass
                    )
                }

                HStack {
                    Button {
                        document.simulate(using: driverLibrary)
                    } label: {
                        if document.isSimulating {
                            ProgressView().controlSize(.small)
                        } else {
                            Label("Simulate acoustic response", systemImage: "waveform.path")
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(document.isSimulating)
                    Spacer()
                    if !driverLibrary.drivers.isEmpty {
                        Text("\(driverLibrary.drivers.count) drivers in library")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                if let error = document.simulationError {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                }

                if !document.acousticResponse.isEmpty {
                    responsePlot
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Custom passive LCR crossover")
                        .font(.title2.weight(.semibold))
                    Text("The schematic is an editable design drawing. This initial acoustic simulation uses ideal Butterworth or Linkwitz–Riley electrical slopes and does not yet solve this LCR network against the drivers' impedance.")
                        .foregroundStyle(.secondary)
                    SchematicEditorView(document: document.schematic)
                        .frame(minHeight: 420)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                }
            }
            .padding(24)
        }
        .navigationTitle(document.name)
        .onChange(of: document.crossoverAlignment) { _, alignment in
            if alignment == .linkwitzRiley && document.crossoverOrder != 2 && document.crossoverOrder != 4 {
                document.crossoverOrder = 4
            }
        }
    }

    private var crossoverSettings: some View {
        GroupBox {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 200), alignment: .leading)], alignment: .leading, spacing: 14) {
                numericSetting("Crossover frequency", unit: "Hz", value: $document.targetFrequencyHz)
                VStack(alignment: .leading, spacing: 6) {
                    Text("Ideal filter alignment").font(.caption).foregroundStyle(.secondary)
                    Picker("Filter alignment", selection: $document.crossoverAlignment) {
                        ForEach(CrossoverAlignment.allCases) { alignment in
                            Text(alignment.rawValue).tag(alignment)
                        }
                    }
                    .labelsHidden()
                }
                VStack(alignment: .leading, spacing: 6) {
                    Text("Filter order").font(.caption).foregroundStyle(.secondary)
                    Picker("Filter order", selection: $document.crossoverOrder) {
                        ForEach(document.crossoverAlignment == .linkwitzRiley ? [2, 4] : [1, 2, 3, 4], id: \.self) { order in
                            Text("\(order * 6) dB/octave").tag(order)
                        }
                    }
                    .labelsHidden()
                }
            }
            .padding(.vertical, 4)
        } label: {
            Label("Two-way system", systemImage: "slider.horizontal.3")
                .font(.headline)
        }
    }

    private func driverBranch(
        title: String,
        driverID: Binding<UUID?>,
        enclosure: Binding<EnclosureType>,
        volume: Binding<Double>,
        tuning: Binding<Double>,
        portDiameter: Binding<Double>,
        baffleWidth: Binding<Double>,
        band: DriverBand
    ) -> some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                Picker("\(title) driver", selection: driverID) {
                    Text("Select a driver").tag(UUID?.none)
                    ForEach(driverLibrary.drivers) { driver in
                        Text(driver.displayName).tag(Optional(driver.id))
                    }
                }

                if let id = driverID.wrappedValue,
                   let driver = driverLibrary.drivers.first(where: { $0.id == id }) {
                    Text("Fs \(driver.fsHz.formatted(.number.precision(.significantDigits(3)))) Hz"
                         + "  ·  Qts \(driver.qts.formatted(.number.precision(.significantDigits(3))))"
                         + "  ·  \(driver.sensitivityDb.formatted(.number.precision(.fractionLength(1)))) dB")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text("Add or import driver data in Speaker Drivers.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Picker("\(title) enclosure", selection: enclosure) {
                    ForEach(EnclosureType.allCases) { type in
                        Text(type.rawValue).tag(type)
                    }
                }

                switch enclosure.wrappedValue {
                case .openBaffle:
                    numericSetting("Baffle width", unit: "m", value: baffleWidth)
                case .closedBox:
                    numericSetting("Net box volume", unit: "L", value: volume)
                case .portedBox:
                    numericSetting("Net box volume", unit: "L", value: volume)
                    numericSetting("Port tuning", unit: "Hz", value: tuning)
                    numericSetting("Port diameter", unit: "cm", value: portDiameter)
                    if let length = PortedBoxDesign.portLengthCentimeters(
                        volumeLiters: volume.wrappedValue,
                        tuningHz: tuning.wrappedValue,
                        diameterCentimeters: portDiameter.wrappedValue
                    ) {
                        Text("Approx. port length: \(length.formatted(.number.precision(.fractionLength(1)))) cm")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("These values do not produce a practical positive port length.")
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }

                Text(band == .lowPass ? "Low-pass branch" : "High-pass branch")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } label: {
            Label(title, systemImage: "speaker.wave.2")
                .font(.headline)
        }
    }

    private var responsePlot: some View {
        GroupBox("Estimated on-axis SPL") {
            VStack(alignment: .leading, spacing: 8) {
                Text("At 2.83 V / 1 m reference, summing the selected woofer and tweeter branches.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if document.crossoverAlignment == .linkwitzRiley && document.crossoverOrder == 2 {
                    Text("For a 12 dB/octave Linkwitz–Riley crossover, reverse the tweeter polarity.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Chart {
                    ForEach(document.acousticResponse) { point in
                        LineMark(
                            x: .value("Frequency (Hz)", point.frequencyHz),
                            y: .value("SPL (dB)", point.totalDb),
                            series: .value("Response", "Combined")
                        )
                        .foregroundStyle(Color.primary)
                        .lineStyle(StrokeStyle(lineWidth: 2.5))
                        LineMark(
                            x: .value("Frequency (Hz)", point.frequencyHz),
                            y: .value("SPL (dB)", point.wooferDb),
                            series: .value("Response", "Woofer")
                        )
                        .foregroundStyle(.blue)
                        LineMark(
                            x: .value("Frequency (Hz)", point.frequencyHz),
                            y: .value("SPL (dB)", point.tweeterDb),
                            series: .value("Response", "Tweeter")
                        )
                        .foregroundStyle(.orange)
                    }
                }
                .chartXScale(type: .log)
                .chartXAxisLabel("Frequency (Hz)")
                .chartYAxisLabel("SPL (dB)")
                .frame(height: 320)
            }
        }
    }

    private func numericSetting(_ title: String, unit: String, value: Binding<Double>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            HStack(spacing: 6) {
                TextField(title, value: value, format: .number.precision(.significantDigits(5)))
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 130)
                Text(unit).foregroundStyle(.secondary)
            }
        }
    }
}
