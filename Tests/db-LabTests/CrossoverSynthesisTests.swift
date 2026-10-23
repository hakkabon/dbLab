import Testing
import DBLabNumeric
import DBLabSynthesis
@testable import DBLabCore

@Test func synthesizerFitsSecondOrderButterworthForResistiveLoads() throws {
    let load = [500.0, 8_000.0].map {
        ACImpedanceSample(frequencyHz: $0, impedance: ACComplex(real: 8))
    }
    let result = try PassiveCrossoverSynthesizer.synthesize(.init(
        crossoverFrequencyHz: 2_000,
        alignment: .butterworth,
        order: 2,
        lowPassLoad: load,
        highPassLoad: load,
        minimumInputImpedanceOhms: 2
    ))

    #expect(result.lowPass.components.map(\.kind) == [.seriesInductor, .shuntCapacitor])
    #expect(result.highPass.components.map(\.kind) == [.seriesCapacitor, .shuntInductor])
    #expect(result.lowPass.components.allSatisfy { $0.value.isFinite && $0.value > 0 })
    #expect(result.highPass.components.allSatisfy { $0.value.isFinite && $0.value > 0 })
    #expect(result.rmsMagnitudeErrorDecibels < 2)
    #expect(result.minimumInputImpedanceOhms.isFinite)
    #expect(result.backendIdentifier.contains("numeric-core"))
}

@Test func synthesizerRejectsLoadTablesWithoutRequiredBandwidth() {
    let load = [1_000.0, 3_000.0].map {
        ACImpedanceSample(frequencyHz: $0, impedance: ACComplex(real: 8))
    }
    #expect(throws: CrossoverSynthesisError.self) {
        try PassiveCrossoverSynthesizer.synthesize(.init(
            crossoverFrequencyHz: 2_000, alignment: .butterworth, order: 2,
            lowPassLoad: load, highPassLoad: load
        ))
    }
}

@Test func synthesizedLadderProducesConnectedApplicationSchematic() throws {
    let load = [500.0, 8_000.0].map {
        ACImpedanceSample(frequencyHz: $0, impedance: ACComplex(real: 8))
    }
    let result = try PassiveCrossoverSynthesizer.synthesize(.init(
        crossoverFrequencyHz: 2_000, alignment: .butterworth, order: 2,
        lowPassLoad: load, highPassLoad: load, minimumInputImpedanceOhms: 2
    ))
    let generated = CrossoverSchematicSynthesizer.makeSchematic(from: result)
    let nets = ConnectivityBuilder.build(symbols: generated.symbols, wires: generated.wires)
    let input = try #require(nets.first { $0.connectedPins.contains(generated.inputReference) })
    let woofer = try #require(nets.first { $0.connectedPins.contains(generated.wooferOutputReference) })
    let tweeter = try #require(nets.first { $0.connectedPins.contains(generated.tweeterOutputReference) })

    #expect(input.connectedPins.count >= 2)
    #expect(input.id != woofer.id)
    #expect(input.id != tweeter.id)
    #expect(woofer.id != tweeter.id)
    #expect(nets.contains { $0.isGround })
    #expect(generated.symbols.filter { $0.descriptorId == "inductor" }.count == 2)
    #expect(generated.symbols.filter { $0.descriptorId == "capacitor" }.count == 2)
}
