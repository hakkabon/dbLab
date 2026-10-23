import Foundation
import DBLabDomain
import DBLabNumeric

public struct LargeSignalDriverParameters: Sendable, Hashable, Codable {
    public let driverInstanceID: UUID
    public var dcResistanceOhms: Double
    public var xmaxMillimeters: Double
    public var thermalResistanceKelvinPerWatt: Double
    public var thermalTimeConstantSeconds: Double
    public var maximumCoilTemperatureCelsius: Double
    public var resistanceTemperatureCoefficientPerKelvin: Double
    public var motorNonlinearity: Double
    public var suspensionNonlinearity: Double

    public init(
        driverInstanceID: UUID, dcResistanceOhms: Double, xmaxMillimeters: Double,
        thermalResistanceKelvinPerWatt: Double = 2.5,
        thermalTimeConstantSeconds: Double = 45,
        maximumCoilTemperatureCelsius: Double = 180,
        resistanceTemperatureCoefficientPerKelvin: Double = 0.00393,
        motorNonlinearity: Double = 0.35,
        suspensionNonlinearity: Double = 0.25
    ) {
        self.driverInstanceID = driverInstanceID
        self.dcResistanceOhms = dcResistanceOhms
        self.xmaxMillimeters = xmaxMillimeters
        self.thermalResistanceKelvinPerWatt = thermalResistanceKelvinPerWatt
        self.thermalTimeConstantSeconds = thermalTimeConstantSeconds
        self.maximumCoilTemperatureCelsius = maximumCoilTemperatureCelsius
        self.resistanceTemperatureCoefficientPerKelvin = resistanceTemperatureCoefficientPerKelvin
        self.motorNonlinearity = motorNonlinearity
        self.suspensionNonlinearity = suspensionNonlinearity
    }
}

public struct LargeSignalOptions: Sendable, Hashable, Codable {
    public var inputVoltagesRMS: [Double]
    public var stimulusDurationSeconds: Double
    public var ambientTemperatureCelsius: Double
    public var maximumPortMach: Double
    public var speedOfSoundMetersPerSecond: Double

    public init(
        inputVoltagesRMS: [Double] = [2.83, 5.66, 11.3, 16, 22.6, 32],
        stimulusDurationSeconds: Double = 60,
        ambientTemperatureCelsius: Double = 20,
        maximumPortMach: Double = 0.10,
        speedOfSoundMetersPerSecond: Double = 343
    ) {
        self.inputVoltagesRMS = inputVoltagesRMS
        self.stimulusDurationSeconds = stimulusDurationSeconds
        self.ambientTemperatureCelsius = ambientTemperatureCelsius
        self.maximumPortMach = maximumPortMach
        self.speedOfSoundMetersPerSecond = speedOfSoundMetersPerSecond
    }
}

public enum LargeSignalLimit: String, Sendable, Hashable, Codable {
    case none = "No modeled limit"
    case excursion = "Excursion"
    case voiceCoilTemperature = "Voice-coil temperature"
    case portVelocity = "Vent velocity"
}

public struct LargeSignalFrequencyPoint: Sendable, Hashable, Identifiable {
    public var id: Double { frequencyHz }
    public let frequencyHz: Double
    public let outputLevelDecibels: Double
    public let compressionDecibels: Double
    public let estimatedTHDPercent: Double
    public let excursionMillimeters: Double
    public let portMach: Double?
}

public struct LargeSignalDriverResult: Sendable, Hashable, Identifiable {
    public var id: UUID { driverInstanceID }
    public let driverInstanceID: UUID
    public let coilTemperatureCelsius: Double
    public let hotResistanceOhms: Double
    public let dissipatedPowerWatts: Double
    public let maximumExcursionRatio: Double
    public let maximumPortMach: Double?
    public let response: [LargeSignalFrequencyPoint]
}

public struct LargeSignalOperatingPoint: Sendable, Hashable, Identifiable {
    public var id: Double { inputVoltageRMS }
    public let inputVoltageRMS: Double
    public let nominalPowerWatts: Double
    public let peakOutputLevelDecibels: Double
    public let maximumCompressionDecibels: Double
    public let limitingMechanism: LargeSignalLimit
    public let drivers: [LargeSignalDriverResult]
}

public struct LargeSignalResult: Sendable, Hashable {
    public let operatingPoints: [LargeSignalOperatingPoint]
    public let maximumSafeInputVoltageRMS: Double
    public let maximumSafeNominalPowerWatts: Double
    public let firstLimitingMechanism: LargeSignalLimit
    public let referenceVoltageRMS: Double
    public let iterations: Int
    public let backendIdentifier: String
}

public enum LargeSignalSimulationError: LocalizedError, Equatable {
    case invalidOptions
    case invalidDriver(UUID)
    case missingDriverTrace(UUID)
    case inconsistentTrace

    public var errorDescription: String? {
        switch self {
        case .invalidOptions: "Large-signal voltage, thermal, or environment settings are invalid."
        case .invalidDriver(let id): "Large-signal parameters are invalid for driver \(id)."
        case .missingDriverTrace(let id): "The small-signal result has no trace for driver \(id)."
        case .inconsistentTrace: "The small-signal result contains inconsistent frequency traces."
        }
    }
}

public enum LargeSignalSimulator {
    public static func simulate(
        smallSignal: SystemSimulationResult,
        drivers: [LargeSignalDriverParameters],
        options: LargeSignalOptions = .init(),
        referenceVoltageRMS: Double = 2.83
    ) throws -> LargeSignalResult {
        try validate(smallSignal: smallSignal, drivers: drivers, options: options, referenceVoltage: referenceVoltageRMS)
        var operatingPoints: [LargeSignalOperatingPoint] = []
        var safeVoltage = 0.0
        var safePower = 0.0
        var firstLimit: LargeSignalLimit = .none
        var totalIterations = 0

        for voltage in options.inputVoltagesRMS.sorted() {
            try Task.checkCancellation()
            let scale = voltage / referenceVoltageRMS
            var driverResults: [LargeSignalDriverResult] = []
            var pointLimit: LargeSignalLimit = .none
            var maximumCompression = 0.0
            var peakOutput = -240.0

            for parameters in drivers {
                guard let trace = smallSignal.drivers.first(where: { $0.driverInstanceID == parameters.driverInstanceID }) else {
                    throw LargeSignalSimulationError.missingDriverTrace(parameters.driverInstanceID)
                }
                let currents = trace.current.map { hypot($0.real, $0.imaginary) * scale }
                let meanCurrentSquared = currents.map { $0 * $0 }.reduce(0, +) / Double(currents.count)
                let coldPower = meanCurrentSquared * parameters.dcResistanceOhms
                let thermal = thermalState(coldPowerWatts: coldPower, parameters: parameters, options: options)
                totalIterations += thermal.iterations
                let thermalGain = parameters.dcResistanceOhms / thermal.hotResistance

                var response: [LargeSignalFrequencyPoint] = []
                var maximumExcursionRatio = 0.0
                var maximumPortMach: Double?
                for index in smallSignal.frequenciesHz.indices {
                    let excursion = (trace.excursionMillimeters?[index] ?? 0) * scale * thermalGain
                    let ratio = excursion / parameters.xmaxMillimeters
                    maximumExcursionRatio = max(maximumExcursionRatio, ratio)
                    let overLinear = max(0, ratio - 0.7)
                    let motorGain = 1 / (1 + parameters.motorNonlinearity * overLinear * overLinear)
                    let suspensionGain = 1 / sqrt(1 + parameters.suspensionNonlinearity * pow(max(ratio, 0), 4))
                    let velocity = trace.portAirVelocityMetersPerSecond?[index]
                    let mach = velocity.map { $0 * scale * thermalGain / options.speedOfSoundMetersPerSecond }
                    if let mach { maximumPortMach = max(maximumPortMach ?? 0, mach) }
                    let portGain = mach.map { 1 / sqrt(1 + pow($0 / options.maximumPortMach, 4)) } ?? 1
                    let nonlinearGain = thermalGain * motorGain * suspensionGain * portGain
                    let compression = max(0, -20 * log10(max(nonlinearGain, 1e-12)))
                    maximumCompression = max(maximumCompression, compression)
                    let pressure = trace.acousticPressure[index]
                    let linearLevel = 20 * log10(max(hypot(pressure.real, pressure.imaginary) * scale, 1e-12))
                    let outputLevel = linearLevel - compression
                    peakOutput = max(peakOutput, outputLevel)
                    let thd = min(100, 100 * sqrt(max(0, 1 - motorGain * suspensionGain)))
                    response.append(.init(
                        frequencyHz: smallSignal.frequenciesHz[index], outputLevelDecibels: outputLevel,
                        compressionDecibels: compression, estimatedTHDPercent: thd,
                        excursionMillimeters: excursion, portMach: mach
                    ))
                }
                if thermal.temperature >= parameters.maximumCoilTemperatureCelsius {
                    pointLimit = .voiceCoilTemperature
                } else if maximumExcursionRatio >= 1, pointLimit == .none {
                    pointLimit = .excursion
                } else if (maximumPortMach ?? 0) >= options.maximumPortMach, pointLimit == .none {
                    pointLimit = .portVelocity
                }
                driverResults.append(.init(
                    driverInstanceID: parameters.driverInstanceID,
                    coilTemperatureCelsius: thermal.temperature,
                    hotResistanceOhms: thermal.hotResistance,
                    dissipatedPowerWatts: thermal.power,
                    maximumExcursionRatio: maximumExcursionRatio,
                    maximumPortMach: maximumPortMach,
                    response: response
                ))
            }
            let nominalResistance = drivers.map(\.dcResistanceOhms).min() ?? 8
            let nominalPower = voltage * voltage / nominalResistance
            operatingPoints.append(.init(
                inputVoltageRMS: voltage, nominalPowerWatts: nominalPower,
                peakOutputLevelDecibels: peakOutput, maximumCompressionDecibels: maximumCompression,
                limitingMechanism: pointLimit, drivers: driverResults
            ))
            if pointLimit == .none {
                safeVoltage = voltage
                safePower = nominalPower
            } else if firstLimit == .none {
                firstLimit = pointLimit
            }
        }
        return .init(
            operatingPoints: operatingPoints, maximumSafeInputVoltageRMS: safeVoltage,
            maximumSafeNominalPowerWatts: safePower, firstLimitingMechanism: firstLimit,
            referenceVoltageRMS: referenceVoltageRMS, iterations: totalIterations,
            backendIdentifier: "numeric-core-operating-point/v1"
        )
    }

    private static func thermalState(
        coldPowerWatts: Double, parameters: LargeSignalDriverParameters,
        options: LargeSignalOptions
    ) -> (temperature: Double, hotResistance: Double, power: Double, iterations: Int) {
        let transientFraction = 1 - exp(-options.stimulusDurationSeconds / parameters.thermalTimeConstantSeconds)
        var rise = 0.0
        var iterations = 0
        for iteration in 1...40 {
            let resistanceRatio = 1 + parameters.resistanceTemperatureCoefficientPerKelvin * rise
            let power = coldPowerWatts / max(resistanceRatio, 1e-12)
            let next = power * parameters.thermalResistanceKelvinPerWatt * transientFraction
            iterations = iteration
            if abs(next - rise) < 1e-8 { rise = next; break }
            rise = 0.5 * (rise + next)
        }
        let hotResistance = parameters.dcResistanceOhms
            * (1 + parameters.resistanceTemperatureCoefficientPerKelvin * rise)
        let power = coldPowerWatts * parameters.dcResistanceOhms / hotResistance
        return (options.ambientTemperatureCelsius + rise, hotResistance, power, iterations)
    }

    private static func validate(
        smallSignal: SystemSimulationResult, drivers: [LargeSignalDriverParameters],
        options: LargeSignalOptions, referenceVoltage: Double
    ) throws {
        guard referenceVoltage.isFinite, referenceVoltage > 0,
              !options.inputVoltagesRMS.isEmpty,
              options.inputVoltagesRMS.allSatisfy({ $0.isFinite && $0 > 0 }),
              Set(options.inputVoltagesRMS).count == options.inputVoltagesRMS.count,
              options.stimulusDurationSeconds.isFinite, options.stimulusDurationSeconds > 0,
              options.ambientTemperatureCelsius.isFinite,
              options.maximumPortMach.isFinite, options.maximumPortMach > 0,
              options.speedOfSoundMetersPerSecond.isFinite, options.speedOfSoundMetersPerSecond > 0,
              !drivers.isEmpty else { throw LargeSignalSimulationError.invalidOptions }
        let count = smallSignal.frequenciesHz.count
        guard count > 1,
              zip(smallSignal.frequenciesHz, smallSignal.frequenciesHz.dropFirst()).allSatisfy({ $0 > 0 && $0 < $1 }),
              Set(drivers.map(\.driverInstanceID)).count == drivers.count,
              smallSignal.drivers.allSatisfy({
            $0.current.count == count && $0.acousticPressure.count == count
                && ($0.excursionMillimeters?.count ?? count) == count
                && ($0.portAirVelocityMetersPerSecond?.count ?? count) == count
        }) else { throw LargeSignalSimulationError.inconsistentTrace }
        for driver in drivers {
            guard driver.dcResistanceOhms.isFinite, driver.dcResistanceOhms > 0,
                  driver.xmaxMillimeters.isFinite, driver.xmaxMillimeters > 0,
                  driver.thermalResistanceKelvinPerWatt.isFinite, driver.thermalResistanceKelvinPerWatt > 0,
                  driver.thermalTimeConstantSeconds.isFinite, driver.thermalTimeConstantSeconds > 0,
                  driver.maximumCoilTemperatureCelsius.isFinite,
                  driver.maximumCoilTemperatureCelsius > options.ambientTemperatureCelsius,
                  driver.resistanceTemperatureCoefficientPerKelvin.isFinite, driver.resistanceTemperatureCoefficientPerKelvin >= 0,
                  driver.motorNonlinearity.isFinite, driver.motorNonlinearity >= 0,
                  driver.suspensionNonlinearity.isFinite, driver.suspensionNonlinearity >= 0 else {
                throw LargeSignalSimulationError.invalidDriver(driver.driverInstanceID)
            }
        }
    }
}
