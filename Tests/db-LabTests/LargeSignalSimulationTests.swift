import Foundation
import Testing
import DBLabDomain
import DBLabMultiphysics

private func largeSignalFixture(driverID: UUID) -> SystemSimulationResult {
    let frequencies = [50.0, 1_000, 5_000]
    func samples(_ real: Double) -> [ComplexTraceSample] {
        frequencies.map { .init(frequencyHz: $0, real: real, imaginary: 0) }
    }
    return SystemSimulationResult(
        frequenciesHz: frequencies,
        inputImpedance: samples(8),
        combinedAcousticPressure: samples(1),
        drivers: [DriverSimulationTrace(
            driverInstanceID: driverID,
            terminalVoltage: samples(2.83),
            current: samples(1),
            acousticPressure: samples(1),
            excursionMillimeters: [6, 2, 0.2],
            portAirVelocityMetersPerSecond: [40, 10, 1]
        )],
        diagnostics: .init(backendIdentifier: "numeric-core-sparse-lu")
    )
}

@Test func largeSignalSweepModelsHeatingCompressionAndLimits() throws {
    let id = UUID()
    let result = try LargeSignalSimulator.simulate(
        smallSignal: largeSignalFixture(driverID: id),
        drivers: [.init(
            driverInstanceID: id, dcResistanceOhms: 6, xmaxMillimeters: 8,
            thermalResistanceKelvinPerWatt: 2, thermalTimeConstantSeconds: 20,
            maximumCoilTemperatureCelsius: 100
        )],
        options: .init(inputVoltagesRMS: [2.83, 5.66, 11.32], stimulusDurationSeconds: 60)
    )
    #expect(result.operatingPoints.count == 3)
    #expect(result.operatingPoints[2].maximumCompressionDecibels > result.operatingPoints[0].maximumCompressionDecibels)
    #expect(result.operatingPoints[2].drivers[0].coilTemperatureCelsius > result.operatingPoints[0].drivers[0].coilTemperatureCelsius)
    #expect(result.operatingPoints[2].drivers[0].hotResistanceOhms > 6)
    #expect(result.firstLimitingMechanism != .none)
    #expect(result.iterations > 0)
}

@Test func largeSignalSweepIsDeterministicAndReportsFrequencyMetrics() throws {
    let id = UUID()
    let parameters = [LargeSignalDriverParameters(driverInstanceID: id, dcResistanceOhms: 6, xmaxMillimeters: 8)]
    let options = LargeSignalOptions(inputVoltagesRMS: [2.83, 8])
    let first = try LargeSignalSimulator.simulate(
        smallSignal: largeSignalFixture(driverID: id), drivers: parameters, options: options
    )
    let second = try LargeSignalSimulator.simulate(
        smallSignal: largeSignalFixture(driverID: id), drivers: parameters, options: options
    )
    #expect(first == second)
    #expect(first.operatingPoints[1].drivers[0].response.count == 3)
    #expect(first.operatingPoints[1].drivers[0].response.allSatisfy { $0.estimatedTHDPercent.isFinite })
}

@Test func largeSignalSweepRejectsInvalidInputsAndMissingDrivers() throws {
    let id = UUID()
    #expect(throws: LargeSignalSimulationError.self) {
        try LargeSignalSimulator.simulate(
            smallSignal: largeSignalFixture(driverID: id),
            drivers: [.init(driverInstanceID: id, dcResistanceOhms: 6, xmaxMillimeters: 8)],
            options: .init(inputVoltagesRMS: [])
        )
    }
    #expect(throws: LargeSignalSimulationError.self) {
        try LargeSignalSimulator.simulate(
            smallSignal: largeSignalFixture(driverID: id),
            drivers: [.init(driverInstanceID: UUID(), dcResistanceOhms: 6, xmaxMillimeters: 8)]
        )
    }
}
