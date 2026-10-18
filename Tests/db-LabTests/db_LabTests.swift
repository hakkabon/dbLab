import Foundation
import Testing
@testable import db_Lab

@Test func pinOnWireInteriorConnectsAndDetectsGround() {
    let resistor = SymbolInstance(
        id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
        descriptorId: "resistor",
        refDes: "R1",
        position: GridPoint(0, 0)
    )
    let ground = SymbolInstance(
        id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!,
        descriptorId: "ground",
        refDes: "GND1",
        position: GridPoint(-2, 1)
    )
    let wire = WireSegment(points: [GridPoint(-3, 0), GridPoint(-1, 0)])

    let nets = ConnectivityBuilder.build(symbols: [resistor, ground], wires: [wire])
    let net = net(containing: PinRef(symbolId: resistor.id, pinId: "1"), in: nets)

    #expect(net?.isGround == true)
    #expect(net?.name == "0")
    #expect(net?.connectedPins.contains(PinRef(symbolId: ground.id, pinId: "1")) == true)
}

@Test func rotatedPinsUseTransformedCoordinates() {
    let resistor = SymbolInstance(
        id: UUID(uuidString: "00000000-0000-0000-0000-000000000011")!,
        descriptorId: "resistor",
        refDes: "R1",
        position: GridPoint(0, 0),
        rotation: 90
    )
    let ground = SymbolInstance(
        id: UUID(uuidString: "00000000-0000-0000-0000-000000000012")!,
        descriptorId: "ground",
        refDes: "GND1",
        position: GridPoint(0, -1)
    )

    let nets = ConnectivityBuilder.build(symbols: [resistor, ground], wires: [])
    let net = net(containing: PinRef(symbolId: resistor.id, pinId: "1"), in: nets)

    #expect(net?.connectedPins.contains(PinRef(symbolId: ground.id, pinId: "1")) == true)
}

@Test func wireVertexConnectsToAnotherWireSegment() {
    let horizontal = SymbolInstance(
        id: UUID(uuidString: "00000000-0000-0000-0000-000000000021")!,
        descriptorId: "resistor",
        refDes: "R1",
        position: GridPoint(0, 0)
    )
    let vertical = SymbolInstance(
        id: UUID(uuidString: "00000000-0000-0000-0000-000000000022")!,
        descriptorId: "resistor",
        refDes: "R2",
        position: GridPoint(0, 2),
        rotation: 90
    )
    let wires = [
        WireSegment(points: [GridPoint(-4, 0), GridPoint(4, 0)]),
        WireSegment(points: [GridPoint(0, 0), GridPoint(0, 6)])
    ]

    let nets = ConnectivityBuilder.build(symbols: [horizontal, vertical], wires: wires)
    let horizontalPin = net(containing: PinRef(symbolId: horizontal.id, pinId: "1"), in: nets)
    let verticalPin = net(containing: PinRef(symbolId: vertical.id, pinId: "1"), in: nets)

    #expect(horizontalPin?.id == verticalPin?.id)
}

@Test func crossingWireInteriorsDoNotConnect() {
    let horizontal = SymbolInstance(
        id: UUID(uuidString: "00000000-0000-0000-0000-000000000031")!,
        descriptorId: "resistor",
        refDes: "R1",
        position: GridPoint(0, 0)
    )
    let vertical = SymbolInstance(
        id: UUID(uuidString: "00000000-0000-0000-0000-000000000032")!,
        descriptorId: "resistor",
        refDes: "R2",
        position: GridPoint(0, 3),
        rotation: 90
    )
    let wires = [
        WireSegment(points: [GridPoint(-4, 0), GridPoint(4, 0)]),
        WireSegment(points: [GridPoint(0, -2), GridPoint(0, 8)])
    ]

    let nets = ConnectivityBuilder.build(symbols: [horizontal, vertical], wires: wires)
    let horizontalPin = net(containing: PinRef(symbolId: horizontal.id, pinId: "1"), in: nets)
    let verticalPin = net(containing: PinRef(symbolId: vertical.id, pinId: "1"), in: nets)

    #expect(horizontalPin?.id != verticalPin?.id)
}

@Test func netIDsAreStableWhenInputOrderChanges() {
    let first = SymbolInstance(
        id: UUID(uuidString: "00000000-0000-0000-0000-000000000041")!,
        descriptorId: "resistor",
        refDes: "R1",
        position: GridPoint(0, 0)
    )
    let second = SymbolInstance(
        id: UUID(uuidString: "00000000-0000-0000-0000-000000000042")!,
        descriptorId: "resistor",
        refDes: "R2",
        position: GridPoint(10, 10)
    )

    let forward = ConnectivityBuilder.build(symbols: [first, second], wires: [])
    let reversed = ConnectivityBuilder.build(symbols: [second, first], wires: [])

    #expect(netSignature(forward) == netSignature(reversed))
}

@Test @MainActor func componentRegistryProvidesTypedPassiveDefaults() {
    let document = SchematicDocument()
    let resistor = document.addComponent(descriptorId: "resistor", at: GridPoint(0, 0))
    let capacitor = document.addComponent(descriptorId: "capacitor", at: GridPoint(5, 0))
    let inductor = document.addComponent(descriptorId: "inductor", at: GridPoint(10, 0))

    #expect(resistor?.parameters["resistance"] == 1_000)
    #expect(capacitor?.parameters["capacitance"] == 1e-6)
    #expect(inductor?.parameters["inductance"] == 1e-3)
    #expect(resistor?.refDes == "R1")
    #expect(document.addComponent(descriptorId: "resistor", at: GridPoint(15, 0))?.refDes == "R2")
}

@Test @MainActor func crossoverProjectStartsWithTwoWayDesignTargets() {
    let document = CrossoverDocument()

    #expect(document.name == "Untitled Crossover")
    #expect(document.targetFrequencyHz == 2_500)
    #expect(document.schematic.symbols.isEmpty)
    #expect(document.settingsValidationMessage == nil)

    document.targetFrequencyHz = 0
    #expect(document.settingsValidationMessage == "Target crossover frequency must be a positive finite value.")
}

@Test @MainActor func crossoverNetworkSimulatesLoadedResistiveBranchesAndAcousticSummation() throws {
    let topology = crossoverTestTopology()
    var driver = sampleSpeakerDriver()
    driver.reOhms = 8
    driver.leMilliHenries = 0
    let wooferFRD = flatResponseMeasurement(levelDb: 80, phaseDegrees: 0)
    let tweeterFRD = flatResponseMeasurement(levelDb: 80, phaseDegrees: 0)

    let result = try simulateCrossover(
        topology,
        woofer: driver,
        tweeter: driver,
        wooferFrequencyResponse: wooferFRD,
        tweeterFrequencyResponse: tweeterFRD
    )

    let point = try #require(result.response.first)
    #expect(abs(point.wooferDb - 80 + 20 * log10(2)) < 0.01)
    #expect(abs(point.tweeterDb - 80 + 20 * log10(2)) < 0.01)
    #expect(abs(point.totalDb - 80) < 0.01)
}

@Test @MainActor func crossoverNetworkUsesMeasuredComplexImpedanceForDriverLoading() throws {
    let topology = crossoverTestTopology()
    var driver = sampleSpeakerDriver()
    driver.reOhms = 8
    driver.leMilliHenries = 0
    let wooferFRD = flatResponseMeasurement(levelDb: 80, phaseDegrees: 0)
    let tweeterFRD = flatResponseMeasurement(levelDb: 80, phaseDegrees: 0)

    let nominal = try simulateCrossover(
        topology,
        woofer: driver,
        tweeter: driver,
        wooferFrequencyResponse: wooferFRD,
        tweeterFrequencyResponse: tweeterFRD
    )
    let higherImpedance = try simulateCrossover(
        topology,
        woofer: driver,
        tweeter: driver,
        wooferFrequencyResponse: wooferFRD,
        tweeterFrequencyResponse: tweeterFRD,
        wooferImpedance: impedanceMeasurement(magnitude: 16),
        tweeterImpedance: impedanceMeasurement(magnitude: 16)
    )

    let nominalLevel = try #require(nominal.response.first).wooferDb
    let loadedLevel = try #require(higherImpedance.response.first).wooferDb
    #expect(abs(loadedLevel - nominalLevel - 20 * log10(4 / 3)) < 0.01)
}

@Test @MainActor func crossoverNetworkIncludesMeasuredAcousticPhaseInSummation() throws {
    let topology = crossoverTestTopology()
    var driver = sampleSpeakerDriver()
    driver.reOhms = 8
    driver.leMilliHenries = 0
    let result = try simulateCrossover(
        topology,
        woofer: driver,
        tweeter: driver,
        wooferFrequencyResponse: flatResponseMeasurement(levelDb: 80, phaseDegrees: 0),
        tweeterFrequencyResponse: flatResponseMeasurement(levelDb: 80, phaseDegrees: 180)
    )

    let point = try #require(result.response.first)
    #expect(abs(point.wooferDb - point.tweeterDb) < 0.01)
    #expect(point.totalDb < 10)
}

@Test @MainActor func crossoverNetworkSolvesReactiveCapacitorBranch() throws {
    let schematic = SchematicDocument()
    let wooferResistor = SymbolInstance(
        descriptorId: "resistor",
        refDes: "R1",
        position: GridPoint(0, 0),
        parameters: ["resistance": 8]
    )
    let tweeterResistor = SymbolInstance(
        descriptorId: "resistor",
        refDes: "R2",
        position: GridPoint(0, 10),
        parameters: ["resistance": 8]
    )
    let capacitor = SymbolInstance(
        descriptorId: "capacitor",
        refDes: "C1",
        position: GridPoint(2, 2),
        rotation: 90,
        parameters: ["capacitance": 100e-6]
    )
    let ground = SymbolInstance(
        descriptorId: "ground",
        refDes: "GND1",
        position: GridPoint(2, 5)
    )
    let secondGround = SymbolInstance(
        descriptorId: "ground",
        refDes: "GND2",
        position: GridPoint(50, 1)
    )
    schematic.restore(
        symbols: [wooferResistor, tweeterResistor, capacitor, ground, secondGround],
        wires: [
            WireSegment(points: [GridPoint(-2, 0), GridPoint(-2, 10)]),
            WireSegment(points: [
                GridPoint(2, 4),
                GridPoint(50, 4),
                GridPoint(50, 0)
            ])
        ]
    )
    let topology = (
        schematic: schematic,
        inputNetID: net(containing: PinRef(symbolId: wooferResistor.id, pinId: "1"), in: schematic.nets)!.id,
        wooferOutputNetID: net(containing: PinRef(symbolId: wooferResistor.id, pinId: "2"), in: schematic.nets)!.id,
        tweeterOutputNetID: net(containing: PinRef(symbolId: tweeterResistor.id, pinId: "2"), in: schematic.nets)!.id
    )
    var driver = sampleSpeakerDriver()
    driver.reOhms = 8
    driver.leMilliHenries = 0

    let result = try simulateCrossover(
        topology,
        woofer: driver,
        tweeter: driver,
        wooferFrequencyResponse: flatResponseMeasurement(levelDb: 80, phaseDegrees: 0),
        tweeterFrequencyResponse: flatResponseMeasurement(levelDb: 80, phaseDegrees: 0)
    )

    let lowFrequency = try #require(result.response.first)
    let highFrequency = try #require(result.response.last)
    #expect(lowFrequency.wooferDb > highFrequency.wooferDb + 10)
}

@Test @MainActor func crossoverNetworkRejectsFloatingPassiveSubcircuits() {
    let topology = crossoverTestTopology()
    _ = topology.schematic.addComponent(descriptorId: "resistor", at: GridPoint(100, 100))
    let driver = sampleSpeakerDriver()

    do {
        _ = try simulateCrossover(
            topology,
            woofer: driver,
            tweeter: driver,
            wooferFrequencyResponse: flatResponseMeasurement(levelDb: 80, phaseDegrees: 0),
            tweeterFrequencyResponse: flatResponseMeasurement(levelDb: 80, phaseDegrees: 0)
        )
        Issue.record("A floating component island must not produce a successful simulation.")
    } catch CrossoverNetworkSimulationError.singularNetwork {
    } catch {
        Issue.record("Unexpected solver error: \(error.localizedDescription)")
    }
}

@Test @MainActor func crossoverProjectNodeAssignmentsRemainAttachedToPinsAfterNetChanges() throws {
    let topology = crossoverTestTopology()
    let document = CrossoverDocument()
    document.schematic.restore(symbols: topology.schematic.symbols, wires: topology.schematic.wires)
    document.inputNetID = topology.inputNetID
    let originalNetPins = try #require(document.schematic.nets.first { $0.id == document.inputNetID })
        .connectedPins

    var earlierNet = SymbolInstance(
        descriptorId: "resistor",
        refDes: "A1",
        position: GridPoint(-100, -100)
    )
    earlierNet.parameters["resistance"] = 8
    document.schematic.addSymbol(earlierNet)
    let encodedSnapshot = try JSONEncoder().encode(document.snapshot)
    let decodedSnapshot = try JSONDecoder().decode(CrossoverProjectSnapshot.self, from: encodedSnapshot)
    let restored = CrossoverDocument(snapshot: decodedSnapshot)
    let restoredInput = try #require(restored.schematic.nets.first { $0.id == restored.inputNetID })

    #expect(restoredInput.connectedPins.contains { originalNetPins.contains($0) })
}

@Test func crossoverPaletteContainsOnlyPassiveComponents() {
    let symbols = Set(ComponentRegistry.shared.passiveDescriptors.map(\.symbol))

    #expect(symbols == Set([.resistor, .capacitor, .inductor, .inductorSeries]))
}

@Test @MainActor func appStateCreatesAndSelectsCrossoverProjects() {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let appState = AppState(
        driverLibrary: DriverLibrary(fileURL: directory.appendingPathComponent("drivers.json")),
        projectStore: CrossoverProjectStore(fileURL: directory.appendingPathComponent("projects.json"))
    )
    appState.newCrossover()

    #expect(appState.crossoverDocuments.count == 1)
    #expect(appState.selectedSidebarItem == .crossover(appState.crossoverDocuments[0].id))
}

@Test @MainActor func crossoverProjectsPersistVersionedSettingsAndSchematic() async throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let projectURL = directory.appendingPathComponent("projects.json")
    let store = CrossoverProjectStore(fileURL: projectURL)
    let appState = AppState(
        driverLibrary: DriverLibrary(fileURL: directory.appendingPathComponent("drivers.json")),
        projectStore: store
    )
    appState.newCrossover()
    let project = try #require(appState.crossoverDocuments.first)
    project.name = "Living Room Three-way"
    project.targetFrequencyHz = 1_850
    project.wooferEnclosure = .portedBox
    project.wooferBoxVolumeLiters = 48
    project.wooferPortTuningHz = 34
    project.wooferPortDiameterCentimeters = 8
    project.crossoverAlignment = .butterworth
    project.crossoverOrder = 3
    project.wooferDriverID = UUID(uuidString: "00000000-0000-0000-0000-000000000501")
    let component = try #require(project.schematic.addComponent(
        descriptorId: "inductor",
        at: GridPoint(4, 2)
    ))
    project.schematic.addWire(WireSegment(points: [GridPoint(0, 0), GridPoint(3, 0)]))

    try await Task.sleep(for: .milliseconds(150))

    let data = try Data(contentsOf: projectURL)
    let archive = try #require(
        JSONSerialization.jsonObject(with: data) as? [String: Any]
    )
    #expect(archive["schemaVersion"] as? Int == 1)

    let restoredApp = AppState(
        driverLibrary: DriverLibrary(fileURL: directory.appendingPathComponent("drivers.json")),
        projectStore: store
    )
    let restored = try #require(restoredApp.crossoverDocuments.first)
    #expect(restored.id == project.id)
    #expect(restored.name == "Living Room Three-way")
    #expect(restored.targetFrequencyHz == 1_850)
    #expect(restored.wooferDriverID == project.wooferDriverID)
    #expect(restored.wooferEnclosure == .portedBox)
    #expect(restored.wooferBoxVolumeLiters == 48)
    #expect(restored.wooferPortTuningHz == 34)
    #expect(restored.wooferPortDiameterCentimeters == 8)
    #expect(restored.crossoverAlignment == .butterworth)
    #expect(restored.crossoverOrder == 3)
    #expect(restored.schematic.symbols == [component])
    #expect(restored.schematic.wires == project.schematic.wires)
}

@Test @MainActor func driverLibraryPersistsImportsExportsAndDeletesDrivers() throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let libraryURL = directory.appendingPathComponent("drivers.json")
    var driver = sampleSpeakerDriver()
    driver.measurements = [
        try DriverMeasurementParser.parse(
            Data("100 80 -12\n1000 87 -3\n".utf8),
            kind: .frequencyResponse,
            fileName: "woofer.frd",
            sourceReference: "Manufacturer measurement, 2.83 V / 1 m"
        )
    ]

    let library = DriverLibrary(fileURL: libraryURL)
    try library.save(driver)
    #expect(library.drivers == [driver])

    let restored = DriverLibrary(fileURL: libraryURL)
    #expect(restored.drivers == [driver])

    let imported = DriverLibrary(fileURL: directory.appendingPathComponent("imported.json"))
    try imported.importJSON(try library.exportJSON())
    #expect(imported.drivers == [driver])
    #expect(imported.drivers[0].measurements[0].sourceReference == "Manufacturer measurement, 2.83 V / 1 m")
    #expect(imported.drivers[0].measurements[0].points.count == 2)
    try imported.delete(driver)
    #expect(imported.drivers.isEmpty)
}

@Test func driverDataRequiresSourceAndValidThieleSmallValues() {
    var driver = sampleSpeakerDriver()
    #expect(driver.validationMessage == nil)
    #expect(driver.qts > 0)

    driver.source = " "
    #expect(driver.validationMessage == "Record the manufacturer's datasheet or other data source.")
    driver.source = "Manufacturer datasheet"
    driver.fsHz = .infinity
    #expect(driver.validationMessage != nil)
}

@Test func frdMeasurementImportSortsPointsAndTracksProvenance() throws {
    let measurement = try DriverMeasurementParser.parse(
        Data("* Example FRD\nFrequency, SPL, Phase\n1000, 87.5, -22\n100, 79.0, -8\n".utf8),
        kind: .frequencyResponse,
        fileName: "woofer-response.frd",
        sourceReference: "Manufacturer datasheet, 2.83 V / 1 m",
        importedAt: Date(timeIntervalSince1970: 1_700_000_000)
    )

    #expect(measurement.kind == .frequencyResponse)
    #expect(measurement.sourceFileName == "woofer-response.frd")
    #expect(measurement.sourceReference == "Manufacturer datasheet, 2.83 V / 1 m")
    #expect(measurement.importedAt == Date(timeIntervalSince1970: 1_700_000_000))
    #expect(measurement.hasPhaseData)
    #expect(measurement.points.map(\.frequencyHz) == [100, 1_000])
    #expect(measurement.points.map(\.magnitude) == [79, 87.5])
}

@Test func zmaMeasurementImportAcceptsTabSeparatedValuesWithoutPhase() throws {
    let measurement = try DriverMeasurementParser.parse(
        Data("\u{feff}10\t4.2\r\n100\t6.1\r\n".utf8),
        kind: .impedance,
        fileName: "/Users/test/woofer.zma",
        sourceReference: "Impedance sweep, 20 C",
        importedAt: Date(timeIntervalSince1970: 1)
    )

    #expect(measurement.sourceFileName == "woofer.zma")
    #expect(measurement.points.count == 2)
    #expect(measurement.points[0].frequencyHz == 10)
    #expect(measurement.points[0].magnitude == 4.2)
    #expect(!measurement.hasPhaseData)
    #expect(measurement.points[0].phaseDegrees == 0)
}

@Test func measuredDataImportRejectsDuplicatesInvalidValuesAndInsufficientPoints() {
    func parse(_ text: String, kind: DriverMeasurementKind = .frequencyResponse) throws -> DriverMeasurement {
        try DriverMeasurementParser.parse(
            Data(text.utf8),
            kind: kind,
            fileName: "test.dat",
            sourceReference: "Test source"
        )
    }

    #expect(throws: DriverMeasurementImportError.self) {
        try parse("100 80\n100 81\n")
    }
    #expect(throws: DriverMeasurementImportError.self) {
        try parse("100 0\n200 4\n", kind: .impedance)
    }
    #expect(throws: DriverMeasurementImportError.self) {
        try parse("100 80\n")
    }
    #expect(throws: DriverMeasurementImportError.self) {
        try parse("100 80 0\n200 82\n")
    }
    #expect(throws: DriverMeasurementImportError.self) {
        try DriverMeasurementParser.parse(
            Data("100 80\n200 81\n".utf8),
            kind: .frequencyResponse,
            fileName: "missing-source.frd",
            sourceReference: " "
        )
    }
}

@Test func legacyDriverJSONDecodesWithoutMeasuredDataField() throws {
    let encoded = try JSONEncoder().encode(sampleSpeakerDriver())
    var object = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
    object.removeValue(forKey: "measurements")
    let legacyData = try JSONSerialization.data(withJSONObject: object)

    let decoded = try JSONDecoder().decode(SpeakerDriver.self, from: legacyData)
    #expect(decoded.measurements.isEmpty)
    #expect(decoded.validationMessage == nil)
}

@Test func acousticSimulationProducesFiniteResponsesForAllEnclosures() throws {
    let driver = sampleSpeakerDriver()
    for enclosure in EnclosureType.allCases {
        let settings = AcousticBranchSettings(
            driver: driver,
            enclosure: enclosure,
            boxVolumeLiters: 30,
            portTuningHz: 40,
            portDiameterCentimeters: 7,
            baffleWidthMeters: 0.3,
            band: .lowPass
        )
        let points = try AcousticSimulator.simulate(
            woofer: settings,
            tweeter: AcousticBranchSettings(
                driver: driver,
                enclosure: enclosure,
                boxVolumeLiters: 30,
                portTuningHz: 40,
                portDiameterCentimeters: 7,
                baffleWidthMeters: 0.3,
                band: .highPass
            ),
            crossoverFrequencyHz: 1_280,
            alignment: .linkwitzRiley,
            order: 4
        )

        #expect(points.count > 200)
        #expect(points.allSatisfy {
            $0.frequencyHz.isFinite && $0.wooferDb.isFinite
                && $0.tweeterDb.isFinite && $0.totalDb.isFinite
        })
    }
}

@Test func secondOrderLinkwitzRileySumsWithCorrectHighPassPolarity() throws {
    let driver = sampleSpeakerDriver()
    let branch = AcousticBranchSettings(
        driver: driver,
        enclosure: .closedBox,
        boxVolumeLiters: 30,
        portTuningHz: 40,
        portDiameterCentimeters: 7,
        baffleWidthMeters: 0.3,
        band: .lowPass
    )
    let tweeter = AcousticBranchSettings(
        driver: driver,
        enclosure: .closedBox,
        boxVolumeLiters: 30,
        portTuningHz: 40,
        portDiameterCentimeters: 7,
        baffleWidthMeters: 0.3,
        band: .highPass
    )
    let response = try AcousticSimulator.simulate(
        woofer: branch,
        tweeter: tweeter,
        crossoverFrequencyHz: 1_280,
        alignment: .linkwitzRiley,
        order: 2
    )
    let atCrossover = try #require(response.first { abs($0.frequencyHz - 1_280) < 0.001 })

    #expect(abs((atCrossover.totalDb - atCrossover.wooferDb) - 6.0206) < 0.01)
}

@Test func butterworthOrdersSumWithoutCrossoverCancellation() throws {
    let driver = sampleSpeakerDriver()
    for order in 1...4 {
        let low = AcousticBranchSettings(
            driver: driver,
            enclosure: .closedBox,
            boxVolumeLiters: 30,
            portTuningHz: 40,
            portDiameterCentimeters: 7,
            baffleWidthMeters: 0.3,
            band: .lowPass
        )
        let high = AcousticBranchSettings(
            driver: driver,
            enclosure: .closedBox,
            boxVolumeLiters: 30,
            portTuningHz: 40,
            portDiameterCentimeters: 7,
            baffleWidthMeters: 0.3,
            band: .highPass
        )
        let response = try AcousticSimulator.simulate(
            woofer: low,
            tweeter: high,
            crossoverFrequencyHz: 1_280,
            alignment: .butterworth,
            order: order
        )
        let atCrossover = try #require(response.first { abs($0.frequencyHz - 1_280) < 0.001 })

        let expectedLevelDifference = order.isMultiple(of: 2) ? 6.0206 : 3.0103
        #expect(abs((atCrossover.totalDb - atCrossover.wooferDb) - expectedLevelDifference) < 0.01)
    }
}

@Test func portedBoxDesignCalculatesPracticalPortLength() {
    let length = PortedBoxDesign.portLengthCentimeters(
        volumeLiters: 30,
        tuningHz: 40,
        diameterCentimeters: 7
    )

    #expect(length != nil)
    if let length {
        #expect(length > 0)
    }
    #expect(PortedBoxDesign.portLengthCentimeters(
        volumeLiters: 1,
        tuningHz: 2_000,
        diameterCentimeters: 20
    ) == nil)
}

@Test func acousticSimulationRejectsUnsupportedLinkwitzRileyOrder() throws {
    let driver = sampleSpeakerDriver()
    let low = AcousticBranchSettings(
        driver: driver,
        enclosure: .closedBox,
        boxVolumeLiters: 30,
        portTuningHz: 40,
        portDiameterCentimeters: 7,
        baffleWidthMeters: 0.3,
        band: .lowPass
    )
    let high = AcousticBranchSettings(
        driver: driver,
        enclosure: .closedBox,
        boxVolumeLiters: 5,
        portTuningHz: 100,
        portDiameterCentimeters: 3,
        baffleWidthMeters: 0.2,
        band: .highPass
    )

    #expect(throws: AcousticSimulationError.self) {
        try AcousticSimulator.simulate(
            woofer: low,
            tweeter: high,
            crossoverFrequencyHz: 2_500,
            alignment: .linkwitzRiley,
            order: 3
        )
    }
}

@Test @MainActor func schematicNetlistEmitsVoltageSourceAndPassiveComponents() throws {
    let document = SchematicDocument()
    let source = document.addComponent(descriptorId: "voltage-source", at: GridPoint(0, 0))!
    let resistor = document.addComponent(descriptorId: "resistor", at: GridPoint(4, 0))!
    let ground = document.addComponent(descriptorId: "ground", at: GridPoint(-2, 1))!

    #expect(source.refDes == "V1")
    #expect(resistor.parameters["resistance"] == 1_000)
    #expect(ground.descriptorId == "ground")

    let netlist = try SpiceNetlistBuilder.build(from: document)
    #expect(netlist.contains("V1 0 N"))
    #expect(netlist.contains("R1 N"))
    #expect(netlist.contains("AC 1"))
    #expect(netlist.hasSuffix(".end"))
}

@Test @MainActor func schematicNetlistEmitsCapacitorsAndInductors() throws {
    let document = SchematicDocument()
    let capacitor = document.addComponent(descriptorId: "capacitor", at: GridPoint(0, 0))!
    let inductor = document.addComponent(descriptorId: "inductor", at: GridPoint(5, 0))!
    _ = document.addComponent(descriptorId: "ground", at: GridPoint(0, 2))

    let netlist = try SpiceNetlistBuilder.build(from: document)

    #expect(netlist.contains("C1 N"))
    #expect(netlist.localizedCaseInsensitiveContains("1e-06"))
    #expect(netlist.contains("L1 N"))
    #expect(netlist.contains("0.001"))
    #expect(capacitor.parameters["capacitance"] == 1e-6)
    #expect(inductor.parameters["inductance"] == 1e-3)
}

@Test @MainActor func seriesResistanceInductorExpandsToResistorAndInductor() throws {
    let document = SchematicDocument()
    let inductor = document.addComponent(descriptorId: "inductor-series-resistance", at: GridPoint(0, 0))!
    _ = document.addComponent(descriptorId: "ground", at: GridPoint(-2, 1))
    _ = document.addComponent(descriptorId: "ground", at: GridPoint(2, 1))

    let netlist = try SpiceNetlistBuilder.build(from: document)

    #expect(inductor.refDes == "L1")
    #expect(netlist.contains("R1_SER 0 L1_SER 0.2"))
    #expect(netlist.contains("L1 L1_SER 0 0.001"))
}

@Test @MainActor func schematicNetlistRequiresGroundAndRejectsInvalidValues() {
    let document = SchematicDocument()
    _ = document.addComponent(descriptorId: "resistor", at: GridPoint(0, 0))

    do {
        _ = try SpiceNetlistBuilder.build(from: document)
        Issue.record("A schematic without ground should not generate an analysis netlist.")
    } catch SpiceNetlistBuildError.missingGround {
    } catch {
        Issue.record("Unexpected error: \(error.localizedDescription)")
    }

    _ = document.addComponent(descriptorId: "ground", at: GridPoint(0, 2))
    document.symbols[0].parameters["resistance"] = 0
    do {
        _ = try SpiceNetlistBuilder.build(from: document)
        Issue.record("A zero-ohm resistor should be rejected.")
    } catch SpiceNetlistBuildError.invalidParameter(reference: "R1", parameter: "resistance") {
    } catch {
        Issue.record("Unexpected error: \(error.localizedDescription)")
    }
}

@Test @MainActor func schematicModeBuildsNetlistBeforeSimulation() async {
    let document = CircuitDocument()
    document.usesSchematic = true
    _ = document.schematic.addComponent(descriptorId: "voltage-source", at: GridPoint(0, 0))
    _ = document.schematic.addComponent(descriptorId: "resistor", at: GridPoint(4, 0))
    _ = document.schematic.addComponent(descriptorId: "ground", at: GridPoint(-2, 1))

    await document.runSimulation()

    #expect(document.simulationError == nil)
    #expect(document.simulationResult?.isMock == true)
}

@Test @MainActor func mockSimulationHonorsAnalysisSettings() async throws {
    let result = try await EngineClient.shared.simulateSpice(
        netlist: "R1 1 0 1k",
        runDC: false,
        runAC: true,
        acFStart: 10,
        acFStop: 1_000,
        acPointsPerDecade: 5,
        runTRAN: true,
        tranTStop: 0.001,
        tranTStep: 0.0001
    )

    #expect(result.isMock)
    #expect(result.dc.map { $0.nodes.isEmpty } ?? true)
    #expect(result.ac?.frequencies.count == 11)
    #expect(result.ac?.frequencies.first == 10)
    #expect(result.ac?.frequencies.last == 1_000)
    #expect(result.tran?.timePoints.count == 11)
    #expect(result.tran?.timePoints.last == 0.001)
}

@Test @MainActor func mockSimulationRejectsNoSelectedAnalysis() async {
    do {
        _ = try await EngineClient.shared.simulateSpice(
            netlist: "R1 1 0 1k",
            runDC: false,
            runAC: false,
            runTRAN: false
        )
        Issue.record("Simulation should reject an empty analysis selection.")
    } catch CircuitSimulationError.noAnalysisSelected {
    } catch {
        Issue.record("Unexpected simulation error: \(error.localizedDescription)")
    }
}

private func net(containing pin: PinRef, in nets: [Net]) -> Net? {
    nets.first { $0.connectedPins.contains(pin) }
}

private func sampleSpeakerDriver(id: UUID = UUID()) -> SpeakerDriver {
    SpeakerDriver(
        id: id,
        manufacturer: "Example Audio",
        model: "EA-200",
        source: "https://example.invalid/ea-200-datasheet",
        fsHz: 35,
        qes: 0.42,
        qms: 5.2,
        vasLiters: 45,
        reOhms: 5.8,
        leMilliHenries: 0.8,
        sdSquareCentimeters: 220,
        xmaxMillimeters: 8,
        sensitivityDb: 89
    )
}

@MainActor
private func crossoverTestTopology() -> (
    schematic: SchematicDocument,
    inputNetID: Int,
    wooferOutputNetID: Int,
    tweeterOutputNetID: Int
) {
    let schematic = SchematicDocument()
    let wooferResistor = SymbolInstance(
        descriptorId: "resistor",
        refDes: "R1",
        position: GridPoint(0, 0),
        parameters: ["resistance": 8]
    )
    let tweeterResistor = SymbolInstance(
        descriptorId: "resistor",
        refDes: "R2",
        position: GridPoint(0, 10),
        parameters: ["resistance": 8]
    )
    let ground = SymbolInstance(
        descriptorId: "ground",
        refDes: "GND1",
        position: GridPoint(10, 1)
    )
    schematic.restore(
        symbols: [wooferResistor, tweeterResistor, ground],
        wires: [WireSegment(points: [GridPoint(-2, 0), GridPoint(-2, 10)])]
    )
    return (
        schematic,
        net(containing: PinRef(symbolId: wooferResistor.id, pinId: "1"), in: schematic.nets)!.id,
        net(containing: PinRef(symbolId: wooferResistor.id, pinId: "2"), in: schematic.nets)!.id,
        net(containing: PinRef(symbolId: tweeterResistor.id, pinId: "2"), in: schematic.nets)!.id
    )
}

@MainActor
private func simulateCrossover(
    _ topology: (
        schematic: SchematicDocument,
        inputNetID: Int,
        wooferOutputNetID: Int,
        tweeterOutputNetID: Int
    ),
    woofer: SpeakerDriver,
    tweeter: SpeakerDriver,
    wooferFrequencyResponse: DriverMeasurement?,
    tweeterFrequencyResponse: DriverMeasurement?,
    wooferImpedance: DriverMeasurement? = nil,
    tweeterImpedance: DriverMeasurement? = nil
) throws -> CrossoverSimulationResult {
    try CrossoverNetworkSimulator.simulate(
        schematic: topology.schematic,
        inputNetID: topology.inputNetID,
        wooferOutputNetID: topology.wooferOutputNetID,
        tweeterOutputNetID: topology.tweeterOutputNetID,
        woofer: AcousticBranchSettings(
            driver: woofer,
            enclosure: .closedBox,
            boxVolumeLiters: 30,
            portTuningHz: 40,
            portDiameterCentimeters: 7,
            baffleWidthMeters: 0.3,
            band: .lowPass
        ),
        tweeter: AcousticBranchSettings(
            driver: tweeter,
            enclosure: .closedBox,
            boxVolumeLiters: 5,
            portTuningHz: 100,
            portDiameterCentimeters: 3,
            baffleWidthMeters: 0.2,
            band: .highPass
        ),
        wooferFrequencyResponse: wooferFrequencyResponse,
        tweeterFrequencyResponse: tweeterFrequencyResponse,
        wooferImpedance: wooferImpedance,
        tweeterImpedance: tweeterImpedance
    )
}

private func flatResponseMeasurement(levelDb: Double, phaseDegrees: Double) -> DriverMeasurement {
    DriverMeasurement(
        kind: .frequencyResponse,
        sourceFileName: "flat.frd",
        sourceReference: "Test response",
        importedAt: Date(timeIntervalSince1970: 0),
        hasPhaseData: true,
        points: [
            DriverMeasurementPoint(frequencyHz: 20, magnitude: levelDb, phaseDegrees: phaseDegrees),
            DriverMeasurementPoint(frequencyHz: 20_000, magnitude: levelDb, phaseDegrees: phaseDegrees)
        ]
    )
}

private func impedanceMeasurement(magnitude: Double) -> DriverMeasurement {
    DriverMeasurement(
        kind: .impedance,
        sourceFileName: "load.zma",
        sourceReference: "Test impedance",
        importedAt: Date(timeIntervalSince1970: 0),
        hasPhaseData: true,
        points: [
            DriverMeasurementPoint(frequencyHz: 20, magnitude: magnitude, phaseDegrees: 0),
            DriverMeasurementPoint(frequencyHz: 20_000, magnitude: magnitude, phaseDegrees: 0)
        ]
    )
}

private func netSignature(_ nets: [Net]) -> [String] {
    nets.map { net in
        let pins = net.connectedPins.map { "\($0.symbolId.uuidString):\($0.pinId)" }.sorted()
        return "\(net.id):\(net.name):\(pins.joined(separator: ","))"
    }
}
