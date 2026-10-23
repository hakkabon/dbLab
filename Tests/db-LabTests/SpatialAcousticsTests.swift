import Foundation
import Testing
import DBLabDomain
import DBLabAcoustics

private func flatSource(
    id: String = "source", position: AcousticPosition = .init(),
    diameter: Double = 0.2, frequencies: [Double] = [100, 1_000, 10_000]
) -> SpatialSource {
    SpatialSource(
        id: id, position: position, radiatingDiameterMeters: diameter,
        pressureAtOneMeter: frequencies.map {
            ComplexTraceSample(frequencyHz: $0, real: 1, imaginary: 0)
        }
    )
}

@Test func spatialPropagationAppliesInverseDistanceAndDelay() throws {
    let oneMeter = try SpatialAcousticsSimulator.simulate(
        sources: [flatSource()], options: .init(listeningDistanceMeters: 1)
    )
    let twoMeters = try SpatialAcousticsSimulator.simulate(
        sources: [flatSource()], options: .init(listeningDistanceMeters: 2)
    )
    let difference = oneMeter.listeningResponse[1].soundPressureLevelDecibels
        - twoMeters.listeningResponse[1].soundPressureLevelDecibels
    #expect(abs(difference - 20 * log10(2)) < 1e-10)
    #expect(oneMeter.listeningResponse[1].pressure.phaseRadians != twoMeters.listeningResponse[1].pressure.phaseRadians)
}

@Test func circularPistonNarrowsAtHighFrequency() throws {
    let result = try SpatialAcousticsSimulator.simulate(
        sources: [flatSource()],
        options: .init(listeningDistanceMeters: 2, polarAngleStepDegrees: 10, polarFrequenciesHz: [100, 10_000])
    )
    let low = try #require(result.polarResponse.first { $0.frequencyHz == 100 && $0.angleDegrees == 60 })
    let high = try #require(result.polarResponse.first { $0.frequencyHz == 10_000 && $0.angleDegrees == 60 })
    #expect(high.relativeLevelDecibels < low.relativeLevelDecibels - 10)
}

@Test func sourceOffsetsCreateFrequencyDependentInterference() throws {
    let frequencies = [500.0, 1_000, 2_000, 4_000]
    let sources = [
        flatSource(id: "low", position: .init(yMeters: -0.15), frequencies: frequencies),
        flatSource(id: "high", position: .init(yMeters: 0.15), diameter: 0.03, frequencies: frequencies)
    ]
    let result = try SpatialAcousticsSimulator.simulate(
        sources: sources, options: .init(listeningDistanceMeters: 2, listeningAngleDegrees: 20)
    )
    let levels = result.listeningResponse.map(\.soundPressureLevelDecibels)
    #expect((levels.max() ?? 0) - (levels.min() ?? 0) > 0.1)
}

@Test func floorReflectionChangesResponseAndInvalidGeometryIsRejected() throws {
    let dry = try SpatialAcousticsSimulator.simulate(
        sources: [flatSource()], options: .init(listeningDistanceMeters: 2)
    )
    let reflected = try SpatialAcousticsSimulator.simulate(
        sources: [flatSource()], options: .init(listeningDistanceMeters: 2, floorReflectionCoefficient: 0.5)
    )
    #expect(dry.listeningResponse.map(\.soundPressureLevelDecibels) != reflected.listeningResponse.map(\.soundPressureLevelDecibels))
    #expect(throws: SpatialAcousticsError.self) {
        try SpatialAcousticsSimulator.simulate(sources: [flatSource()], options: .init(listeningDistanceMeters: 0))
    }
}
