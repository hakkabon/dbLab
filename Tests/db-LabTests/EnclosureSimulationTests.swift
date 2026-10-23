import Foundation
import Testing
import DBLabDomain
import DBLabEnclosure

private let referenceDriver = EnclosureDriverParameters(
    fsHz: 30, qes: 0.38, qms: 4.5, vasLiters: 100,
    reOhms: 5.8, leMilliHenries: 0.6,
    sdSquareCentimeters: 350, xmaxMillimeters: 8
)

@Test func sealedAlignmentDerivesExpectedResonanceAndElectricalLoading() throws {
    let freeAir = try EnclosureModel(
        driver: referenceDriver,
        enclosure: .openBaffle(widthMeters: 0.4)
    )
    let sealed = try EnclosureModel(
        driver: referenceDriver,
        enclosure: .sealed(netVolumeLiters: 50)
    )
    let expectedResonance = 30 * sqrt(1 + 100.0 / 50.0)

    #expect(abs(sealed.alignment.systemResonanceHz - expectedResonance) < 1e-12)
    #expect(abs((sealed.alignment.complianceRatio ?? 0) - 2) < 1e-12)

    let sealedAtFc = try sealed.response(at: expectedResonance)
    let freeAtFc = try freeAir.response(at: expectedResonance)
    #expect(sealedAtFc.electricalImpedance.magnitude > freeAtFc.electricalImpedance.magnitude)
    #expect(sealedAtFc.coneDisplacementMetersPerVolt.isFinite)
    #expect(sealedAtFc.acousticPressurePascalsPerVolt.isFinite)
}

@Test func ventedAlignmentProducesPortOutputAndSuppressesConeMotionAtTuning() throws {
    let vented = try EnclosureModel(
        driver: referenceDriver,
        enclosure: .vented(netVolumeLiters: 70, tuningHz: 32, portDiameterCentimeters: 10)
    )
    let atTuning = try vented.response(at: 32)
    let belowTuning = try vented.response(at: 16)

    #expect(vented.alignment.portLengthCentimeters != nil)
    #expect((atTuning.portAirVelocityMetersPerSecondPerVolt?.magnitude ?? 0) > 0)
    #expect(atTuning.portPressurePascalsPerVolt?.isFinite == true)
    #expect(atTuning.coneDisplacementMetersPerVolt.magnitude < belowTuning.coneDisplacementMetersPerVolt.magnitude)
}

@Test func openBaffleWidthControlsLowFrequencyDipoleCancellation() throws {
    let narrow = try EnclosureModel(
        driver: referenceDriver,
        enclosure: .openBaffle(widthMeters: 0.2)
    )
    let wide = try EnclosureModel(
        driver: referenceDriver,
        enclosure: .openBaffle(widthMeters: 0.8)
    )

    let narrowPressure = try narrow.response(at: 50).acousticPressurePascalsPerVolt.magnitude
    let widePressure = try wide.response(at: 50).acousticPressurePascalsPerVolt.magnitude
    #expect(widePressure > narrowPressure)
}

@Test func enclosureDriverDerivationReconstructsFreeAirResonance() throws {
    let model = try EnclosureModel(
        driver: referenceDriver,
        enclosure: .openBaffle(widthMeters: 0.4)
    )
    let reconstructed = 1 / (2 * .pi * sqrt(
        model.derived.movingMassKilograms * model.derived.complianceMetersPerNewton
    ))
    #expect(abs(reconstructed - referenceDriver.fsHz) < 1e-12)
    #expect(model.derived.forceFactorNewtonPerAmpere > 0)
}
