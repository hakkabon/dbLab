import Charts
import SwiftUI
import DBLabSynthesis

struct CrossoverWorkspaceView: View {
    @ObservedObject var document: CrossoverDocument
    @ObservedObject var driverLibrary: DriverLibrary
    @State private var isApplySynthesisConfirmationPresented = false

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
                spatialSettings

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

                synthesisPanel

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
                    spatialAcousticsPlots
                    operatingLimitsPlot
                    largeSignalPanel
                }
            }
            .padding(24)
        }
        .navigationTitle(document.name)
        .confirmationDialog(
            "Replace the current crossover schematic?",
            isPresented: $isApplySynthesisConfirmationPresented,
            titleVisibility: .visible
        ) {
            Button("Replace schematic", role: .destructive) {
                document.applySynthesizedCrossover()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The synthesized ladder and its node assignments will replace the current symbols and wires.")
        }
    }

    private var crossoverSettings: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 8) {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 200), alignment: .leading)], alignment: .leading, spacing: 14) {
                    numericSetting("Target crossover frequency (reference)", unit: "Hz", value: $document.targetFrequencyHz)
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Synthesis alignment").font(.caption).foregroundStyle(.secondary)
                        Picker("Synthesis alignment", selection: $document.crossoverAlignment) {
                            ForEach(CrossoverAlignment.allCases) { alignment in
                                Text(alignment.rawValue).tag(alignment)
                            }
                        }
                        .labelsHidden()
                        .onChange(of: document.crossoverAlignment) { _, alignment in
                            if alignment == .linkwitzRiley,
                               document.crossoverOrder != 2 && document.crossoverOrder != 4 {
                                document.crossoverOrder = 4
                            }
                        }
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Electrical order").font(.caption).foregroundStyle(.secondary)
                        Picker("Electrical order", selection: $document.crossoverOrder) {
                            ForEach(
                                document.crossoverAlignment == .linkwitzRiley ? [2, 4] : [1, 2, 3, 4],
                                id: \.self
                            ) { order in
                                Text("\(order)").tag(order)
                            }
                        }
                        .labelsHidden()
                    }
                }
                Text("These targets drive synthesis; after application, schematic components determine the simulated crossover.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 4)
        } label: {
            Label("Two-way system", systemImage: "slider.horizontal.3")
                .font(.headline)
        }
    }

    private var synthesisPanel: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                Text("Generate a passive ladder from the selected drivers, enclosure loading, target alignment, and order. NumericCore refines classical prototype values against both complex loads.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                HStack(alignment: .bottom, spacing: 12) {
                    numericSetting(
                        "Minimum system impedance", unit: "Ω",
                        value: $document.synthesisMinimumImpedanceOhms
                    )
                    Button {
                        document.synthesizeCrossover(using: driverLibrary)
                    } label: {
                        if document.isSynthesizing {
                            ProgressView().controlSize(.small)
                        } else {
                            Label("Synthesize crossover", systemImage: "wand.and.stars")
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(
                        document.isSynthesizing
                            || document.wooferDriverID == nil
                            || document.tweeterDriverID == nil
                    )
                }
                if let error = document.synthesisError {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                }
                if let result = document.synthesisResult {
                    HStack(spacing: 18) {
                        Text("RMS fit error: \(result.rmsMagnitudeErrorDecibels.formatted(.number.precision(.fractionLength(2)))) dB")
                        Text("Minimum input: \(result.minimumInputImpedanceOhms.formatted(.number.precision(.fractionLength(2)))) Ω")
                        Text("\(result.preferredValueSeries) values")
                        Text("\(result.iterations) iterations")
                    }
                    .font(.caption.monospacedDigit())
                    LazyVGrid(
                        columns: [GridItem(.adaptive(minimum: 260), alignment: .leading)],
                        alignment: .leading, spacing: 8
                    ) {
                        synthesizedBranch(result.lowPass, title: "Woofer low-pass")
                        synthesizedBranch(result.highPass, title: "Tweeter high-pass")
                    }
                    Chart {
                        ForEach(result.response, id: \.frequencyHz) { point in
                            LineMark(
                                x: .value("Frequency", point.frequencyHz),
                                y: .value("Magnitude", 20 * log10(max(point.lowPassMagnitude, 1e-9))),
                                series: .value("Curve", "Low-pass optimized")
                            )
                            .foregroundStyle(.blue)
                            LineMark(
                                x: .value("Frequency", point.frequencyHz),
                                y: .value("Magnitude", 20 * log10(max(point.highPassMagnitude, 1e-9))),
                                series: .value("Curve", "High-pass optimized")
                            )
                            .foregroundStyle(.orange)
                        }
                    }
                    .chartXScale(type: .log)
                    .chartXAxisLabel("Frequency (Hz)")
                    .chartYAxisLabel("Electrical transfer (dB)")
                    .frame(height: 210)
                    Divider()
                    Text("Robust design").font(.subheadline.weight(.semibold))
                    LazyVGrid(
                        columns: [GridItem(.adaptive(minimum: 190), alignment: .leading)],
                        alignment: .leading, spacing: 10
                    ) {
                        numericSetting(
                            "Component tolerance", unit: "%",
                            value: $document.robustComponentTolerancePercent
                        )
                        numericSetting(
                            "Load magnitude variation", unit: "%",
                            value: $document.robustLoadTolerancePercent
                        )
                        numericSetting(
                            "Load phase variation", unit: "°",
                            value: $document.robustLoadPhaseToleranceDegrees
                        )
                        numericSetting(
                            "Allowed response error", unit: "dB",
                            value: $document.robustAllowedErrorDecibels
                        )
                        Stepper(
                            "Samples: \(document.robustSampleCount)",
                            value: $document.robustSampleCount, in: 20...2_000, step: 20
                        )
                    }
                    Button {
                        document.analyzeRobustness()
                    } label: {
                        if document.isAnalyzingRobustness {
                            ProgressView().controlSize(.small)
                        } else {
                            Label("Analyze and robustify", systemImage: "shield.lefthalf.filled")
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(document.isAnalyzingRobustness)
                    if let error = document.robustDesignError {
                        Label(error, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                    }
                    if let robust = document.robustDesignResult {
                        HStack(spacing: 18) {
                            Text("Yield: \(robust.yieldPercent.formatted(.number.precision(.fractionLength(1))))%")
                            Text("Worst error: \(robust.worstCaseMagnitudeErrorDecibels.formatted(.number.precision(.fractionLength(2)))) dB")
                            Text("Worst input: \(robust.worstCaseMinimumImpedanceOhms.formatted(.number.precision(.fractionLength(2)))) Ω")
                            Text("\(robust.changedComponentCount) E24 changes")
                        }
                        .font(.caption.monospacedDigit())
                        Chart {
                            ForEach(robust.envelope, id: \.frequencyHz) { point in
                                AreaMark(
                                    x: .value("Frequency", point.frequencyHz),
                                    yStart: .value("Low 5%", point.lowPassP05Decibels),
                                    yEnd: .value("Low 95%", point.lowPassP95Decibels)
                                )
                                .foregroundStyle(.blue.opacity(0.18))
                                AreaMark(
                                    x: .value("Frequency", point.frequencyHz),
                                    yStart: .value("High 5%", point.highPassP05Decibels),
                                    yEnd: .value("High 95%", point.highPassP95Decibels)
                                )
                                .foregroundStyle(.orange.opacity(0.18))
                                LineMark(
                                    x: .value("Frequency", point.frequencyHz),
                                    y: .value("Low median", point.lowPassMedianDecibels),
                                    series: .value("Median", "Low-pass")
                                )
                                .foregroundStyle(.blue)
                                LineMark(
                                    x: .value("Frequency", point.frequencyHz),
                                    y: .value("High median", point.highPassMedianDecibels),
                                    series: .value("Median", "High-pass")
                                )
                                .foregroundStyle(.orange)
                            }
                        }
                        .chartXScale(type: .log)
                        .chartXAxisLabel("Frequency (Hz)")
                        .chartYAxisLabel("Tolerance envelope (dB)")
                        .frame(height: 210)
                        if let mostSensitive = robust.sensitivities.first {
                            Text("Most sensitive: \(mostSensitive.componentID), \(mostSensitive.worstCaseMagnitudeShiftDecibels.formatted(.number.precision(.fractionLength(2)))) dB span at ±\(document.robustComponentTolerancePercent.formatted(.number.precision(.fractionLength(1))))%")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        if robust.changedComponentCount > 0 {
                            LazyVGrid(
                                columns: [GridItem(.adaptive(minimum: 260), alignment: .leading)],
                                alignment: .leading, spacing: 8
                            ) {
                                synthesizedBranch(
                                    robust.recommendedDesign.lowPass,
                                    title: "Robust woofer values"
                                )
                                synthesizedBranch(
                                    robust.recommendedDesign.highPass,
                                    title: "Robust tweeter values"
                                )
                            }
                        }
                    }
                    Button(
                        document.robustDesignResult == nil
                            ? "Apply synthesized schematic" : "Apply robust synthesized schematic",
                        systemImage: "point.3.connected.trianglepath.dotted"
                    ) {
                        isApplySynthesisConfirmationPresented = true
                    }
                    .buttonStyle(.bordered)
                }
            }
        } label: {
            Label("Crossover synthesis", systemImage: "function")
                .font(.headline)
        }
    }

    private var spatialSettings: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                Text("Driver offsets are relative to the cabinet acoustic center. Positive depth moves a driver toward the listener; horizontal polar data uses a circular-piston directivity model.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 190), alignment: .leading)],
                    alignment: .leading, spacing: 12
                ) {
                    numericSetting("Listening distance", unit: "m", value: $document.listeningDistanceMeters)
                    numericSetting("Listening angle", unit: "°", value: $document.listeningAngleDegrees)
                    numericSetting("Listener height", unit: "m", value: $document.listenerHeightMeters)
                    numericSetting("Acoustic-center height", unit: "m", value: $document.acousticCenterHeightMeters)
                    numericSetting("Floor reflection", unit: "−1…1", value: $document.floorReflectionCoefficient)
                    numericSetting("Air loss at 10 kHz", unit: "dB/m", value: $document.airAbsorptionDbPerMeterAt10kHz)
                }
                Divider()
                Text("Driver acoustic centers").font(.subheadline.weight(.semibold))
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 190), alignment: .leading)],
                    alignment: .leading, spacing: 12
                ) {
                    numericSetting("Woofer horizontal", unit: "m", value: $document.wooferXOffsetMeters)
                    numericSetting("Woofer vertical", unit: "m", value: $document.wooferYOffsetMeters)
                    numericSetting("Woofer depth", unit: "m", value: $document.wooferZOffsetMeters)
                    numericSetting("Tweeter horizontal", unit: "m", value: $document.tweeterXOffsetMeters)
                    numericSetting("Tweeter vertical", unit: "m", value: $document.tweeterYOffsetMeters)
                    numericSetting("Tweeter depth", unit: "m", value: $document.tweeterZOffsetMeters)
                }
            }
        } label: {
            Label("Spatial acoustics", systemImage: "dot.radiowaves.left.and.right")
                .font(.headline)
        }
    }

    private func synthesizedBranch(_ branch: SynthesizedBranch, title: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.subheadline.weight(.semibold))
            ForEach(branch.components) { component in
                Text("\(componentLabel(component.kind)): \(componentValue(component))")
                    .font(.caption.monospacedDigit())
            }
        }
    }

    private func componentLabel(_ kind: SynthesizedComponentKind) -> String {
        switch kind {
        case .seriesInductor: "Series L"
        case .shuntCapacitor: "Shunt C"
        case .seriesCapacitor: "Series C"
        case .shuntInductor: "Shunt L"
        }
    }

    private func componentValue(_ component: SynthesizedComponent) -> String {
        if component.kind.isInductor {
            return "\((component.value * 1_000).formatted(.number.precision(.significantDigits(4)))) mH"
        }
        return "\((component.value * 1_000_000).formatted(.number.precision(.significantDigits(4)))) µF"
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

    @ViewBuilder
    private var spatialAcousticsPlots: some View {
        if let spatial = document.spatialAcousticsResult {
            GroupBox("Directivity and spatial response") {
                VStack(alignment: .leading, spacing: 14) {
                    Text("Listening-window and sound-power curves are spatial averages. The directivity index is their level difference; polar curves are normalized to the on-axis response at each frequency.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Chart {
                        ForEach(Array(spatial.listeningWindowResponse.enumerated()), id: \.offset) { index, point in
                            LineMark(
                                x: .value("Frequency", point.frequencyHz),
                                y: .value("Level", point.soundPressureLevelDecibels),
                                series: .value("Curve", "Listening window")
                            ).foregroundStyle(.blue)
                            LineMark(
                                x: .value("Frequency", spatial.soundPowerResponse[index].frequencyHz),
                                y: .value("Level", spatial.soundPowerResponse[index].soundPressureLevelDecibels),
                                series: .value("Curve", "Sound power")
                            ).foregroundStyle(.purple)
                        }
                    }
                    .chartXScale(type: .log)
                    .chartXAxisLabel("Frequency (Hz)")
                    .chartYAxisLabel("SPL (dB)")
                    .frame(height: 220)
                    Chart(spatial.polarResponse) { point in
                        LineMark(
                            x: .value("Angle", point.angleDegrees),
                            y: .value("Relative level", point.relativeLevelDecibels),
                            series: .value("Frequency", point.frequencyHz)
                        )
                    }
                    .chartXAxisLabel("Horizontal angle (°)")
                    .chartYAxisLabel("Relative level (dB)")
                    .chartYScale(domain: -30...3)
                    .frame(height: 240)
                    Chart {
                        ForEach(Array(spatial.listeningResponse.enumerated()), id: \.offset) { index, point in
                            LineMark(
                                x: .value("Frequency", point.frequencyHz),
                                y: .value("DI", spatial.directivityIndexDecibels[index])
                            )
                        }
                    }
                    .chartXScale(type: .log)
                    .chartXAxisLabel("Frequency (Hz)")
                    .chartYAxisLabel("Directivity index (dB)")
                    .frame(height: 180)
                }
            }
        }
    }

    @ViewBuilder
    private var operatingLimitsPlot: some View {
        if let result = document.systemSimulationResult {
            let excursionPoints = result.drivers.enumerated().flatMap { driverIndex, trace in
                zip(result.frequenciesHz, trace.excursionMillimeters ?? []).map {
                    EnclosureLimitPoint(
                        frequencyHz: $0.0, value: $0.1,
                        series: driverIndex == 0 ? "Woofer" : "Tweeter"
                    )
                }
            }
            let ventPoints = result.drivers.enumerated().flatMap { driverIndex, trace in
                zip(result.frequenciesHz, trace.portAirVelocityMetersPerSecond ?? []).map {
                    EnclosureLimitPoint(
                        frequencyHz: $0.0, value: $0.1,
                        series: driverIndex == 0 ? "Woofer vent" : "Tweeter vent"
                    )
                }
            }
            GroupBox("Enclosure operating limits") {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Small-signal cone peak displacement and vent air speed at the solved terminal voltage. Compare excursion against each driver's Xmax; vent speeds above Mach 0.10 are flagged.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Chart(excursionPoints) { point in
                        LineMark(
                            x: .value("Frequency (Hz)", point.frequencyHz),
                            y: .value("Excursion (mm)", point.value),
                            series: .value("Driver", point.series)
                        )
                    }
                    .chartXScale(type: .log)
                    .chartXAxisLabel("Frequency (Hz)")
                    .chartYAxisLabel("Peak excursion (mm)")
                    .frame(height: 220)
                    if !ventPoints.isEmpty {
                        Chart {
                            ForEach(ventPoints) { point in
                                LineMark(
                                    x: .value("Frequency (Hz)", point.frequencyHz),
                                    y: .value("Air speed (m/s)", point.value),
                                    series: .value("Vent", point.series)
                                )
                            }
                            RuleMark(y: .value("Mach 0.10", 34.3))
                                .foregroundStyle(.red.opacity(0.7))
                                .lineStyle(StrokeStyle(dash: [5, 4]))
                        }
                        .chartXScale(type: .log)
                        .chartXAxisLabel("Frequency (Hz)")
                        .chartYAxisLabel("Vent air speed (m/s)")
                        .frame(height: 180)
                    }
                }
            }
        }
    }

    private var largeSignalPanel: some View {
        GroupBox("Large-signal and multiphysics") {
            VStack(alignment: .leading, spacing: 12) {
                Text("Sweep input level from the 2.83 V NumericCore operating point. The model iterates voice-coil temperature and resistance, then estimates motor/compliance nonlinearity, excursion, distortion, and vent compression.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 190), alignment: .leading)],
                    alignment: .leading, spacing: 10
                ) {
                    numericSetting("Maximum input", unit: "V RMS", value: $document.largeSignalMaximumVoltageRMS)
                    Stepper("Sweep points: \(document.largeSignalSteps)", value: $document.largeSignalSteps, in: 2...16)
                    numericSetting("Stimulus duration", unit: "s", value: $document.largeSignalDurationSeconds)
                    numericSetting("Coil thermal resistance", unit: "K/W", value: $document.thermalResistanceKelvinPerWatt)
                    numericSetting("Thermal time constant", unit: "s", value: $document.thermalTimeConstantSeconds)
                    numericSetting("Maximum coil temperature", unit: "°C", value: $document.maximumCoilTemperatureCelsius)
                }
                Button {
                    document.analyzeLargeSignal()
                } label: {
                    if document.isAnalyzingLargeSignal {
                        ProgressView().controlSize(.small)
                    } else {
                        Label("Run large-signal sweep", systemImage: "thermometer.high")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(document.isAnalyzingLargeSignal || document.systemSimulationResult == nil)
                if let error = document.largeSignalError {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                }
                if let result = document.largeSignalResult {
                    HStack(spacing: 18) {
                        Text("Safe input: \(result.maximumSafeInputVoltageRMS.formatted(.number.precision(.fractionLength(2)))) V")
                        Text("Safe nominal power: \(result.maximumSafeNominalPowerWatts.formatted(.number.precision(.fractionLength(1)))) W")
                        Text("First limit: \(result.firstLimitingMechanism.rawValue)")
                    }
                    .font(.caption.monospacedDigit())
                    Chart(result.operatingPoints) { point in
                        LineMark(
                            x: .value("Input", point.inputVoltageRMS),
                            y: .value("Compression", point.maximumCompressionDecibels)
                        )
                        PointMark(
                            x: .value("Input", point.inputVoltageRMS),
                            y: .value("Compression", point.maximumCompressionDecibels)
                        )
                        .foregroundStyle(point.limitingMechanism == .none ? .blue : .red)
                    }
                    .chartXAxisLabel("Input voltage (V RMS)")
                    .chartYAxisLabel("Maximum compression (dB)")
                    .frame(height: 210)
                    Chart {
                        ForEach(result.operatingPoints) { point in
                            ForEach(Array(point.drivers.enumerated()), id: \.offset) { index, driver in
                                LineMark(
                                    x: .value("Input", point.inputVoltageRMS),
                                    y: .value("Temperature", driver.coilTemperatureCelsius),
                                    series: .value("Driver", index == 0 ? "Woofer" : "Tweeter")
                                )
                            }
                        }
                        RuleMark(y: .value("Limit", document.maximumCoilTemperatureCelsius))
                            .foregroundStyle(.red.opacity(0.7))
                            .lineStyle(StrokeStyle(dash: [5, 4]))
                    }
                    .chartXAxisLabel("Input voltage (V RMS)")
                    .chartYAxisLabel("Voice-coil temperature (°C)")
                    .frame(height: 210)
                    if let highest = result.operatingPoints.last {
                        let frequencyPoints = highest.drivers.enumerated().flatMap { driverIndex, driver in
                            driver.response.map {
                                LargeSignalChartPoint(
                                    frequencyHz: $0.frequencyHz,
                                    value: $0.estimatedTHDPercent,
                                    series: driverIndex == 0 ? "Woofer" : "Tweeter"
                                )
                            }
                        }
                        Chart(frequencyPoints) { point in
                            LineMark(
                                x: .value("Frequency", point.frequencyHz),
                                y: .value("THD", point.value),
                                series: .value("Driver", point.series)
                            )
                        }
                        .chartXScale(type: .log)
                        .chartXAxisLabel("Frequency (Hz) at \(highest.inputVoltageRMS.formatted(.number.precision(.fractionLength(1)))) V")
                        .chartYAxisLabel("Estimated THD (%)")
                        .frame(height: 210)
                    }
                }
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

private struct EnclosureLimitPoint: Identifiable {
    let id = UUID()
    let frequencyHz: Double
    let value: Double
    let series: String
}

private struct LargeSignalChartPoint: Identifiable {
    let id = UUID()
    let frequencyHz: Double
    let value: Double
    let series: String
}
