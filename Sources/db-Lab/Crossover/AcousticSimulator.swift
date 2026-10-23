import Foundation
import DBLabDomain
import DBLabEnclosure
import DBLabNumeric

enum EnclosureType: String, CaseIterable, Identifiable, Codable, Sendable {
    case openBaffle = "Open baffle"
    case closedBox = "Closed box"
    case portedBox = "Ported box"

    var id: String { rawValue }
}

enum CrossoverAlignment: String, CaseIterable, Identifiable, Equatable, Codable, Sendable {
    case butterworth = "Butterworth"
    case linkwitzRiley = "Linkwitz–Riley"

    var id: String { rawValue }
}

enum DriverBand: Equatable, Sendable {
    case lowPass
    case highPass
}

struct AcousticBranchSettings: Sendable {
    let driver: SpeakerDriver
    let enclosure: EnclosureType
    let boxVolumeLiters: Double
    let portTuningHz: Double
    let portDiameterCentimeters: Double
    let baffleWidthMeters: Double
    let band: DriverBand

    var domainEnclosure: EnclosureConfiguration {
        switch enclosure {
        case .openBaffle: .openBaffle(widthMeters: baffleWidthMeters)
        case .closedBox: .sealed(netVolumeLiters: boxVolumeLiters)
        case .portedBox: .vented(
            netVolumeLiters: boxVolumeLiters,
            tuningHz: portTuningHz,
            portDiameterCentimeters: portDiameterCentimeters
        )
        }
    }
}

struct AcousticResponsePoint: Identifiable, Sendable {
    let frequencyHz: Double
    let wooferDb: Double
    let tweeterDb: Double
    let totalDb: Double

    var id: Double { frequencyHz }
}

enum AcousticSimulationError: LocalizedError {
    case missingDriver(String)
    case invalidSettings(String)

    var errorDescription: String? {
        switch self {
        case .missingDriver(let band):
            "Select a driver for the \(band) before running the acoustic simulation."
        case .invalidSettings(let message):
            message
        }
    }
}

enum PortedBoxDesign {
    static func portLengthCentimeters(
        volumeLiters: Double,
        tuningHz: Double,
        diameterCentimeters: Double
    ) -> Double? {
        guard volumeLiters.isFinite, volumeLiters > 0,
              tuningHz.isFinite, tuningHz > 0,
              diameterCentimeters.isFinite, diameterCentimeters > 0 else {
            return nil
        }
        return EnclosureModel.portLengthCentimeters(
            volumeLiters: volumeLiters,
            tuningHz: tuningHz,
            diameterCentimeters: diameterCentimeters
        )
    }
}

enum AcousticSimulator {
    static func simulate(
        woofer: AcousticBranchSettings,
        tweeter: AcousticBranchSettings,
        crossoverFrequencyHz: Double,
        alignment: CrossoverAlignment,
        order: Int
    ) throws -> [AcousticResponsePoint] {
        guard crossoverFrequencyHz.isFinite, crossoverFrequencyHz > 0 else {
            throw AcousticSimulationError.invalidSettings("Crossover frequency must be a positive finite value.")
        }
        guard order >= 1, order <= 4,
              alignment != .linkwitzRiley || order == 2 || order == 4 else {
            throw AcousticSimulationError.invalidSettings(
                "Linkwitz–Riley filters are supported at 2nd and 4th order; Butterworth filters support 1st through 4th order."
            )
        }
        try validate(woofer)
        try validate(tweeter)

        let frequencies = logFrequencies(start: 20, stop: 20_000, pointsPerOctave: 24)
        let response = frequencies.map { frequency in
            let w = branchResponse(
                woofer,
                frequencyHz: frequency,
                crossoverFrequencyHz: crossoverFrequencyHz,
                alignment: alignment,
                order: order
            )
            let t = branchResponse(
                tweeter,
                frequencyHz: frequency,
                crossoverFrequencyHz: crossoverFrequencyHz,
                alignment: alignment,
                order: order
            )
            return AcousticResponsePoint(
                frequencyHz: frequency,
                wooferDb: db(w.magnitude),
                tweeterDb: db(t.magnitude),
                totalDb: db((w + t).magnitude)
            )
        }
        guard response.allSatisfy({
            $0.frequencyHz.isFinite && $0.wooferDb.isFinite
                && $0.tweeterDb.isFinite && $0.totalDb.isFinite
        }) else {
            throw AcousticSimulationError.invalidSettings(
                "The selected driver and enclosure values produce a non-finite response."
            )
        }
        return response
    }

    private static func validate(_ branch: AcousticBranchSettings) throws {
        guard let message = branch.driver.validationMessage else {
            switch branch.enclosure {
            case .openBaffle:
                guard branch.baffleWidthMeters.isFinite, branch.baffleWidthMeters > 0 else {
                    throw AcousticSimulationError.invalidSettings("Baffle width must be a positive finite value.")
                }
            case .closedBox:
                guard branch.boxVolumeLiters.isFinite, branch.boxVolumeLiters > 0 else {
                    throw AcousticSimulationError.invalidSettings("Closed-box volume must be a positive finite value.")
                }
            case .portedBox:
                guard branch.boxVolumeLiters.isFinite, branch.boxVolumeLiters > 0,
                      branch.portTuningHz.isFinite, branch.portTuningHz > 0,
                      PortedBoxDesign.portLengthCentimeters(
                        volumeLiters: branch.boxVolumeLiters,
                        tuningHz: branch.portTuningHz,
                        diameterCentimeters: branch.portDiameterCentimeters
                      ) != nil else {
                    throw AcousticSimulationError.invalidSettings(
                        "Ported-box volume, tuning, and port diameter must produce a positive port length."
                    )
                }
            }
            return
        }
        throw AcousticSimulationError.invalidSettings("\(branch.driver.displayName): \(message)")
    }

    static func modeledAcousticResponse(
        _ branch: AcousticBranchSettings,
        frequencyHz: Double
    ) -> ComplexValue {
        guard let response = try? enclosureModel(for: branch).response(at: frequencyHz) else {
            return ComplexValue(real: 0, imaginary: 0)
        }
        return ComplexValue(response.acousticPressurePascalsPerVolt) * (2.83 / 20e-6)
    }

    static func enclosureModel(for branch: AcousticBranchSettings) throws -> EnclosureModel {
        try EnclosureModel(
            driver: EnclosureDriverParameters(
                fsHz: branch.driver.fsHz, qes: branch.driver.qes, qms: branch.driver.qms,
                vasLiters: branch.driver.vasLiters, reOhms: branch.driver.reOhms,
                leMilliHenries: branch.driver.leMilliHenries,
                sdSquareCentimeters: branch.driver.sdSquareCentimeters,
                xmaxMillimeters: branch.driver.xmaxMillimeters
            ),
            enclosure: branch.domainEnclosure
        )
    }

    private static func branchResponse(
        _ branch: AcousticBranchSettings,
        frequencyHz: Double,
        crossoverFrequencyHz: Double,
        alignment: CrossoverAlignment,
        order: Int
    ) -> ComplexValue {
        let normalizedFrequency = frequencyHz / crossoverFrequencyHz
        let filter = crossoverTransfer(
            normalizedFrequency,
            band: branch.band,
            alignment: alignment,
            order: order
        )
        return modeledAcousticResponse(branch, frequencyHz: frequencyHz) * filter
    }

    private static func crossoverTransfer(
        _ ratio: Double,
        band: DriverBand,
        alignment: CrossoverAlignment,
        order: Int
    ) -> ComplexValue {
        let s = ComplexValue(real: 0, imaginary: ratio)
        let baseOrder = alignment == .linkwitzRiley ? order / 2 : order
        var denominator = ComplexValue(real: 1, imaginary: 0)

        for index in 0..<baseOrder {
            let angle = Double.pi / 2 + Double(2 * index + 1) * Double.pi / Double(2 * baseOrder)
            let pole = ComplexValue(real: cos(angle), imaginary: sin(angle))
            denominator = denominator * (s - pole)
        }

        var transfer: ComplexValue
        switch band {
        case .lowPass:
            transfer = ComplexValue(real: 1, imaginary: 0) / denominator
        case .highPass:
            var numerator = ComplexValue(real: 1, imaginary: 0)
            for _ in 0..<baseOrder {
                numerator = numerator * s
            }
            transfer = numerator / denominator
        }
        if alignment == .linkwitzRiley {
            transfer = transfer * transfer
        }
        if band == .highPass, order.isMultiple(of: 2), order % 4 != 0 {
            transfer = transfer * -1
        }
        return transfer
    }

    private static func logFrequencies(start: Double, stop: Double, pointsPerOctave: Int) -> [Double] {
        let count = Int(ceil(log2(stop / start) * Double(pointsPerOctave)))
        return (0...count).map { index in
            min(start * pow(2, Double(index) / Double(pointsPerOctave)), stop)
        }
    }

    private static func db(_ magnitude: Double) -> Double {
        20 * log10(max(magnitude, 1e-12))
    }
}

struct ComplexValue: Sendable {
    var real: Double
    var imaginary: Double

    var magnitude: Double { hypot(real, imaginary) }

    static func polar(magnitude: Double, phaseRadians: Double) -> Self {
        Self(
            real: magnitude * cos(phaseRadians),
            imaginary: magnitude * sin(phaseRadians)
        )
    }

    static func + (lhs: Self, rhs: Self) -> Self {
        Self(real: lhs.real + rhs.real, imaginary: lhs.imaginary + rhs.imaginary)
    }

    static func - (lhs: Self, rhs: Self) -> Self {
        Self(real: lhs.real - rhs.real, imaginary: lhs.imaginary - rhs.imaginary)
    }

    static func * (lhs: Self, rhs: Self) -> Self {
        Self(
            real: lhs.real * rhs.real - lhs.imaginary * rhs.imaginary,
            imaginary: lhs.real * rhs.imaginary + lhs.imaginary * rhs.real
        )
    }

    static func * (lhs: Self, rhs: Double) -> Self {
        Self(real: lhs.real * rhs, imaginary: lhs.imaginary * rhs)
    }

    static func / (lhs: Self, rhs: Self) -> Self {
        let denominator = rhs.real * rhs.real + rhs.imaginary * rhs.imaginary
        return Self(
            real: (lhs.real * rhs.real + lhs.imaginary * rhs.imaginary) / denominator,
            imaginary: (lhs.imaginary * rhs.real - lhs.real * rhs.imaginary) / denominator
        )
    }
}

private extension ComplexValue {
    init(_ value: ACComplex) {
        self.init(real: value.real, imaginary: value.imaginary)
    }
}
