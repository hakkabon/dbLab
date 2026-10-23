import Foundation
import DBLabDomain
import DBLabNumeric
import DBLabEnclosure
import DBLabAcoustics

struct CrossoverSimulationResult: Sendable {
    var response: [AcousticResponsePoint]
    var warnings: [String]
    var trace: [CrossoverTracePoint]
    var solverDiagnostics: [ACSolverDiagnostics]
    var spatialAcoustics: SpatialAcousticsResult?

    func domainResult(system: LoudspeakerSystem?) -> SystemSimulationResult? {
        guard let system, system.drivers.count >= 2 else { return nil }
        let woofer = system.drivers.first(where: { $0.role == .woofer }) ?? system.drivers[0]
        let tweeter = system.drivers.first(where: { $0.role == .tweeter }) ?? system.drivers[1]
        func sample(_ frequency: Double, _ value: ComplexValue) -> ComplexTraceSample {
            ComplexTraceSample(frequencyHz: frequency, real: value.real, imaginary: value.imaginary)
        }
        let wooferTrace = DriverSimulationTrace(
            driverInstanceID: woofer.id,
            terminalVoltage: trace.map { sample($0.frequencyHz, $0.wooferVoltage) },
            current: trace.map { sample($0.frequencyHz, $0.wooferCurrent) },
            acousticPressure: trace.map { sample($0.frequencyHz, $0.wooferAcoustic) },
            excursionMillimeters: trace.map(\.wooferExcursionMillimeters),
            portAirVelocityMetersPerSecond: trace.compactMap(\.wooferPortVelocity).isEmpty
                ? nil : trace.compactMap(\.wooferPortVelocity)
        )
        let tweeterTrace = DriverSimulationTrace(
            driverInstanceID: tweeter.id,
            terminalVoltage: trace.map { sample($0.frequencyHz, $0.tweeterVoltage) },
            current: trace.map { sample($0.frequencyHz, $0.tweeterCurrent) },
            acousticPressure: trace.map { sample($0.frequencyHz, $0.tweeterAcoustic) },
            excursionMillimeters: trace.map(\.tweeterExcursionMillimeters),
            portAirVelocityMetersPerSecond: trace.compactMap(\.tweeterPortVelocity).isEmpty
                ? nil : trace.compactMap(\.tweeterPortVelocity)
        )
        let positionedPressure = spatialAcoustics?.listeningResponse.map {
            ComplexTraceSample(
                frequencyHz: $0.frequencyHz,
                real: $0.pressure.real / 20e-6,
                imaginary: $0.pressure.imaginary / 20e-6
            )
        }
        return SystemSimulationResult(
            frequenciesHz: trace.map(\.frequencyHz),
            inputImpedance: trace.map { sample($0.frequencyHz, $0.inputImpedance) },
            combinedAcousticPressure: positionedPressure ?? trace.map {
                sample($0.frequencyHz, $0.wooferAcoustic + $0.tweeterAcoustic)
            },
            drivers: [wooferTrace, tweeterTrace],
            diagnostics: SimulationDiagnostics(
                warnings: warnings,
                relativeResiduals: solverDiagnostics.map(\.relativeResidual),
                backendIdentifier: solverDiagnostics.first?.backendIdentifier ?? "numeric-core-sparse-lu"
            )
        )
    }
}

struct CrossoverTracePoint: Sendable {
    let frequencyHz: Double
    let inputImpedance: ComplexValue
    let wooferVoltage: ComplexValue
    let tweeterVoltage: ComplexValue
    let wooferCurrent: ComplexValue
    let tweeterCurrent: ComplexValue
    let wooferAcoustic: ComplexValue
    let tweeterAcoustic: ComplexValue
    let wooferExcursionMillimeters: Double
    let tweeterExcursionMillimeters: Double
    let wooferPortVelocity: Double?
    let tweeterPortVelocity: Double?
}

enum CrossoverNetworkSimulationError: LocalizedError {
    case missingGround
    case missingNode(String)
    case invalidNodeAssignment
    case missingComponent(String)
    case missingPin(String)
    case invalidParameter(String)
    case unsupportedComponent(String)
    case missingMeasurement(driver: String, kind: DriverMeasurementKind)
    case noFrequencyOverlap
    case singularNetwork(frequencyHz: Double)

    var errorDescription: String? {
        switch self {
        case .missingGround:
            "Connect a ground symbol to the crossover's common return before simulating."
        case .missingNode(let role):
            "Assign a schematic net to the \(role)."
        case .invalidNodeAssignment:
            "The input and driver output nodes must be distinct from ground; the woofer and tweeter outputs must also be distinct."
        case .missingComponent(let reference):
            "\(reference) does not have a supported component definition."
        case .missingPin(let reference):
            "\(reference) has an unconnected schematic pin."
        case .invalidParameter(let reference):
            "\(reference) has a missing, non-finite, or non-positive component value."
        case .unsupportedComponent(let reference):
            "\(reference) is not supported by the passive crossover solver."
        case .missingMeasurement(let driver, let kind):
            "\(driver) needs an imported \(kind.title.lowercased()) dataset for this simulation."
        case .noFrequencyOverlap:
            "The selected driver measurements have no common usable frequency range."
        case .singularNetwork(let frequency):
            "The passive network is floating or singular near \(frequency.formatted(.number.precision(.fractionLength(1)))) Hz. Check wiring, net assignments, and component connections."
        }
    }
}

enum CrossoverNetworkSimulator {
    private static let referenceVoltage = 2.83
    private static let pointsPerOctave = 24

    static func synthesisLoadSamples(
        branch: AcousticBranchSettings,
        impedanceMeasurement: DriverMeasurement?,
        crossoverFrequencyHz: Double,
        pointsPerOctave: Int = 8
    ) throws -> [ACImpedanceSample] {
        try validateAcousticBranch(branch, validateEnclosure: true)
        try validateMeasurement(impedanceMeasurement, kind: .impedance, driver: branch.driver)
        let lower = crossoverFrequencyHz / 4
        let upper = crossoverFrequencyHz * 4
        guard lower.isFinite, lower > 0, upper.isFinite,
              impedanceMeasurement == nil || (
                impedanceMeasurement!.points.first!.frequencyHz <= lower
                    && impedanceMeasurement!.points.last!.frequencyHz >= upper
              ) else {
            throw CrossoverNetworkSimulationError.noFrequencyOverlap
        }
        let model = try AcousticSimulator.enclosureModel(for: branch)
        return logFrequencies(start: lower, stop: upper, pointsPerOctave: pointsPerOctave).map {
            ACImpedanceSample(
                frequencyHz: $0,
                impedance: loadImpedance(
                    measurement: impedanceMeasurement, enclosureModel: model, frequencyHz: $0
                ).acComplex
            )
        }
    }

    @MainActor
    static func simulate(
        schematic: SchematicDocument,
        inputNetID: Int?,
        wooferOutputNetID: Int?,
        tweeterOutputNetID: Int?,
        woofer: AcousticBranchSettings,
        tweeter: AcousticBranchSettings,
        wooferFrequencyResponse: DriverMeasurement?,
        tweeterFrequencyResponse: DriverMeasurement?,
        wooferImpedance: DriverMeasurement?,
        tweeterImpedance: DriverMeasurement?,
        wooferPosition: AcousticPosition = .init(yMeters: -0.12),
        tweeterPosition: AcousticPosition = .init(yMeters: 0.12),
        spatialOptions: SpatialAcousticsOptions? = nil
    ) throws -> CrossoverSimulationResult {
        try simulate(
            symbols: schematic.symbols,
            wires: schematic.wires,
            inputNetID: inputNetID,
            wooferOutputNetID: wooferOutputNetID,
            tweeterOutputNetID: tweeterOutputNetID,
            woofer: woofer,
            tweeter: tweeter,
            wooferFrequencyResponse: wooferFrequencyResponse,
            tweeterFrequencyResponse: tweeterFrequencyResponse,
            wooferImpedance: wooferImpedance,
            tweeterImpedance: tweeterImpedance,
            wooferPosition: wooferPosition,
            tweeterPosition: tweeterPosition,
            spatialOptions: spatialOptions
        )
    }

    static func simulate(
        symbols: [SymbolInstance],
        wires: [WireSegment],
        inputNetID: Int?,
        wooferOutputNetID: Int?,
        tweeterOutputNetID: Int?,
        woofer: AcousticBranchSettings,
        tweeter: AcousticBranchSettings,
        wooferFrequencyResponse: DriverMeasurement?,
        tweeterFrequencyResponse: DriverMeasurement?,
        wooferImpedance: DriverMeasurement?,
        tweeterImpedance: DriverMeasurement?,
        wooferPosition: AcousticPosition = .init(yMeters: -0.12),
        tweeterPosition: AcousticPosition = .init(yMeters: 0.12),
        spatialOptions: SpatialAcousticsOptions? = nil
    ) throws -> CrossoverSimulationResult {
        guard let inputNetID else { throw CrossoverNetworkSimulationError.missingNode("input") }
        guard let wooferOutputNetID else { throw CrossoverNetworkSimulationError.missingNode("woofer output") }
        guard let tweeterOutputNetID else { throw CrossoverNetworkSimulationError.missingNode("tweeter output") }

        let nets = ConnectivityBuilder.build(symbols: symbols, wires: wires)
        guard let groundNet = nets.first(where: \.isGround) else {
            throw CrossoverNetworkSimulationError.missingGround
        }
        let groundNetIDs = Set(nets.filter(\.isGround).map(\.id))
        let validNodeIDs = Set(nets.map(\.id))
        guard validNodeIDs.contains(inputNetID),
              validNodeIDs.contains(wooferOutputNetID),
              validNodeIDs.contains(tweeterOutputNetID),
              !groundNetIDs.contains(inputNetID),
              !groundNetIDs.contains(wooferOutputNetID),
              !groundNetIDs.contains(tweeterOutputNetID),
              inputNetID != wooferOutputNetID,
              inputNetID != tweeterOutputNetID,
              wooferOutputNetID != tweeterOutputNetID else {
            throw CrossoverNetworkSimulationError.invalidNodeAssignment
        }

        try validateAcousticBranch(woofer, validateEnclosure: wooferFrequencyResponse == nil)
        try validateAcousticBranch(tweeter, validateEnclosure: tweeterFrequencyResponse == nil)
        try validateMeasurement(wooferFrequencyResponse, kind: .frequencyResponse, driver: woofer.driver)
        try validateMeasurement(tweeterFrequencyResponse, kind: .frequencyResponse, driver: tweeter.driver)
        try validateMeasurement(wooferImpedance, kind: .impedance, driver: woofer.driver)
        try validateMeasurement(tweeterImpedance, kind: .impedance, driver: tweeter.driver)

        let components = try componentBranches(symbols: symbols, nets: nets)
        let bounds = frequencyBounds(
            wooferFrequencyResponse: wooferFrequencyResponse,
            tweeterFrequencyResponse: tweeterFrequencyResponse,
            wooferImpedance: wooferImpedance,
            tweeterImpedance: tweeterImpedance
        )
        guard bounds.lowerBound < bounds.upperBound else {
            throw CrossoverNetworkSimulationError.noFrequencyOverlap
        }
        let frequencies = logFrequencies(
            start: bounds.lowerBound,
            stop: bounds.upperBound,
            pointsPerOctave: pointsPerOctave
        )
        let wooferEnclosureModel: EnclosureModel
        let tweeterEnclosureModel: EnclosureModel
        do {
            wooferEnclosureModel = try AcousticSimulator.enclosureModel(for: woofer)
            tweeterEnclosureModel = try AcousticSimulator.enclosureModel(for: tweeter)
        } catch {
            throw CrossoverNetworkSimulationError.invalidParameter("Enclosure model")
        }
        var elements = components.map { component in
            ACTwoTerminalElement(
                id: component.id,
                firstNode: groundNetIDs.contains(component.firstNodeID) ? groundNet.id : component.firstNodeID,
                secondNode: groundNetIDs.contains(component.secondNodeID) ? groundNet.id : component.secondNodeID,
                impedance: component.model
            )
        }
        elements.append(ACTwoTerminalElement(
            id: "woofer-load", firstNode: wooferOutputNetID, secondNode: groundNet.id,
            impedance: .tabulated(frequencies.map {
                ACImpedanceSample(
                    frequencyHz: $0,
                    impedance: loadImpedance(
                        measurement: wooferImpedance, enclosureModel: wooferEnclosureModel, frequencyHz: $0
                    ).acComplex
                )
            })
        ))
        elements.append(ACTwoTerminalElement(
            id: "tweeter-load", firstNode: tweeterOutputNetID, secondNode: groundNet.id,
            impedance: .tabulated(frequencies.map {
                ACImpedanceSample(
                    frequencyHz: $0,
                    impedance: loadImpedance(
                        measurement: tweeterImpedance, enclosureModel: tweeterEnclosureModel, frequencyHz: $0
                    ).acComplex
                )
            })
        ))
        let prepared = try PreparedACNetwork(ACNetwork(
            referenceNode: groundNet.id,
            sourceNode: inputNetID,
            sourceVoltage: ACComplex(real: referenceVoltage),
            elements: elements
        ))
        let solutions: [ACSolutionPoint]
        do {
            solutions = try prepared.solve(frequenciesHz: frequencies)
        } catch ACAnalysisError.singularNetwork(let frequency) {
            throw CrossoverNetworkSimulationError.singularNetwork(frequencyHz: frequency)
        }
        var points: [AcousticResponsePoint] = []
        var trace: [CrossoverTracePoint] = []

        for (frequency, solution) in zip(frequencies, solutions) {
            let voltages = solution.nodeVoltages.mapValues(ComplexValue.init)
            guard let wooferVoltage = voltages[wooferOutputNetID],
                  let tweeterVoltage = voltages[tweeterOutputNetID] else {
                throw CrossoverNetworkSimulationError.invalidNodeAssignment
            }

            let wooferAcoustic = acousticResponse(
                branch: woofer,
                measurement: wooferFrequencyResponse,
                frequencyHz: frequency
            ) * (wooferVoltage / ComplexValue(real: referenceVoltage, imaginary: 0))
            let tweeterAcoustic = acousticResponse(
                branch: tweeter,
                measurement: tweeterFrequencyResponse,
                frequencyHz: frequency
            ) * (tweeterVoltage / ComplexValue(real: referenceVoltage, imaginary: 0))
            let wooferLoad = loadImpedance(
                measurement: wooferImpedance, enclosureModel: wooferEnclosureModel, frequencyHz: frequency
            )
            let tweeterLoad = loadImpedance(
                measurement: tweeterImpedance, enclosureModel: tweeterEnclosureModel, frequencyHz: frequency
            )
            let wooferEnclosureResponse = try wooferEnclosureModel.response(at: frequency)
            let tweeterEnclosureResponse = try tweeterEnclosureModel.response(at: frequency)
            let wooferVoltageAC = wooferVoltage.acComplex
            let tweeterVoltageAC = tweeterVoltage.acComplex
            trace.append(CrossoverTracePoint(
                frequencyHz: frequency,
                inputImpedance: ComplexValue(solution.inputImpedance),
                wooferVoltage: wooferVoltage,
                tweeterVoltage: tweeterVoltage,
                wooferCurrent: wooferVoltage / wooferLoad,
                tweeterCurrent: tweeterVoltage / tweeterLoad,
                wooferAcoustic: wooferAcoustic,
                tweeterAcoustic: tweeterAcoustic,
                wooferExcursionMillimeters: (wooferEnclosureResponse.coneDisplacementMetersPerVolt * wooferVoltageAC).magnitude * sqrt(2) * 1_000,
                tweeterExcursionMillimeters: (tweeterEnclosureResponse.coneDisplacementMetersPerVolt * tweeterVoltageAC).magnitude * sqrt(2) * 1_000,
                wooferPortVelocity: wooferEnclosureResponse.portAirVelocityMetersPerSecondPerVolt.map { ($0 * wooferVoltageAC).magnitude * sqrt(2) },
                tweeterPortVelocity: tweeterEnclosureResponse.portAirVelocityMetersPerSecondPerVolt.map { ($0 * tweeterVoltageAC).magnitude * sqrt(2) }
            ))
            points.append(AcousticResponsePoint(
                frequencyHz: frequency,
                wooferDb: decibels(wooferAcoustic.magnitude),
                tweeterDb: decibels(tweeterAcoustic.magnitude),
                totalDb: decibels((wooferAcoustic + tweeterAcoustic).magnitude)
            ))
        }

        guard points.allSatisfy({
            $0.frequencyHz.isFinite && $0.wooferDb.isFinite
                && $0.tweeterDb.isFinite && $0.totalDb.isFinite
        }) else {
            throw CrossoverNetworkSimulationError.noFrequencyOverlap
        }

        var warnings: [String] = []
        if wooferFrequencyResponse == nil || tweeterFrequencyResponse == nil {
            warnings.append("A driver has no selected measured response; its enclosure model estimates acoustic output.")
        }
        if wooferImpedance == nil || tweeterImpedance == nil {
            warnings.append("A driver has no selected measured impedance; its Thiele/Small enclosure model supplies the complex electrical load.")
        }
        if wooferImpedance?.hasPhaseData == false || tweeterImpedance?.hasPhaseData == false {
            warnings.append("A selected impedance dataset lacks phase; that driver's load is treated as purely resistive between samples.")
        }
        if wooferFrequencyResponse?.hasPhaseData == false || tweeterFrequencyResponse?.hasPhaseData == false {
            warnings.append("A selected response dataset lacks phase; acoustic summation uses zero phase for that driver.")
        }
        if trace.contains(where: { $0.wooferExcursionMillimeters > woofer.driver.xmaxMillimeters }) {
            warnings.append("Woofer excursion exceeds its linear Xmax at one or more simulated frequencies.")
        }
        if trace.contains(where: { $0.tweeterExcursionMillimeters > tweeter.driver.xmaxMillimeters }) {
            warnings.append("Tweeter excursion exceeds its linear Xmax at one or more simulated frequencies.")
        }
        let portWarningThreshold = 0.1 * 343.0
        if trace.contains(where: { ($0.wooferPortVelocity ?? 0) > portWarningThreshold }) {
            warnings.append("Woofer vent air speed exceeds Mach 0.10; increase vent area or reconsider tuning.")
        }
        if trace.contains(where: { ($0.tweeterPortVelocity ?? 0) > portWarningThreshold }) {
            warnings.append("Tweeter vent air speed exceeds Mach 0.10; increase vent area or reconsider tuning.")
        }
        let spatial = try spatialOptions.map { options in
            try SpatialAcousticsSimulator.simulate(
                sources: [
                    SpatialSource(
                        id: "woofer", position: wooferPosition,
                        radiatingDiameterMeters: 2 * sqrt(woofer.driver.sdSquareCentimeters / 10_000 / .pi),
                        pressureAtOneMeter: trace.map {
                            .init(frequencyHz: $0.frequencyHz, real: $0.wooferAcoustic.real * 20e-6, imaginary: $0.wooferAcoustic.imaginary * 20e-6)
                        }
                    ),
                    SpatialSource(
                        id: "tweeter", position: tweeterPosition,
                        radiatingDiameterMeters: 2 * sqrt(tweeter.driver.sdSquareCentimeters / 10_000 / .pi),
                        pressureAtOneMeter: trace.map {
                            .init(frequencyHz: $0.frequencyHz, real: $0.tweeterAcoustic.real * 20e-6, imaginary: $0.tweeterAcoustic.imaginary * 20e-6)
                        }
                    )
                ],
                options: options
            )
        }
        if let spatial {
            points = zip(points, spatial.listeningResponse).map { original, positioned in
                AcousticResponsePoint(
                    frequencyHz: original.frequencyHz, wooferDb: original.wooferDb,
                    tweeterDb: original.tweeterDb, totalDb: positioned.soundPressureLevelDecibels
                )
            }
        }
        return CrossoverSimulationResult(
            response: points, warnings: warnings, trace: trace,
            solverDiagnostics: solutions.map(\.diagnostics), spatialAcoustics: spatial
        )
    }

    private static func validateMeasurement(
        _ measurement: DriverMeasurement?,
        kind: DriverMeasurementKind,
        driver: SpeakerDriver
    ) throws {
        guard let measurement else { return }
        guard measurement.kind == kind, measurement.validationMessage == nil else {
            throw CrossoverNetworkSimulationError.missingMeasurement(driver: driver.displayName, kind: kind)
        }
    }

    private static func validateAcousticBranch(
        _ branch: AcousticBranchSettings,
        validateEnclosure: Bool
    ) throws {
        guard branch.driver.validationMessage == nil else {
            throw CrossoverNetworkSimulationError.invalidParameter(branch.driver.displayName)
        }
        guard validateEnclosure else { return }
        switch branch.enclosure {
        case .openBaffle:
            guard branch.baffleWidthMeters.isFinite, branch.baffleWidthMeters > 0 else {
                throw CrossoverNetworkSimulationError.invalidParameter("Open-baffle width")
            }
        case .closedBox:
            guard branch.boxVolumeLiters.isFinite, branch.boxVolumeLiters > 0 else {
                throw CrossoverNetworkSimulationError.invalidParameter("Closed-box volume")
            }
        case .portedBox:
            guard PortedBoxDesign.portLengthCentimeters(
                volumeLiters: branch.boxVolumeLiters,
                tuningHz: branch.portTuningHz,
                diameterCentimeters: branch.portDiameterCentimeters
            ) != nil else {
                throw CrossoverNetworkSimulationError.invalidParameter("Ported-box dimensions")
            }
        }
    }

    private static func componentBranches(
        symbols: [SymbolInstance],
        nets: [Net]
    ) throws -> [PassiveComponentBranch] {
        let nodeByPin = Dictionary(
            uniqueKeysWithValues: nets.flatMap { net in
                net.connectedPins.map { ($0, net.id) }
            }
        )
        var branches: [PassiveComponentBranch] = []

        for symbol in symbols {
            guard let descriptor = ComponentRegistry.shared.descriptor(for: symbol.descriptorId) else {
                throw CrossoverNetworkSimulationError.missingComponent(symbol.refDes)
            }
            if descriptor.symbol == .ground { continue }
            guard descriptor.symbol == .resistor || descriptor.symbol == .capacitor
                    || descriptor.symbol == .inductor || descriptor.symbol == .inductorSeries else {
                throw CrossoverNetworkSimulationError.unsupportedComponent(symbol.refDes)
            }
            guard descriptor.pins.count == 2,
                  let first = descriptor.pins.first,
                  let second = descriptor.pins.last,
                  let firstNode = nodeByPin[PinRef(symbolId: symbol.id, pinId: first.id)],
                  let secondNode = nodeByPin[PinRef(symbolId: symbol.id, pinId: second.id)] else {
                throw CrossoverNetworkSimulationError.missingPin(symbol.refDes)
            }

            let value: Double
            switch descriptor.symbol {
            case .resistor:
                value = try positiveParameter("resistance", in: symbol)
                branches.append(PassiveComponentBranch(
                    id: symbol.refDes,
                    firstNodeID: firstNode,
                    secondNodeID: secondNode,
                    type: .resistor,
                    value: value,
                    seriesResistance: 0
                ))
            case .capacitor:
                value = try positiveParameter("capacitance", in: symbol)
                branches.append(PassiveComponentBranch(
                    id: symbol.refDes,
                    firstNodeID: firstNode,
                    secondNodeID: secondNode,
                    type: .capacitor,
                    value: value,
                    seriesResistance: 0
                ))
            case .inductor:
                value = try positiveParameter("inductance", in: symbol)
                branches.append(PassiveComponentBranch(
                    id: symbol.refDes,
                    firstNodeID: firstNode,
                    secondNodeID: secondNode,
                    type: .inductor,
                    value: value,
                    seriesResistance: 0
                ))
            case .inductorSeries:
                value = try positiveParameter("inductance", in: symbol)
                guard let resistance = symbol.parameters["seriesResistance"],
                      resistance.isFinite, resistance >= 0 else {
                    throw CrossoverNetworkSimulationError.invalidParameter(symbol.refDes)
                }
                branches.append(PassiveComponentBranch(
                    id: symbol.refDes,
                    firstNodeID: firstNode,
                    secondNodeID: secondNode,
                    type: .inductor,
                    value: value,
                    seriesResistance: resistance
                ))
            case .voltageSource, .currentSource, .ground:
                throw CrossoverNetworkSimulationError.unsupportedComponent(symbol.refDes)
            }
        }
        return branches
    }

    private static func positiveParameter(_ name: String, in symbol: SymbolInstance) throws -> Double {
        guard let value = symbol.parameters[name], value.isFinite, value > 0 else {
            throw CrossoverNetworkSimulationError.invalidParameter(symbol.refDes)
        }
        return value
    }

    private static func loadImpedance(
        measurement: DriverMeasurement?,
        enclosureModel: EnclosureModel,
        frequencyHz: Double
    ) -> ComplexValue {
        if let measurement, let value = interpolatedComplex(measurement, frequencyHz: frequencyHz) {
            return value
        }
        guard let response = try? enclosureModel.response(at: frequencyHz) else {
            return ComplexValue(real: .nan, imaginary: .nan)
        }
        return ComplexValue(response.electricalImpedance)
    }

    private static func acousticResponse(
        branch: AcousticBranchSettings,
        measurement: DriverMeasurement?,
        frequencyHz: Double
    ) -> ComplexValue {
        if let measurement, let response = interpolatedResponse(measurement, frequencyHz: frequencyHz) {
            return response
        }
        return AcousticSimulator.modeledAcousticResponse(branch, frequencyHz: frequencyHz)
    }

    private static func frequencyBounds(
        wooferFrequencyResponse: DriverMeasurement?,
        tweeterFrequencyResponse: DriverMeasurement?,
        wooferImpedance: DriverMeasurement?,
        tweeterImpedance: DriverMeasurement?
    ) -> ClosedRange<Double> {
        let measurements = [
            wooferFrequencyResponse, tweeterFrequencyResponse,
            wooferImpedance, tweeterImpedance
        ].compactMap { $0 }
        let lower = max(20, measurements.compactMap { $0.points.first?.frequencyHz }.max() ?? 20)
        let upper = min(20_000, measurements.compactMap { $0.points.last?.frequencyHz }.min() ?? 20_000)
        return lower...max(lower, upper)
    }

    private static func interpolatedComplex(
        _ measurement: DriverMeasurement,
        frequencyHz: Double
    ) -> ComplexValue? {
        guard measurement.points.count >= 2,
              let interval = interval(in: measurement.points, frequencyHz: frequencyHz) else {
            return nil
        }
        let (first, second, fraction) = interval
        let firstMagnitude = first.magnitude
        let secondMagnitude = second.magnitude
        let magnitude = exp(log(firstMagnitude) + fraction * (log(secondMagnitude) - log(firstMagnitude)))
        let phase = interpolatedPhase(
            first.phaseDegrees,
            second.phaseDegrees,
            fraction: fraction
        )
        return ComplexValue.polar(magnitude: magnitude, phaseRadians: phase * .pi / 180)
    }

    private static func interpolatedResponse(
        _ measurement: DriverMeasurement,
        frequencyHz: Double
    ) -> ComplexValue? {
        guard measurement.points.count >= 2,
              let interval = interval(in: measurement.points, frequencyHz: frequencyHz) else {
            return nil
        }
        let (first, second, fraction) = interval
        let firstDb = measurement.normalizedMagnitude(first.magnitude)
        let secondDb = measurement.normalizedMagnitude(second.magnitude)
        let magnitudeDb = firstDb + fraction * (secondDb - firstDb)
        let phase = interpolatedPhase(first.phaseDegrees, second.phaseDegrees, fraction: fraction)
        return ComplexValue.polar(
            magnitude: pow(10, magnitudeDb / 20),
            phaseRadians: phase * .pi / 180
        )
    }

    private static func interval(
        in points: [DriverMeasurementPoint],
        frequencyHz: Double
    ) -> (DriverMeasurementPoint, DriverMeasurementPoint, Double)? {
        guard let first = points.first, let last = points.last,
              frequencyHz >= first.frequencyHz, frequencyHz <= last.frequencyHz else {
            return nil
        }
        guard frequencyHz != first.frequencyHz else {
            return (first, points[1], 0)
        }
        guard frequencyHz != last.frequencyHz else {
            return (points[points.count - 2], last, 1)
        }
        guard let upperIndex = points.firstIndex(where: { $0.frequencyHz >= frequencyHz }),
              upperIndex > 0 else {
            return nil
        }
        let lower = points[upperIndex - 1]
        let upper = points[upperIndex]
        let fraction = log(frequencyHz / lower.frequencyHz) / log(upper.frequencyHz / lower.frequencyHz)
        return (lower, upper, fraction)
    }

    private static func interpolatedPhase(_ first: Double, _ second: Double, fraction: Double) -> Double {
        var difference = second - first
        while difference > 180 { difference -= 360 }
        while difference < -180 { difference += 360 }
        return first + fraction * difference
    }

    private static func logFrequencies(start: Double, stop: Double, pointsPerOctave: Int) -> [Double] {
        let intervals = max(1, Int(ceil(log2(stop / start) * Double(pointsPerOctave))))
        return (0...intervals).map {
            start * pow(stop / start, Double($0) / Double(intervals))
        }
    }

    private static func decibels(_ magnitude: Double) -> Double {
        20 * log10(max(magnitude, 1e-12))
    }

}

private struct PassiveComponentBranch {
    enum Kind {
        case resistor
        case capacitor
        case inductor
    }

    let id: String
    let firstNodeID: Int
    let secondNodeID: Int
    let type: Kind
    let value: Double
    let seriesResistance: Double

    var model: ACImpedanceModel {
        switch type {
        case .resistor:
            return .resistance(value)
        case .capacitor:
            return .capacitance(value)
        case .inductor:
            return .inductance(henries: value, seriesResistance: seriesResistance)
        }
    }
}

private extension ComplexValue {
    init(_ value: ACComplex) {
        self.init(real: value.real, imaginary: value.imaginary)
    }

    var acComplex: ACComplex { ACComplex(real: real, imaginary: imaginary) }
}
