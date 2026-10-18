import SwiftUI
import Combine

@MainActor
final class CrossoverDocument: ObservableObject, Identifiable {
    let id: UUID

    @Published var name = "Untitled Crossover"
    @Published var targetFrequencyHz = 2_500.0
    @Published var schematic = SchematicDocument()
    @Published var wooferDriverID: UUID?
    @Published var tweeterDriverID: UUID?
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
    @Published var simulationWarnings: [String] = []
    @Published var simulationError: String?
    @Published var isSimulating = false
    private var schematicSubscription: AnyCancellable?

    init() {
        id = UUID()
        forwardSchematicChanges()
    }

    init(snapshot: CrossoverProjectSnapshot) {
        id = snapshot.id
        name = snapshot.name
        targetFrequencyHz = snapshot.targetFrequencyHz
        wooferDriverID = snapshot.wooferDriverID
        tweeterDriverID = snapshot.tweeterDriverID
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
            targetFrequencyHz: targetFrequencyHz,
            wooferDriverID: wooferDriverID,
            tweeterDriverID: tweeterDriverID,
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

    func simulate(using library: DriverLibrary) {
        simulationError = nil
        simulationWarnings = []
        acousticResponse = []
        guard let wooferID = wooferDriverID,
              let woofer = library.drivers.first(where: { $0.id == wooferID }) else {
            simulationError = AcousticSimulationError.missingDriver("woofer").localizedDescription
            return
        }
        guard let tweeterID = tweeterDriverID,
              let tweeter = library.drivers.first(where: { $0.id == tweeterID }) else {
            simulationError = AcousticSimulationError.missingDriver("tweeter").localizedDescription
            return
        }
        isSimulating = true
        do {
            let result = try CrossoverNetworkSimulator.simulate(
                schematic: schematic,
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
                )
            )
            acousticResponse = result.response
            simulationWarnings = result.warnings
        } catch {
            simulationError = error.localizedDescription
        }
        isSimulating = false
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
