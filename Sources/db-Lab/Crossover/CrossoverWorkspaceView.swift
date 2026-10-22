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
                        frequencyResponseID: $document.wooferFrequencyResponseID,
                        impedanceID: $document.wooferImpedanceID,
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
                        frequencyResponseID: $document.tweeterFrequencyResponseID,
                        impedanceID: $document.tweeterImpedanceID,
                        enclosure: $document.tweeterEnclosure,
                        volume: $document.tweeterBoxVolumeLiters,
                        tuning: $document.tweeterPortTuningHz,
                        portDiameter: $document.tweeterPortDiameterCentimeters,
                        baffleWidth: $document.tweeterBaffleWidthMeters,
                        band: .highPass
                    )
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Custom passive LCR crossover")
                        .font(.title2.weight(.semibold))
                    Text("The passive LCR network below is solved against the selected driver impedances. Connect the source and output nets to ground through the crossover as appropriate.")
                        .foregroundStyle(.secondary)
                    SchematicEditorView(document: document.schematic)
                        .frame(minHeight: 420)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                }

                networkAssignments

                HStack {
                    Button {
                        document.simulate(using: driverLibrary)
                    } label: {
                        if document.isSimulating {
                            ProgressView().controlSize(.small)
                        } else {
                            Label("Simulate electrical + acoustic response", systemImage: "waveform.path")
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
                        .textSelection(.enabled)
                }
                ForEach(document.simulationWarnings, id: \.self) { warning in
                    Label(warning, systemImage: "info.circle")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }

                if !document.acousticResponse.isEmpty {
                    responsePlot
                }
            }
            .padding(24)
        }
        .navigationTitle(document.name)
    }

    private var crossoverSettings: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 8) {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 200), alignment: .leading)], alignment: .leading, spacing: 14) {
                    numericSetting("Target crossover frequency (reference)", unit: "Hz", value: $document.targetFrequencyHz)
                }
                Text("Reference only; the schematic components determine the simulated crossover.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
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
        frequencyResponseID: Binding<UUID?>,
        impedanceID: Binding<UUID?>,
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
                .onChange(of: driverID.wrappedValue) { _, _ in
                    frequencyResponseID.wrappedValue = nil
                    impedanceID.wrappedValue = nil
                    if band == .lowPass {
                        document.wooferDriverSnapshot = nil
                    } else {
                        document.tweeterDriverSnapshot = nil
                    }
                }

                if let id = driverID.wrappedValue,
                   let driver = driverLibrary.drivers.first(where: { $0.id == id }) {
                    Text("Fs \(driver.fsHz.formatted(.number.precision(.significantDigits(3)))) Hz"
                         + "  ·  Qts \(driver.qts.formatted(.number.precision(.significantDigits(3))))"
                         + "  ·  \(driver.sensitivityDb.formatted(.number.precision(.fractionLength(1)))) dB")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    measurementPicker(
                        title: "Measured frequency response",
                        kind: .frequencyResponse,
                        measurements: driver.measurements,
                        selection: frequencyResponseID
                    )
                    measurementPicker(
                        title: "Measured impedance",
                        kind: .impedance,
                        measurements: driver.measurements,
                        selection: impedanceID
                    )
                    if frequencyResponseID.wrappedValue != nil {
                        Text("Measured response is treated as the complete acoustic response at 2.83 V / 1 m; enclosure fields are not applied to this branch.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Text("Add or import driver data in Speaker Drivers.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Group {
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
                }
                .disabled(frequencyResponseID.wrappedValue != nil)

                Text(band == .lowPass ? "Low-pass branch" : "High-pass branch")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } label: {
            Label(title, systemImage: "speaker.wave.2")
                .font(.headline)
        }
    }

    private var networkAssignments: some View {
        GroupBox {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 250), alignment: .leading)], alignment: .leading, spacing: 14) {
                nodePicker("Input net", selection: binding(for: \.inputNetID))
                nodePicker("Woofer output net", selection: binding(for: \.wooferOutputNetID))
                nodePicker("Tweeter output net", selection: binding(for: \.tweeterOutputNetID))
            }
            .padding(.vertical, 4)
        } label: {
            Label("Electrical network node assignments", systemImage: "point.3.connected.trianglepath.dotted")
                .font(.headline)
        }
    }

    private var availableOutputNets: [Net] {
        document.schematic.nets.filter { !$0.isGround }
    }

    private func binding(for keyPath: ReferenceWritableKeyPath<CrossoverDocument, Int?>) -> Binding<Int?> {
        Binding(
            get: { document[keyPath: keyPath] },
            set: { document[keyPath: keyPath] = $0 }
        )
    }

    private func nodePicker(_ title: String, selection: Binding<Int?>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Picker(title, selection: selection) {
                Text("Select net").tag(Int?.none)
                ForEach(availableOutputNets) { net in
                    Text(netLabel(net)).tag(Optional(net.id))
                }
            }
            .labelsHidden()
            if availableOutputNets.isEmpty {
                Text("Place and wire components to create nets.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func netLabel(_ net: Net) -> String {
        let symbolsByID = Dictionary(uniqueKeysWithValues: document.schematic.symbols.map { ($0.id, $0) })
        let pinNames = net.connectedPins.compactMap { pin -> String? in
            guard let symbol = symbolsByID[pin.symbolId] else { return nil }
            return "\(symbol.refDes).\(pin.pinId)"
        }
        let pins = pinNames.isEmpty ? "unconnected" : pinNames.joined(separator: ", ")
        return "\(net.name) (\(pins))"
    }

    private func measurementPicker(
        title: String,
        kind: DriverMeasurementKind,
        measurements: [DriverMeasurement],
        selection: Binding<UUID?>
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Picker(title, selection: selection) {
                Text("Use estimated model").tag(UUID?.none)
                ForEach(measurements.filter { $0.kind == kind }) { measurement in
                    Text("\(measurement.sourceFileName) · \(measurement.points.count) pts")
                        .tag(Optional(measurement.id))
                }
            }
            .labelsHidden()
        }
    }

    private var responsePlot: some View {
        GroupBox("System SPL response") {
            VStack(alignment: .leading, spacing: 8) {
                Text("The input source is 2.83 V RMS. Driver terminal voltages come from the passive network solution.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
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
