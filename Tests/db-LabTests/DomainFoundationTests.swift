import Foundation
import Testing
@testable import DBLabCore
import DBLabDomain

private struct NormalizationFixture: Decodable {
    let sourceVoltageRMS: Double
    let sourceDistanceMeters: Double
    let targetVoltageRMS: Double
    let targetDistanceMeters: Double
    let expectedGainDecibels: Double
}

@Test func measurementCalibrationMatchesGoldenFixture() throws {
    let url = try #require(Bundle.module.url(
        forResource: "measurement-normalization",
        withExtension: "json",
        subdirectory: "Fixtures"
    ))
    let fixture = try JSONDecoder().decode(
        NormalizationFixture.self,
        from: Data(contentsOf: url)
    )
    let calibration = MeasurementCalibration(
        acousticLevelReference: .voltage(rms: fixture.sourceVoltageRMS),
        distanceMeters: fixture.sourceDistanceMeters
    )
    let gain = try #require(calibration.gainDecibels(
        targetVoltageRMS: fixture.targetVoltageRMS,
        targetDistanceMeters: fixture.targetDistanceMeters
    ))
    #expect(abs(gain - fixture.expectedGainDecibels) < 1e-10)
}

@Test func nWaySystemRoundTripsWithoutLosingDriverSemantics() throws {
    let baseID = UUID(uuidString: "10000000-0000-0000-0000-000000000001")!
    let roles: [DriverRole] = [.woofer, .midrange, .tweeter]
    let instances = roles.enumerated().map { index, role in
        DriverInstance(
            id: UUID(),
            name: role.rawValue,
            role: role,
            driverRevision: domainTestRevision(driverID: baseID, revision: index + 1),
            terminals: TerminalAssignment(positiveNode: index + 1, negativeNode: 0),
            polarity: index == 1 ? .inverted : .normal,
            acousticPosition: AcousticPosition(xMeters: 0, yMeters: Double(index) * 0.1, zMeters: 0),
            enclosure: index == 0
                ? .vented(netVolumeLiters: 40, tuningHz: 35, portDiameterCentimeters: 7)
                : .sealed(netVolumeLiters: 5)
        )
    }
    let system = LoudspeakerSystem(name: "Three-way reference", drivers: instances)
    let decoded = try JSONDecoder().decode(
        LoudspeakerSystem.self,
        from: JSONEncoder().encode(system)
    )

    #expect(decoded == system)
    #expect(decoded.drivers.map(\.role) == roles)
    #expect(decoded.drivers[1].polarity == .inverted)
}

@Test func driverRevisionCatalogRejectsBrokenHistory() throws {
    let driverID = UUID()
    let first = domainTestRevision(driverID: driverID, revision: 1)
    var catalog = DriverRevisionCatalog()
    try catalog.append(first)
    let second = domainTestRevision(
        driverID: driverID,
        revision: 2,
        supersedes: first.id
    )
    try catalog.append(second)

    #expect(catalog.currentRevision(for: driverID)?.id == second.id)
    #expect(catalog.history(for: driverID).map(\.revision) == [1, 2])

    #expect(throws: DriverRevisionError.self) {
        try catalog.append(domainTestRevision(driverID: driverID, revision: 4, supersedes: second.id))
    }
}

@Test func legacyDriverAdaptsToImmutableDomainRevision() {
    let driver = sampleDomainAdapterDriver()
    let revision = driver.domainRevision

    #expect(revision.driverID == driver.id)
    #expect(revision.id == driver.revisionID)
    #expect(revision.measurements.count == driver.measurements.count)
}

@Test @MainActor func driverLibraryPreservesImmutableRevisionHistory() throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let url = directory.appendingPathComponent("drivers.json")
    let library = DriverLibrary(fileURL: url)
    var driver = sampleDomainAdapterDriver()
    try library.save(driver)
    driver.sensitivityDb = 89
    try library.save(driver)

    let current = try #require(library.drivers.first)
    #expect(current.revision == 2)
    #expect(library.revisions(for: driver.id).map(\.revision) == [1, 2])

    let restored = DriverLibrary(fileURL: url)
    #expect(restored.revisions(for: driver.id).map(\.revision) == [1, 2])
    #expect(restored.drivers.first?.supersedesRevisionID != nil)
}

private func domainTestRevision(
    driverID: UUID,
    revision: Int,
    supersedes: UUID? = nil
) -> SpeakerDriverRevision {
    SpeakerDriverRevision(
        driverID: driverID,
        revision: revision,
        supersedesRevisionID: supersedes,
        manufacturer: "Reference",
        model: "D\(revision)",
        source: "Golden fixture",
        fsHz: 40,
        qes: 0.4,
        qms: 4,
        vasLiters: 30,
        reOhms: 6,
        leMilliHenries: 0.5,
        sdSquareCentimeters: 150,
        xmaxMillimeters: 5,
        sensitivityDb: 88
    )
}

private func sampleDomainAdapterDriver() -> SpeakerDriver {
    SpeakerDriver(
        manufacturer: "Reference",
        model: "Adapter",
        source: "Fixture",
        fsHz: 40,
        qes: 0.4,
        qms: 4,
        vasLiters: 30,
        reOhms: 6,
        leMilliHenries: 0.5,
        sdSquareCentimeters: 150,
        xmaxMillimeters: 5,
        sensitivityDb: 88
    )
}
