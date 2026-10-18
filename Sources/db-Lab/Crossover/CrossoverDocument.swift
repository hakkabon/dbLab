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
    @Published var acousticResponse: [AcousticResponsePoint] = []
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
        schematic.restore(symbols: snapshot.symbols, wires: snapshot.wires)
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
            symbols: schematic.symbols,
            wires: schematic.wires
        )
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
        if let message = settingsValidationMessage {
            simulationError = message
            return
        }

        isSimulating = true
        do {
            acousticResponse = try AcousticSimulator.simulate(
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
                crossoverFrequencyHz: targetFrequencyHz,
                alignment: crossoverAlignment,
                order: crossoverOrder
            )
        } catch {
            simulationError = error.localizedDescription
        }
        isSimulating = false
    }
}
