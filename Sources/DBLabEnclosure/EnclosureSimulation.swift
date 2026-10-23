import Foundation
import DBLabDomain
import DBLabNumeric

public struct EnclosureEnvironment: Sendable, Hashable, Codable {
    public var airDensityKilogramsPerCubicMeter: Double
    public var speedOfSoundMetersPerSecond: Double
    public var listeningDistanceMeters: Double
    public var boxLossQ: Double
    public var portLossQ: Double

    public init(
        airDensityKilogramsPerCubicMeter: Double = 1.204,
        speedOfSoundMetersPerSecond: Double = 343,
        listeningDistanceMeters: Double = 1,
        boxLossQ: Double = 7,
        portLossQ: Double = 7
    ) {
        self.airDensityKilogramsPerCubicMeter = airDensityKilogramsPerCubicMeter
        self.speedOfSoundMetersPerSecond = speedOfSoundMetersPerSecond
        self.listeningDistanceMeters = listeningDistanceMeters
        self.boxLossQ = boxLossQ
        self.portLossQ = portLossQ
    }
}

public struct EnclosureDriverParameters: Sendable, Hashable, Codable {
    public let fsHz: Double
    public let qes: Double
    public let qms: Double
    public let vasLiters: Double
    public let reOhms: Double
    public let leMilliHenries: Double
    public let sdSquareCentimeters: Double
    public let xmaxMillimeters: Double

    public init(
        fsHz: Double, qes: Double, qms: Double, vasLiters: Double,
        reOhms: Double, leMilliHenries: Double,
        sdSquareCentimeters: Double, xmaxMillimeters: Double
    ) {
        self.fsHz = fsHz
        self.qes = qes
        self.qms = qms
        self.vasLiters = vasLiters
        self.reOhms = reOhms
        self.leMilliHenries = leMilliHenries
        self.sdSquareCentimeters = sdSquareCentimeters
        self.xmaxMillimeters = xmaxMillimeters
    }

    public init(_ revision: SpeakerDriverRevision) {
        self.init(
            fsHz: revision.fsHz, qes: revision.qes, qms: revision.qms,
            vasLiters: revision.vasLiters, reOhms: revision.reOhms,
            leMilliHenries: revision.leMilliHenries,
            sdSquareCentimeters: revision.sdSquareCentimeters,
            xmaxMillimeters: revision.xmaxMillimeters
        )
    }
}

public struct DerivedDriverParameters: Sendable, Hashable {
    public let complianceMetersPerNewton: Double
    public let movingMassKilograms: Double
    public let mechanicalResistanceNewtonSecondsPerMeter: Double
    public let forceFactorNewtonPerAmpere: Double
}

public struct EnclosureResponse: Sendable, Hashable {
    public let frequencyHz: Double
    public let electricalImpedance: ACComplex
    public let coneDisplacementMetersPerVolt: ACComplex
    public let coneVelocityMetersPerSecondPerVolt: ACComplex
    public let portAirVelocityMetersPerSecondPerVolt: ACComplex?
    public let acousticPressurePascalsPerVolt: ACComplex
    public let conePressurePascalsPerVolt: ACComplex
    public let portPressurePascalsPerVolt: ACComplex?
}

public struct EnclosureAlignmentMetrics: Sendable, Hashable {
    public let systemResonanceHz: Double
    public let systemQ: Double?
    public let complianceRatio: Double?
    public let portLengthCentimeters: Double?
    public let portAreaSquareCentimeters: Double?
}

public enum EnclosureSimulationError: Error, LocalizedError, Equatable {
    case invalidDriverParameters
    case invalidEnclosure
    case invalidEnvironment
    case invalidFrequency(Double)

    public var errorDescription: String? {
        switch self {
        case .invalidDriverParameters: "The driver needs finite, positive Thiele/Small parameters."
        case .invalidEnclosure: "The enclosure dimensions or tuning are invalid."
        case .invalidEnvironment: "The enclosure simulation environment is invalid."
        case .invalidFrequency(let frequency): "Invalid enclosure simulation frequency: \(frequency) Hz."
        }
    }
}

/// Linear small-signal electro-mechanical enclosure model. All motion and
/// pressure quantities are complex values per one RMS volt at the terminals.
public struct EnclosureModel: Sendable {
    public let driver: EnclosureDriverParameters
    public let enclosure: EnclosureConfiguration
    public let environment: EnclosureEnvironment
    public let derived: DerivedDriverParameters
    public let alignment: EnclosureAlignmentMetrics

    private let coneArea: Double
    private let boxVolume: Double?
    private let portArea: Double?

    public init(
        driver: EnclosureDriverParameters,
        enclosure: EnclosureConfiguration,
        environment: EnclosureEnvironment = .init()
    ) throws {
        guard driver.fsHz.isFinite, driver.fsHz > 0,
              driver.qes.isFinite, driver.qes > 0,
              driver.qms.isFinite, driver.qms > 0,
              driver.vasLiters.isFinite, driver.vasLiters > 0,
              driver.reOhms.isFinite, driver.reOhms > 0,
              driver.leMilliHenries.isFinite, driver.leMilliHenries >= 0,
              driver.sdSquareCentimeters.isFinite, driver.sdSquareCentimeters > 0,
              driver.xmaxMillimeters.isFinite, driver.xmaxMillimeters > 0 else {
            throw EnclosureSimulationError.invalidDriverParameters
        }
        guard environment.airDensityKilogramsPerCubicMeter.isFinite,
              environment.airDensityKilogramsPerCubicMeter > 0,
              environment.speedOfSoundMetersPerSecond.isFinite,
              environment.speedOfSoundMetersPerSecond > 0,
              environment.listeningDistanceMeters.isFinite,
              environment.listeningDistanceMeters > 0,
              environment.boxLossQ.isFinite, environment.boxLossQ > 0,
              environment.portLossQ.isFinite, environment.portLossQ > 0 else {
            throw EnclosureSimulationError.invalidEnvironment
        }

        let sd = driver.sdSquareCentimeters / 10_000
        let vas = driver.vasLiters / 1_000
        let omegaS = 2 * Double.pi * driver.fsHz
        let cms = vas / (environment.airDensityKilogramsPerCubicMeter
            * pow(environment.speedOfSoundMetersPerSecond, 2) * sd * sd)
        let mms = 1 / (omegaS * omegaS * cms)
        let rms = omegaS * mms / driver.qms
        let forceFactor = sqrt(driver.reOhms * omegaS * mms / driver.qes)
        guard cms.isFinite, cms > 0, mms.isFinite, mms > 0,
              rms.isFinite, rms > 0, forceFactor.isFinite, forceFactor > 0 else {
            throw EnclosureSimulationError.invalidDriverParameters
        }

        let volume: Double?
        let area: Double?
        let alignment: EnclosureAlignmentMetrics
        switch enclosure {
        case .openBaffle(let width):
            guard width.isFinite, width > 0 else { throw EnclosureSimulationError.invalidEnclosure }
            volume = nil
            area = nil
            alignment = .init(
                systemResonanceHz: driver.fsHz, systemQ: driver.qes * driver.qms / (driver.qes + driver.qms),
                complianceRatio: nil, portLengthCentimeters: nil, portAreaSquareCentimeters: nil
            )
        case .sealed(let liters):
            guard liters.isFinite, liters > 0 else { throw EnclosureSimulationError.invalidEnclosure }
            let alpha = driver.vasLiters / liters
            let qtc = driver.qes * driver.qms / (driver.qes + driver.qms) * sqrt(1 + alpha)
            volume = liters / 1_000
            area = nil
            alignment = .init(
                systemResonanceHz: driver.fsHz * sqrt(1 + alpha), systemQ: qtc,
                complianceRatio: alpha, portLengthCentimeters: nil, portAreaSquareCentimeters: nil
            )
        case .vented(let liters, let tuning, let diameter):
            guard liters.isFinite, liters > 0, tuning.isFinite, tuning > 0,
                  diameter.isFinite, diameter > 0,
                  let portLength = Self.portLengthCentimeters(
                    volumeLiters: liters, tuningHz: tuning, diameterCentimeters: diameter
                  ) else { throw EnclosureSimulationError.invalidEnclosure }
            let radiusMeters = diameter / 200
            let portAreaSquareMeters = .pi * radiusMeters * radiusMeters
            volume = liters / 1_000
            area = portAreaSquareMeters
            alignment = .init(
                systemResonanceHz: tuning, systemQ: nil,
                complianceRatio: driver.vasLiters / liters,
                portLengthCentimeters: portLength,
                portAreaSquareCentimeters: portAreaSquareMeters * 10_000
            )
        }
        self.driver = driver
        self.enclosure = enclosure
        self.environment = environment
        coneArea = sd
        boxVolume = volume
        portArea = area
        derived = .init(
            complianceMetersPerNewton: cms, movingMassKilograms: mms,
            mechanicalResistanceNewtonSecondsPerMeter: rms,
            forceFactorNewtonPerAmpere: forceFactor
        )
        self.alignment = alignment
    }

    public func response(at frequencyHz: Double) throws -> EnclosureResponse {
        guard frequencyHz.isFinite, frequencyHz > 0 else {
            throw EnclosureSimulationError.invalidFrequency(frequencyHz)
        }
        let omega = 2 * Double.pi * frequencyHz
        let jOmega = ACComplex(real: 0, imaginary: omega)
        var mechanical = ACComplex(
            real: derived.mechanicalResistanceNewtonSecondsPerMeter,
            imaginary: omega * derived.movingMassKilograms
                - 1 / (omega * derived.complianceMetersPerNewton)
        )
        var portVolumeVelocityPerConeVelocity: ACComplex?

        switch enclosure {
        case .openBaffle:
            break
        case .sealed:
            guard let boxVolume else { throw EnclosureSimulationError.invalidEnclosure }
            let compliance = boxVolume / (
                environment.airDensityKilogramsPerCubicMeter
                    * pow(environment.speedOfSoundMetersPerSecond, 2) * coneArea * coneArea
            )
            let boxSpring = ACComplex(
                real: 1 / (omega * compliance * environment.boxLossQ),
                imaginary: -1 / (omega * compliance)
            )
            mechanical = mechanical + boxSpring
        case .vented(_, let tuningHz, _):
            guard let boxVolume else { throw EnclosureSimulationError.invalidEnclosure }
            let acousticCompliance = boxVolume / (
                environment.airDensityKilogramsPerCubicMeter * pow(environment.speedOfSoundMetersPerSecond, 2)
            )
            let omegaB = 2 * Double.pi * tuningHz
            let acousticMass = 1 / (omegaB * omegaB * acousticCompliance)
            let portResistance = omegaB * acousticMass / environment.portLossQ
            let complianceImpedance = ACComplex(
                real: 1 / (omega * acousticCompliance * environment.boxLossQ),
                imaginary: -1 / (omega * acousticCompliance)
            )
            let portImpedance = ACComplex(real: portResistance, imaginary: omega * acousticMass)
            let parallel = complianceImpedance * portImpedance / (complianceImpedance + portImpedance)
            mechanical = mechanical + parallel * (coneArea * coneArea)
            portVolumeVelocityPerConeVelocity = ACComplex(real: coneArea) * complianceImpedance
                / (complianceImpedance + portImpedance)
        }

        let electrical = ACComplex(
            real: driver.reOhms,
            imaginary: omega * driver.leMilliHenries / 1_000
        )
        let forceFactor = ACComplex(real: derived.forceFactorNewtonPerAmpere)
        let impedance = electrical + forceFactor * forceFactor / mechanical
        let currentPerVolt = ACComplex(real: 1) / impedance
        let velocityPerVolt = forceFactor * currentPerVolt / mechanical
        let displacementPerVolt = velocityPerVolt / jOmega
        let coneVolumeVelocity = velocityPerVolt * coneArea
        let radiation = jOmega * environment.airDensityKilogramsPerCubicMeter
            / ACComplex(real: 2 * .pi * environment.listeningDistanceMeters)
        let conePressure = radiation * coneVolumeVelocity

        var portVelocity: ACComplex?
        var portPressure: ACComplex?
        let pressure: ACComplex
        switch enclosure {
        case .openBaffle(let width):
            let corner = environment.speedOfSoundMetersPerSecond / (4 * .pi * width)
            let dipole = ACComplex(real: 0, imaginary: frequencyHz / corner)
                / ACComplex(real: 1, imaginary: frequencyHz / corner)
            pressure = conePressure * dipole
        case .sealed:
            pressure = conePressure
        case .vented:
            guard let ratio = portVolumeVelocityPerConeVelocity, let portArea else {
                throw EnclosureSimulationError.invalidEnclosure
            }
            let portVolumeVelocity = velocityPerVolt * ratio
            portVelocity = portVolumeVelocity / ACComplex(real: portArea)
            portPressure = -(radiation * portVolumeVelocity)
            pressure = conePressure + (portPressure ?? .init(real: 0))
        }
        guard impedance.isFinite, displacementPerVolt.isFinite, pressure.isFinite else {
            throw EnclosureSimulationError.invalidDriverParameters
        }
        return .init(
            frequencyHz: frequencyHz, electricalImpedance: impedance,
            coneDisplacementMetersPerVolt: displacementPerVolt,
            coneVelocityMetersPerSecondPerVolt: velocityPerVolt,
            portAirVelocityMetersPerSecondPerVolt: portVelocity,
            acousticPressurePascalsPerVolt: pressure,
            conePressurePascalsPerVolt: conePressure,
            portPressurePascalsPerVolt: portPressure
        )
    }

    public static func portLengthCentimeters(
        volumeLiters: Double, tuningHz: Double, diameterCentimeters: Double
    ) -> Double? {
        guard volumeLiters.isFinite, volumeLiters > 0,
              tuningHz.isFinite, tuningHz > 0,
              diameterCentimeters.isFinite, diameterCentimeters > 0 else { return nil }
        let length = 23_562.5 * diameterCentimeters * diameterCentimeters
            / (tuningHz * tuningHz * volumeLiters) - 0.732 * diameterCentimeters
        return length.isFinite && length > 0 ? length : nil
    }
}

private func / (lhs: ACComplex, rhs: Double) -> ACComplex {
    ACComplex(real: lhs.real / rhs, imaginary: lhs.imaginary / rhs)
}
