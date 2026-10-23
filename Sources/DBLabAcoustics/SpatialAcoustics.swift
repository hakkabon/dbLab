import Foundation
import DBLabDomain
import DBLabNumeric
import NumericCore

public struct SpatialSource: Sendable, Hashable {
    public let id: String
    public let position: AcousticPosition
    public let radiatingDiameterMeters: Double
    public let pressureAtOneMeter: [ComplexTraceSample]

    public init(
        id: String,
        position: AcousticPosition,
        radiatingDiameterMeters: Double,
        pressureAtOneMeter: [ComplexTraceSample]
    ) {
        self.id = id
        self.position = position
        self.radiatingDiameterMeters = radiatingDiameterMeters
        self.pressureAtOneMeter = pressureAtOneMeter
    }
}

public struct SpatialAcousticsOptions: Sendable, Hashable {
    public var listeningDistanceMeters: Double
    public var listeningAngleDegrees: Double
    public var listenerHeightMeters: Double
    public var acousticCenterHeightMeters: Double
    public var speedOfSoundMetersPerSecond: Double
    public var airAbsorptionDecibelsPerMeterAt10kHz: Double
    public var floorReflectionCoefficient: Double
    public var polarAngleStepDegrees: Double
    public var polarFrequenciesHz: [Double]

    public init(
        listeningDistanceMeters: Double = 2,
        listeningAngleDegrees: Double = 0,
        listenerHeightMeters: Double = 1,
        acousticCenterHeightMeters: Double = 1,
        speedOfSoundMetersPerSecond: Double = 343,
        airAbsorptionDecibelsPerMeterAt10kHz: Double = 0,
        floorReflectionCoefficient: Double = 0,
        polarAngleStepDegrees: Double = 10,
        polarFrequenciesHz: [Double] = [500, 1_000, 2_000, 4_000, 8_000]
    ) {
        self.listeningDistanceMeters = listeningDistanceMeters
        self.listeningAngleDegrees = listeningAngleDegrees
        self.listenerHeightMeters = listenerHeightMeters
        self.acousticCenterHeightMeters = acousticCenterHeightMeters
        self.speedOfSoundMetersPerSecond = speedOfSoundMetersPerSecond
        self.airAbsorptionDecibelsPerMeterAt10kHz = airAbsorptionDecibelsPerMeterAt10kHz
        self.floorReflectionCoefficient = floorReflectionCoefficient
        self.polarAngleStepDegrees = polarAngleStepDegrees
        self.polarFrequenciesHz = polarFrequenciesHz
    }
}

public struct SpatialResponsePoint: Sendable, Hashable, Identifiable {
    public var id: Double { frequencyHz }
    public let frequencyHz: Double
    public let pressure: ACComplex
    public let soundPressureLevelDecibels: Double
}

public struct PolarResponsePoint: Sendable, Hashable, Identifiable {
    public var id: String { "\(frequencyHz)-\(angleDegrees)" }
    public let frequencyHz: Double
    public let angleDegrees: Double
    public let relativeLevelDecibels: Double
}

public struct SpatialAcousticsResult: Sendable, Hashable {
    public let listeningResponse: [SpatialResponsePoint]
    public let polarResponse: [PolarResponsePoint]
    public let listeningWindowResponse: [SpatialResponsePoint]
    public let soundPowerResponse: [SpatialResponsePoint]
    public let directivityIndexDecibels: [Double]
}

public enum SpatialAcousticsError: LocalizedError, Equatable {
    case invalidOptions(String)
    case invalidSource(String)
    case mismatchedFrequencyGrid

    public var errorDescription: String? {
        switch self {
        case .invalidOptions(let message): "Invalid spatial-acoustics options: \(message)."
        case .invalidSource(let id): "Spatial source \(id) has invalid geometry or response data."
        case .mismatchedFrequencyGrid: "All spatial sources must use the same increasing frequency grid."
        }
    }
}

public enum SpatialAcousticsSimulator {
    public static func simulate(
        sources: [SpatialSource],
        options: SpatialAcousticsOptions = .init()
    ) throws -> SpatialAcousticsResult {
        try validate(sources: sources, options: options)
        let frequencies = sources[0].pressureAtOneMeter.map(\.frequencyHz)
        let listening = response(sources: sources, frequencies: frequencies, angleDegrees: options.listeningAngleDegrees, options: options)

        let polarAngles = stride(from: -90.0, through: 90.0, by: options.polarAngleStepDegrees).map { $0 }
        var polar: [PolarResponsePoint] = []
        for target in options.polarFrequenciesHz where target >= frequencies[0] && target <= frequencies.last! {
            let index = nearestIndex(to: target, in: frequencies)
            let onAxis = response(sources: sources, frequencyIndex: index, angleDegrees: 0, options: options).magnitude
            for angle in polarAngles {
                let magnitude = response(sources: sources, frequencyIndex: index, angleDegrees: angle, options: options).magnitude
                polar.append(.init(
                    frequencyHz: frequencies[index], angleDegrees: angle,
                    relativeLevelDecibels: 20 * log10(max(magnitude / max(onAxis, 1e-15), 1e-12))
                ))
            }
        }

        let integrationAngles = stride(from: -90.0, through: 90.0, by: 5.0).map { $0 }
        let windowAngles = [-30.0, -15, 0, 15, 30]
        var window: [SpatialResponsePoint] = []
        var power: [SpatialResponsePoint] = []
        var directivity: [Double] = []
        for index in frequencies.indices {
            let windowMeanSquare = windowAngles.map {
                pow(response(sources: sources, frequencyIndex: index, angleDegrees: $0, options: options).magnitude, 2)
            }.reduce(0, +) / Double(windowAngles.count)
            var weightedPower = 0.0
            var weight = 0.0
            for angle in integrationAngles {
                let w = max(cos(angle * .pi / 180), 0)
                let p = response(sources: sources, frequencyIndex: index, angleDegrees: angle, options: options).magnitude
                weightedPower += w * p * p
                weight += w
            }
            let powerMeanSquare = weightedPower / max(weight, 1e-15)
            let windowPressure = sqrt(windowMeanSquare)
            let powerPressure = sqrt(powerMeanSquare)
            window.append(point(frequency: frequencies[index], pressure: ACComplex(real: windowPressure)))
            power.append(point(frequency: frequencies[index], pressure: ACComplex(real: powerPressure)))
            directivity.append(10 * log10(max(windowMeanSquare / max(powerMeanSquare, 1e-30), 1e-12)))
        }
        return .init(
            listeningResponse: listening, polarResponse: polar,
            listeningWindowResponse: window, soundPowerResponse: power,
            directivityIndexDecibels: directivity
        )
    }

    private static func validate(sources: [SpatialSource], options: SpatialAcousticsOptions) throws {
        guard options.listeningDistanceMeters.isFinite, options.listeningDistanceMeters > 0,
              options.listeningAngleDegrees.isFinite, abs(options.listeningAngleDegrees) <= 90,
              options.listenerHeightMeters.isFinite, options.listenerHeightMeters >= 0,
              options.acousticCenterHeightMeters.isFinite, options.acousticCenterHeightMeters >= 0,
              options.speedOfSoundMetersPerSecond.isFinite, options.speedOfSoundMetersPerSecond > 0,
              options.airAbsorptionDecibelsPerMeterAt10kHz.isFinite, options.airAbsorptionDecibelsPerMeterAt10kHz >= 0,
              options.floorReflectionCoefficient.isFinite, abs(options.floorReflectionCoefficient) <= 1,
              options.polarAngleStepDegrees.isFinite, options.polarAngleStepDegrees >= 1, options.polarAngleStepDegrees <= 45 else {
            throw SpatialAcousticsError.invalidOptions("distance, angles, environment, or reflection coefficient")
        }
        guard let first = sources.first, first.pressureAtOneMeter.count >= 2 else {
            throw SpatialAcousticsError.invalidSource(sources.first?.id ?? "unknown")
        }
        let grid = first.pressureAtOneMeter.map(\.frequencyHz)
        guard zip(grid, grid.dropFirst()).allSatisfy({ $0 > 0 && $0 < $1 }) else {
            throw SpatialAcousticsError.invalidSource(first.id)
        }
        for source in sources {
            guard source.radiatingDiameterMeters.isFinite, source.radiatingDiameterMeters > 0,
                  source.position.xMeters.isFinite, source.position.yMeters.isFinite, source.position.zMeters.isFinite,
                  source.pressureAtOneMeter.allSatisfy({ $0.real.isFinite && $0.imaginary.isFinite }) else {
                throw SpatialAcousticsError.invalidSource(source.id)
            }
            guard source.pressureAtOneMeter.map(\.frequencyHz) == grid else {
                throw SpatialAcousticsError.mismatchedFrequencyGrid
            }
        }
    }

    private static func response(
        sources: [SpatialSource], frequencies: [Double], angleDegrees: Double,
        options: SpatialAcousticsOptions
    ) -> [SpatialResponsePoint] {
        frequencies.indices.map { index in
            point(
                frequency: frequencies[index],
                pressure: response(sources: sources, frequencyIndex: index, angleDegrees: angleDegrees, options: options)
            )
        }
    }

    private static func response(
        sources: [SpatialSource], frequencyIndex: Int, angleDegrees: Double,
        options: SpatialAcousticsOptions
    ) -> ACComplex {
        let angle = angleDegrees * .pi / 180
        let listener = AcousticPosition(
            xMeters: options.listeningDistanceMeters * sin(angle),
            yMeters: options.listenerHeightMeters - options.acousticCenterHeightMeters,
            zMeters: options.listeningDistanceMeters * cos(angle)
        )
        var total = ACComplex(real: 0)
        for source in sources {
            let frequency = source.pressureAtOneMeter[frequencyIndex].frequencyHz
            let pressure = ACComplex(
                real: source.pressureAtOneMeter[frequencyIndex].real,
                imaginary: source.pressureAtOneMeter[frequencyIndex].imaginary
            )
            total = total + propagated(
                pressure: pressure, source: source, listener: listener,
                frequencyHz: frequency, options: options, reflected: false
            )
            if options.floorReflectionCoefficient != 0 {
                total = total + propagated(
                    pressure: pressure, source: source, listener: listener,
                    frequencyHz: frequency, options: options, reflected: true
                ) * options.floorReflectionCoefficient
            }
        }
        return total
    }

    private static func propagated(
        pressure: ACComplex, source: SpatialSource, listener: AcousticPosition,
        frequencyHz: Double, options: SpatialAcousticsOptions, reflected: Bool
    ) -> ACComplex {
        let sourceY: Double
        if reflected {
            sourceY = -2 * options.acousticCenterHeightMeters - source.position.yMeters
        } else {
            sourceY = source.position.yMeters
        }
        let dx = listener.xMeters - source.position.xMeters
        let dy = listener.yMeters - sourceY
        let dz = listener.zMeters - source.position.zMeters
        let distance = max(sqrt(dx * dx + dy * dy + dz * dz), 1e-6)
        let axialDistance = max(abs(dz), 1e-12)
        let offAxisAngle = atan2(sqrt(dx * dx + dy * dy), axialDistance)
        let waveNumber = 2 * Double.pi * frequencyHz / options.speedOfSoundMetersPerSecond
        let pistonArgument = waveNumber * source.radiatingDiameterMeters * 0.5 * sin(offAxisAngle)
        let directivity = circularPistonDirectivity(pistonArgument)
        let absorptionDB = options.airAbsorptionDecibelsPerMeterAt10kHz
            * pow(frequencyHz / 10_000, 2) * distance
        let attenuation = directivity / distance * pow(10, -absorptionDB / 20)
        return pressure * ACComplex.polar(magnitude: attenuation, phaseRadians: -waveNumber * distance)
    }

    private static func circularPistonDirectivity(_ x: Double) -> Double {
        let ax = abs(x)
        guard ax > 1e-7 else { return 1 }
        return abs(2 * SpecialFunctions.besselJ1(ax) / ax)
    }

    private static func nearestIndex(to target: Double, in values: [Double]) -> Int {
        values.indices.min { abs(values[$0] - target) < abs(values[$1] - target) } ?? 0
    }

    private static func point(frequency: Double, pressure: ACComplex) -> SpatialResponsePoint {
        .init(
            frequencyHz: frequency, pressure: pressure,
            soundPressureLevelDecibels: 20 * log10(max(pressure.magnitude / 20e-6, 1e-12))
        )
    }
}
