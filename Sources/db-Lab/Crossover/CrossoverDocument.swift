import SwiftUI
import Combine
import DBLabDomain
import DBLabSynthesis
import DBLabAcoustics

@MainActor
final class CrossoverDocument: ObservableObject, Identifiable {
    let id: UUID

    @Published var name = "Untitled Crossover"
    @Published var domainSystem: LoudspeakerSystem?
    @Published var targetFrequencyHz = 2_500.0
    @Published var schematic = SchematicDocument()
    @Published var wooferDriverID: UUID?
    @Published var tweeterDriverID: UUID?
    @Published var wooferDriverSnapshot: SpeakerDriver?
    @Published var tweeterDriverSnapshot: SpeakerDriver?
    @Published var wooferEnclosure = EnclosureType.closedBox
    @Published var tweeterEnclosure = EnclosureType.closedBox
    @Published var wooferBoxVolumeLiters = 30.0
    @Published var tweeterBoxVolumeLiters = 5.0
    @Published var wooferPortTuningHz = 40.0
    @Published var tweeterPortTuningHz = 100.0
    @Published var wooferPortDiameterCentimeters = 7.0
    @Published var tweeterPortDiameterCentimeters = 3.0
    @Published var wooferBaffleWidthMeters = 0.3
    @Published var tweeterBaffleWidthMeters = 0.2
    @Published var crossoverAlignment = CrossoverAlignment.linkwitzRiley
    @Published var crossoverOrder = 4
    @Published private var inputNetReference: PinRef?
    @Published private var wooferOutputNetReference: PinRef?
    @Published private var tweeterOutputNetReference: PinRef?
    @Published var wooferFrequencyResponseID: UUID?
    @Published var tweeterFrequencyResponseID: UUID?
    @Published var wooferImpedanceID: UUID?
    @Published var tweeterImpedanceID: UUID?
    @Published var acousticResponse: [AcousticResponsePoint] = []
    @Published var systemSimulationResult: SystemSimulationResult?
    @Published var simulationWarnings: [String] = []
    @Published var simulationError: String?
    @Published var isSimulating = false
    @Published var synthesisMinimumImpedanceOhms = 3.2
    @Published var synthesisResult: CrossoverSynthesisResult?
    @Published var synthesisError: String?
    @Published var isSynthesizing = false
    @Published var robustComponentTolerancePercent = 5.0
    @Published var robustLoadTolerancePercent = 5.0
    @Published var robustLoadPhaseToleranceDegrees = 3.0
    @Published var robustAllowedErrorDecibels = 2.0
    @Published var robustSampleCount = 200
    @Published var robustDesignResult: RobustDesignResult?
    @Published var robustDesignError: String?
    @Published var isAnalyzingRobustness = false
    @Published var wooferXOffsetMeters = 0.0
    @Published var wooferYOffsetMeters = -0.12
    @Published var wooferZOffsetMeters = 0.0
    @Published var tweeterXOffsetMeters = 0.0
    @Published var tweeterYOffsetMeters = 0.12
    @Published var tweeterZOffsetMeters = 0.0
    @Published var listeningDistanceMeters = 2.0
    @Published var listeningAngleDegrees = 0.0
    @Published var listenerHeightMeters = 1.0
    @Published var acousticCenterHeightMeters = 1.0
    @Published var floorReflectionCoefficient = 0.0
    @Published var airAbsorptionDbPerMeterAt10kHz = 0.0
    @Published var spatialAcousticsResult: SpatialAcousticsResult?
    private var schematicSubscription: AnyCancellable?
    private var simulationTask: Task<Void, Never>?
    private var synthesisTask: Task<Void, Never>?
    private var robustDesignTask: Task<Void, Never>?
    private var lastSynthesisRequest: CrossoverSynthesisRequest?

    init() {
        id = UUID()
        forwardSchematicChanges()
    }

    init(snapshot: CrossoverProjectSnapshot) {
        id = snapshot.id
        name = snapshot.name
        domainSystem = snapshot.domainSystem
        targetFrequencyHz = snapshot.targetFrequencyHz
        wooferDriverID = snapshot.wooferDriverID
        tweeterDriverID = snapshot.tweeterDriverID
        wooferDriverSnapshot = snapshot.wooferDriverSnapshot
        tweeterDriverSnapshot = snapshot.tweeterDriverSnapshot
        wooferEnclosure = snapshot.wooferEnclosure
        tweeterEnclosure = snapshot.tweeterEnclosure
        wooferBoxVolumeLiters = snapshot.wooferBoxVolumeLiters
        tweeterBoxVolumeLiters = snapshot.tweeterBoxVolumeLiters
        wooferPortTuningHz = snapshot.wooferPortTuningHz
        tweeterPortTuningHz = snapshot.tweeterPortTuningHz
        wooferPortDiameterCentimeters = snapshot.wooferPortDiameterCentimeters
        tweeterPortDiameterCentimeters = snapshot.tweeterPortDiameterCentimeters
        wooferBaffleWidthMeters = snapshot.wooferBaffleWidthMeters
        tweeterBaffleWidthMeters = snapshot.tweeterBaffleWidthMeters
        crossoverAlignment = snapshot.crossoverAlignment
        crossoverOrder = snapshot.crossoverOrder
        wooferFrequencyResponseID = snapshot.wooferFrequencyResponseID
        tweeterFrequencyResponseID = snapshot.tweeterFrequencyResponseID
        wooferImpedanceID = snapshot.wooferImpedanceID
        tweeterImpedanceID = snapshot.tweeterImpedanceID
        wooferXOffsetMeters = snapshot.wooferXOffsetMeters ?? 0
        wooferYOffsetMeters = snapshot.wooferYOffsetMeters ?? -0.12
        wooferZOffsetMeters = snapshot.wooferZOffsetMeters ?? 0
        tweeterXOffsetMeters = snapshot.tweeterXOffsetMeters ?? 0
        tweeterYOffsetMeters = snapshot.tweeterYOffsetMeters ?? 0.12
        tweeterZOffsetMeters = snapshot.tweeterZOffsetMeters ?? 0
        listeningDistanceMeters = snapshot.listeningDistanceMeters ?? 2
        listeningAngleDegrees = snapshot.listeningAngleDegrees ?? 0
        listenerHeightMeters = snapshot.listenerHeightMeters ?? 1
        acousticCenterHeightMeters = snapshot.acousticCenterHeightMeters ?? 1
        floorReflectionCoefficient = snapshot.floorReflectionCoefficient ?? 0
        airAbsorptionDbPerMeterAt10kHz = snapshot.airAbsorptionDbPerMeterAt10kHz ?? 0
        schematic.restore(symbols: snapshot.symbols, wires: snapshot.wires)
        inputNetReference = snapshot.inputNetReference ?? netReference(for: snapshot.inputNetID)
        wooferOutputNetReference = snapshot.wooferOutputNetReference ?? netReference(for: snapshot.wooferOutputNetID)
        tweeterOutputNetReference = snapshot.tweeterOutputNetReference ?? netReference(for: snapshot.tweeterOutputNetID)
        forwardSchematicChanges()
    }

    var snapshot: CrossoverProjectSnapshot {
        CrossoverProjectSnapshot(
            id: id,
            name: name,
            domainSystem: makeDomainSystem(),
            targetFrequencyHz: targetFrequencyHz,
            wooferDriverID: wooferDriverID,
            tweeterDriverID: tweeterDriverID,
            wooferDriverSnapshot: wooferDriverSnapshot,
            tweeterDriverSnapshot: tweeterDriverSnapshot,
            wooferEnclosure: wooferEnclosure,
            tweeterEnclosure: tweeterEnclosure,
            wooferBoxVolumeLiters: wooferBoxVolumeLiters,
            tweeterBoxVolumeLiters: tweeterBoxVolumeLiters,
            wooferPortTuningHz: wooferPortTuningHz,
            tweeterPortTuningHz: tweeterPortTuningHz,
            wooferPortDiameterCentimeters: wooferPortDiameterCentimeters,
            tweeterPortDiameterCentimeters: tweeterPortDiameterCentimeters,
            wooferBaffleWidthMeters: wooferBaffleWidthMeters,
            tweeterBaffleWidthMeters: tweeterBaffleWidthMeters,
            crossoverAlignment: crossoverAlignment,
            crossoverOrder: crossoverOrder,
            inputNetID: inputNetID,
            wooferOutputNetID: wooferOutputNetID,
            tweeterOutputNetID: tweeterOutputNetID,
            inputNetReference: inputNetReference,
            wooferOutputNetReference: wooferOutputNetReference,
            tweeterOutputNetReference: tweeterOutputNetReference,
            wooferFrequencyResponseID: wooferFrequencyResponseID,
            tweeterFrequencyResponseID: tweeterFrequencyResponseID,
            wooferImpedanceID: wooferImpedanceID,
            tweeterImpedanceID: tweeterImpedanceID,
            wooferXOffsetMeters: wooferXOffsetMeters,
            wooferYOffsetMeters: wooferYOffsetMeters,
            wooferZOffsetMeters: wooferZOffsetMeters,
            tweeterXOffsetMeters: tweeterXOffsetMeters,
            tweeterYOffsetMeters: tweeterYOffsetMeters,
            tweeterZOffsetMeters: tweeterZOffsetMeters,
            listeningDistanceMeters: listeningDistanceMeters,
            listeningAngleDegrees: listeningAngleDegrees,
            listenerHeightMeters: listenerHeightMeters,
            acousticCenterHeightMeters: acousticCenterHeightMeters,
            floorReflectionCoefficient: floorReflectionCoefficient,
            airAbsorptionDbPerMeterAt10kHz: airAbsorptionDbPerMeterAt10kHz,
            symbols: schematic.symbols,
            wires: schematic.wires
        )
    }

    var inputNetID: Int? {
        get { netID(for: inputNetReference) }
        set { inputNetReference = netReference(for: newValue) }
    }

    var wooferOutputNetID: Int? {
        get { netID(for: wooferOutputNetReference) }
        set { wooferOutputNetReference = netReference(for: newValue) }
    }

    var tweeterOutputNetID: Int? {
        get { netID(for: tweeterOutputNetReference) }
        set { tweeterOutputNetReference = netReference(for: newValue) }
    }

    private func netID(for reference: PinRef?) -> Int? {
        guard let reference else { return nil }
        return schematic.nets.first { $0.connectedPins.contains(reference) }?.id
    }

    private func netReference(for id: Int?) -> PinRef? {
        guard let id else { return nil }
        return schematic.nets.first(where: { $0.id == id })?.connectedPins.first
    }

    private func forwardSchematicChanges() {
        schematicSubscription = schematic.objectWillChange.sink { [weak self] _ in
            self?.objectWillChange.send()
        }
    }

    var settingsValidationMessage: String? {
        guard targetFrequencyHz.isFinite, targetFrequencyHz > 0 else {
            return "Target crossover frequency must be a positive finite value."
        }
        return nil
    }

    private func makeDomainSystem() -> LoudspeakerSystem? {
        let existingAdditionalDrivers = domainSystem?.drivers.filter {
            $0.role != .woofer && $0.role != .tweeter
        } ?? []
        var instances: [DriverInstance] = []
        if let woofer = wooferDriverSnapshot {
            instances.append(DriverInstance(
                name: "Woofer",
                role: .woofer,
                driverRevision: woofer.domainRevision,
                terminals: TerminalAssignment(positiveNode: wooferOutputNetID, negativeNode: nil),
                acousticPosition: .init(
                    xMeters: wooferXOffsetMeters, yMeters: wooferYOffsetMeters,
                    zMeters: wooferZOffsetMeters
                ),
                enclosure: domainEnclosure(
                    type: wooferEnclosure,
                    volume: wooferBoxVolumeLiters,
                    tuning: wooferPortTuningHz,
                    diameter: wooferPortDiameterCentimeters,
                    baffleWidth: wooferBaffleWidthMeters
                ),
                frequencyResponseDatasetID: wooferFrequencyResponseID,
                impedanceDatasetID: wooferImpedanceID
            ))
        }
        if let tweeter = tweeterDriverSnapshot {
            instances.append(DriverInstance(
                name: "Tweeter",
                role: .tweeter,
                driverRevision: tweeter.domainRevision,
                terminals: TerminalAssignment(positiveNode: tweeterOutputNetID, negativeNode: nil),
                acousticPosition: .init(
                    xMeters: tweeterXOffsetMeters, yMeters: tweeterYOffsetMeters,
                    zMeters: tweeterZOffsetMeters
                ),
                enclosure: domainEnclosure(
                    type: tweeterEnclosure,
                    volume: tweeterBoxVolumeLiters,
                    tuning: tweeterPortTuningHz,
                    diameter: tweeterPortDiameterCentimeters,
                    baffleWidth: tweeterBaffleWidthMeters
                ),
                frequencyResponseDatasetID: tweeterFrequencyResponseID,
                impedanceDatasetID: tweeterImpedanceID
            ))
        }
        instances.append(contentsOf: existingAdditionalDrivers)
        guard !instances.isEmpty else { return domainSystem }
        return LoudspeakerSystem(
            id: domainSystem?.id ?? id,
            name: name,
            referenceVoltageRMS: 2.83,
            listeningPosition: .init(
                xMeters: listeningDistanceMeters * sin(listeningAngleDegrees * .pi / 180),
                yMeters: listenerHeightMeters - acousticCenterHeightMeters,
                zMeters: listeningDistanceMeters * cos(listeningAngleDegrees * .pi / 180)
            ),
            drivers: instances
        )
    }

    private func domainEnclosure(
        type: EnclosureType,
        volume: Double,
        tuning: Double,
        diameter: Double,
        baffleWidth: Double
    ) -> EnclosureConfiguration {
        switch type {
        case .openBaffle: .openBaffle(widthMeters: baffleWidth)
        case .closedBox: .sealed(netVolumeLiters: volume)
        case .portedBox: .vented(
            netVolumeLiters: volume,
            tuningHz: tuning,
            portDiameterCentimeters: diameter
        )
        }
    }

    func simulate(using library: DriverLibrary) {
        simulationError = nil
        simulationWarnings = []
        acousticResponse = []
        systemSimulationResult = nil
        spatialAcousticsResult = nil
        guard let wooferID = wooferDriverID,
              let woofer = wooferDriverSnapshot.flatMap({ $0.id == wooferID ? $0 : nil })
                ?? library.drivers.first(where: { $0.id == wooferID }) else {
            simulationError = AcousticSimulationError.missingDriver("woofer").localizedDescription
            return
        }
        guard let tweeterID = tweeterDriverID,
              let tweeter = tweeterDriverSnapshot.flatMap({ $0.id == tweeterID ? $0 : nil })
                ?? library.drivers.first(where: { $0.id == tweeterID }) else {
            simulationError = AcousticSimulationError.missingDriver("tweeter").localizedDescription
            return
        }
        // Freeze the exact driver revision and imported measurements used by
        // this project. Library edits or deletion no longer rewrite history.
        wooferDriverSnapshot = woofer
        tweeterDriverSnapshot = tweeter
        do {
            let request = CrossoverSimulationRequest(
                symbols: schematic.symbols,
                wires: schematic.wires,
                inputNetID: inputNetID,
                wooferOutputNetID: wooferOutputNetID,
                tweeterOutputNetID: tweeterOutputNetID,
                woofer: AcousticBranchSettings(
                    driver: woofer,
                    enclosure: wooferEnclosure,
                    boxVolumeLiters: wooferBoxVolumeLiters,
                    portTuningHz: wooferPortTuningHz,
                    portDiameterCentimeters: wooferPortDiameterCentimeters,
                    baffleWidthMeters: wooferBaffleWidthMeters,
                    band: .lowPass
                ),
                tweeter: AcousticBranchSettings(
                    driver: tweeter,
                    enclosure: tweeterEnclosure,
                    boxVolumeLiters: tweeterBoxVolumeLiters,
                    portTuningHz: tweeterPortTuningHz,
                    portDiameterCentimeters: tweeterPortDiameterCentimeters,
                    baffleWidthMeters: tweeterBaffleWidthMeters,
                    band: .highPass
                ),
                wooferFrequencyResponse: try measurement(
                    id: wooferFrequencyResponseID,
                    kind: .frequencyResponse,
                    driver: woofer
                ),
                tweeterFrequencyResponse: try measurement(
                    id: tweeterFrequencyResponseID,
                    kind: .frequencyResponse,
                    driver: tweeter
                ),
                wooferImpedance: try measurement(
                    id: wooferImpedanceID,
                    kind: .impedance,
                    driver: woofer
                ),
                tweeterImpedance: try measurement(
                    id: tweeterImpedanceID,
                    kind: .impedance,
                    driver: tweeter
                ),
                wooferPosition: .init(xMeters: wooferXOffsetMeters, yMeters: wooferYOffsetMeters, zMeters: wooferZOffsetMeters),
                tweeterPosition: .init(xMeters: tweeterXOffsetMeters, yMeters: tweeterYOffsetMeters, zMeters: tweeterZOffsetMeters),
                spatialOptions: .init(
                    listeningDistanceMeters: listeningDistanceMeters,
                    listeningAngleDegrees: listeningAngleDegrees,
                    listenerHeightMeters: listenerHeightMeters,
                    acousticCenterHeightMeters: acousticCenterHeightMeters,
                    airAbsorptionDecibelsPerMeterAt10kHz: airAbsorptionDbPerMeterAt10kHz,
                    floorReflectionCoefficient: floorReflectionCoefficient
                )
            )
            simulationTask?.cancel()
            isSimulating = true
            simulationTask = Task { [weak self] in
                do {
                    let result = try await Task.detached(priority: .userInitiated) {
                        try request.run()
                    }.value
                    guard !Task.isCancelled else { return }
                    self?.acousticResponse = result.response
                    self?.simulationWarnings = result.warnings
                    self?.domainSystem = self?.makeDomainSystem()
                    self?.systemSimulationResult = result.domainResult(system: self?.domainSystem)
                    self?.spatialAcousticsResult = result.spatialAcoustics
                    self?.isSimulating = false
                } catch is CancellationError {
                    self?.isSimulating = false
                } catch {
                    self?.simulationError = error.localizedDescription
                    self?.isSimulating = false
                }
            }
        } catch {
            simulationError = error.localizedDescription
            isSimulating = false
        }
    }

    func synthesizeCrossover(using library: DriverLibrary) {
        synthesisError = nil
        synthesisResult = nil
        robustDesignResult = nil
        robustDesignError = nil
        guard let wooferID = wooferDriverID,
              let woofer = wooferDriverSnapshot.flatMap({ $0.id == wooferID ? $0 : nil })
                ?? library.drivers.first(where: { $0.id == wooferID }) else {
            synthesisError = AcousticSimulationError.missingDriver("woofer").localizedDescription
            return
        }
        guard let tweeterID = tweeterDriverID,
              let tweeter = tweeterDriverSnapshot.flatMap({ $0.id == tweeterID ? $0 : nil })
                ?? library.drivers.first(where: { $0.id == tweeterID }) else {
            synthesisError = AcousticSimulationError.missingDriver("tweeter").localizedDescription
            return
        }
        do {
            let wooferBranch = AcousticBranchSettings(
                driver: woofer, enclosure: wooferEnclosure,
                boxVolumeLiters: wooferBoxVolumeLiters, portTuningHz: wooferPortTuningHz,
                portDiameterCentimeters: wooferPortDiameterCentimeters,
                baffleWidthMeters: wooferBaffleWidthMeters, band: .lowPass
            )
            let tweeterBranch = AcousticBranchSettings(
                driver: tweeter, enclosure: tweeterEnclosure,
                boxVolumeLiters: tweeterBoxVolumeLiters, portTuningHz: tweeterPortTuningHz,
                portDiameterCentimeters: tweeterPortDiameterCentimeters,
                baffleWidthMeters: tweeterBaffleWidthMeters, band: .highPass
            )
            let request = CrossoverSynthesisRequest(
                crossoverFrequencyHz: targetFrequencyHz,
                alignment: crossoverAlignment == .butterworth ? .butterworth : .linkwitzRiley,
                order: crossoverOrder,
                lowPassLoad: try CrossoverNetworkSimulator.synthesisLoadSamples(
                    branch: wooferBranch,
                    impedanceMeasurement: try measurement(id: wooferImpedanceID, kind: .impedance, driver: woofer),
                    crossoverFrequencyHz: targetFrequencyHz
                ),
                highPassLoad: try CrossoverNetworkSimulator.synthesisLoadSamples(
                    branch: tweeterBranch,
                    impedanceMeasurement: try measurement(id: tweeterImpedanceID, kind: .impedance, driver: tweeter),
                    crossoverFrequencyHz: targetFrequencyHz
                ),
                minimumInputImpedanceOhms: synthesisMinimumImpedanceOhms
            )
            lastSynthesisRequest = request
            synthesisTask?.cancel()
            isSynthesizing = true
            synthesisTask = Task { [weak self] in
                do {
                    let result = try await Task.detached(priority: .userInitiated) {
                        try PassiveCrossoverSynthesizer.synthesize(request)
                    }.value
                    guard !Task.isCancelled else { return }
                    self?.synthesisResult = result
                    self?.isSynthesizing = false
                } catch is CancellationError {
                    self?.isSynthesizing = false
                } catch {
                    self?.synthesisError = error.localizedDescription
                    self?.isSynthesizing = false
                }
            }
        } catch {
            synthesisError = error.localizedDescription
            isSynthesizing = false
        }
    }

    func analyzeRobustness() {
        robustDesignError = nil
        robustDesignResult = nil
        guard let request = lastSynthesisRequest, let synthesisResult else {
            robustDesignError = "Synthesize a crossover before running robust-design analysis."
            return
        }
        let options = RobustDesignOptions(
            componentTolerancePercent: robustComponentTolerancePercent,
            loadMagnitudeTolerancePercent: robustLoadTolerancePercent,
            loadPhaseToleranceDegrees: robustLoadPhaseToleranceDegrees,
            allowedMagnitudeErrorDecibels: robustAllowedErrorDecibels,
            sampleCount: robustSampleCount
        )
        robustDesignTask?.cancel()
        isAnalyzingRobustness = true
        robustDesignTask = Task { [weak self] in
            do {
                let result = try await Task.detached(priority: .userInitiated) {
                    try RobustCrossoverDesigner.analyzeAndRefine(
                        request: request, nominal: synthesisResult, options: options
                    )
                }.value
                guard !Task.isCancelled else { return }
                self?.robustDesignResult = result
                self?.isAnalyzingRobustness = false
            } catch is CancellationError {
                self?.isAnalyzingRobustness = false
            } catch {
                self?.robustDesignError = error.localizedDescription
                self?.isAnalyzingRobustness = false
            }
        }
    }

    func applySynthesizedCrossover() {
        guard let synthesisResult else { return }
        let design = robustDesignResult?.recommendedDesign ?? synthesisResult
        let generated = CrossoverSchematicSynthesizer.makeSchematic(from: design)
        schematic.restore(symbols: generated.symbols, wires: generated.wires)
        inputNetReference = generated.inputReference
        wooferOutputNetReference = generated.wooferOutputReference
        tweeterOutputNetReference = generated.tweeterOutputReference
        simulationError = nil
        acousticResponse = []
        systemSimulationResult = nil
        spatialAcousticsResult = nil
    }

    private func measurement(
        id: UUID?,
        kind: DriverMeasurementKind,
        driver: SpeakerDriver
    ) throws -> DriverMeasurement? {
        guard let id else { return nil }
        guard let match = driver.measurements.first(where: { $0.id == id && $0.kind == kind }) else {
            throw CrossoverNetworkSimulationError.missingMeasurement(
                driver: driver.displayName,
                kind: kind
            )
        }
        return match
    }
}

private struct CrossoverSimulationRequest: Sendable {
    let symbols: [SymbolInstance]
    let wires: [WireSegment]
    let inputNetID: Int?
    let wooferOutputNetID: Int?
    let tweeterOutputNetID: Int?
    let woofer: AcousticBranchSettings
    let tweeter: AcousticBranchSettings
    let wooferFrequencyResponse: DriverMeasurement?
    let tweeterFrequencyResponse: DriverMeasurement?
    let wooferImpedance: DriverMeasurement?
    let tweeterImpedance: DriverMeasurement?
    let wooferPosition: AcousticPosition
    let tweeterPosition: AcousticPosition
    let spatialOptions: SpatialAcousticsOptions

    func run() throws -> CrossoverSimulationResult {
        try CrossoverNetworkSimulator.simulate(
            symbols: symbols,
            wires: wires,
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
}
