import Foundation

// MARK: - Measurement data and calibration

public enum MeasurementKind: String, Codable, CaseIterable, Sendable {
    case frequencyResponse
    case impedance
}

public struct MeasurementSample: Codable, Hashable, Sendable {
    public let frequencyHz: Double
    public let magnitude: Double
    public let phaseDegrees: Double

    public init(frequencyHz: Double, magnitude: Double, phaseDegrees: Double = 0) {
        self.frequencyHz = frequencyHz
        self.magnitude = magnitude
        self.phaseDegrees = phaseDegrees
    }
}

public enum AcousticLevelReference: Codable, Hashable, Sendable {
    case voltage(rms: Double)
    case power(watts: Double, nominalImpedanceOhms: Double)

    public var voltageRMS: Double? {
        switch self {
        case .voltage(let rms): return rms
        case .power(let watts, let impedance):
            guard watts.isFinite, impedance.isFinite, watts > 0, impedance > 0 else { return nil }
            return sqrt(watts * impedance)
        }
    }
}

public struct MeasurementCalibration: Codable, Hashable, Sendable {
    public var acousticLevelReference: AcousticLevelReference?
    public var distanceMeters: Double?
    public var angleDegrees: Double?
    public var fixture: String?
    public var smoothing: String?
    public var phaseDescription: String?

    public init(
        acousticLevelReference: AcousticLevelReference? = nil,
        distanceMeters: Double? = nil,
        angleDegrees: Double? = nil,
        fixture: String? = nil,
        smoothing: String? = nil,
        phaseDescription: String? = nil
    ) {
        self.acousticLevelReference = acousticLevelReference
        self.distanceMeters = distanceMeters
        self.angleDegrees = angleDegrees
        self.fixture = fixture
        self.smoothing = smoothing
        self.phaseDescription = phaseDescription
    }

    public func gainDecibels(
        targetVoltageRMS: Double = 2.83,
        targetDistanceMeters: Double = 1
    ) -> Double? {
        guard targetVoltageRMS.isFinite, targetVoltageRMS > 0,
              targetDistanceMeters.isFinite, targetDistanceMeters > 0 else { return nil }
        var gain = 0.0
        if let sourceVoltage = acousticLevelReference?.voltageRMS {
            guard sourceVoltage.isFinite, sourceVoltage > 0 else { return nil }
            gain += 20 * log10(targetVoltageRMS / sourceVoltage)
        }
        if let sourceDistance = distanceMeters {
            guard sourceDistance.isFinite, sourceDistance > 0 else { return nil }
            gain += 20 * log10(sourceDistance / targetDistanceMeters)
        }
        return gain
    }
}

public struct MeasurementDataset: Codable, Hashable, Identifiable, Sendable {
    public let id: UUID
    public let kind: MeasurementKind
    public let sourceFileName: String
    public let sourceReference: String
    public let importedAt: Date
    public let hasPhaseData: Bool
    public let samples: [MeasurementSample]
    public let calibration: MeasurementCalibration?
    public let sourceSHA256: String?
    public let sourceByteCount: Int?

    public init(
        id: UUID = UUID(),
        kind: MeasurementKind,
        sourceFileName: String,
        sourceReference: String,
        importedAt: Date,
        hasPhaseData: Bool,
        samples: [MeasurementSample],
        calibration: MeasurementCalibration? = nil,
        sourceSHA256: String? = nil,
        sourceByteCount: Int? = nil
    ) {
        self.id = id
        self.kind = kind
        self.sourceFileName = sourceFileName
        self.sourceReference = sourceReference
        self.importedAt = importedAt
        self.hasPhaseData = hasPhaseData
        self.samples = samples
        self.calibration = calibration
        self.sourceSHA256 = sourceSHA256
        self.sourceByteCount = sourceByteCount
    }

    public func normalizedAcousticSamples(
        targetVoltageRMS: Double = 2.83,
        targetDistanceMeters: Double = 1
    ) -> [MeasurementSample] {
        guard kind == .frequencyResponse,
              let gain = calibration?.gainDecibels(
                targetVoltageRMS: targetVoltageRMS,
                targetDistanceMeters: targetDistanceMeters
              ) else { return samples }
        return samples.map {
            MeasurementSample(
                frequencyHz: $0.frequencyHz,
                magnitude: $0.magnitude + gain,
                phaseDegrees: $0.phaseDegrees
            )
        }
    }
}

// MARK: - Immutable driver revisions

public struct SpeakerDriverRevision: Codable, Hashable, Identifiable, Sendable {
    public let id: UUID
    public let driverID: UUID
    public let revision: Int
    public let supersedesRevisionID: UUID?
    public let createdAt: Date
    public let manufacturer: String
    public let model: String
    public let source: String
    public let fsHz: Double
    public let qes: Double
    public let qms: Double
    public let vasLiters: Double
    public let reOhms: Double
    public let leMilliHenries: Double
    public let sdSquareCentimeters: Double
    public let xmaxMillimeters: Double
    public let sensitivityDb: Double
    public let notes: String
    public let measurements: [MeasurementDataset]

    public init(
        id: UUID = UUID(), driverID: UUID, revision: Int,
        supersedesRevisionID: UUID? = nil, createdAt: Date = Date(),
        manufacturer: String, model: String, source: String,
        fsHz: Double, qes: Double, qms: Double, vasLiters: Double,
        reOhms: Double, leMilliHenries: Double, sdSquareCentimeters: Double,
        xmaxMillimeters: Double, sensitivityDb: Double, notes: String = "",
        measurements: [MeasurementDataset] = []
    ) {
        self.id = id
        self.driverID = driverID
        self.revision = revision
        self.supersedesRevisionID = supersedesRevisionID
        self.createdAt = createdAt
        self.manufacturer = manufacturer
        self.model = model
        self.source = source
        self.fsHz = fsHz
        self.qes = qes
        self.qms = qms
        self.vasLiters = vasLiters
        self.reOhms = reOhms
        self.leMilliHenries = leMilliHenries
        self.sdSquareCentimeters = sdSquareCentimeters
        self.xmaxMillimeters = xmaxMillimeters
        self.sensitivityDb = sensitivityDb
        self.notes = notes
        self.measurements = measurements
    }

    public var qts: Double { qes * qms / (qes + qms) }
    public var displayName: String { "\(manufacturer) \(model)" }
}

public struct DriverRevisionCatalog: Codable, Hashable, Sendable {
    public private(set) var revisions: [SpeakerDriverRevision]

    public init(revisions: [SpeakerDriverRevision] = []) {
        self.revisions = revisions.sorted { ($0.driverID.uuidString, $0.revision) < ($1.driverID.uuidString, $1.revision) }
    }

    public func currentRevision(for driverID: UUID) -> SpeakerDriverRevision? {
        revisions.filter { $0.driverID == driverID }.max { $0.revision < $1.revision }
    }

    public func history(for driverID: UUID) -> [SpeakerDriverRevision] {
        revisions.filter { $0.driverID == driverID }.sorted { $0.revision < $1.revision }
    }

    public mutating func append(_ revision: SpeakerDriverRevision) throws {
        guard revision.revision > 0,
              !revisions.contains(where: { $0.id == revision.id }),
              !revisions.contains(where: {
                  $0.driverID == revision.driverID && $0.revision == revision.revision
              }) else { throw DriverRevisionError.duplicateOrInvalidRevision }
        if revision.revision > 1 {
            guard let previous = currentRevision(for: revision.driverID),
                  revision.revision == previous.revision + 1,
                  revision.supersedesRevisionID == previous.id else {
                throw DriverRevisionError.brokenRevisionChain
            }
        }
        revisions.append(revision)
    }
}

public enum DriverRevisionError: LocalizedError, Sendable {
    case duplicateOrInvalidRevision
    case brokenRevisionChain

    public var errorDescription: String? {
        switch self {
        case .duplicateOrInvalidRevision: "The driver revision is duplicated or invalid."
        case .brokenRevisionChain: "The driver revision does not extend the current revision chain."
        }
    }
}

// MARK: - N-way loudspeaker system

public enum DriverRole: String, Codable, CaseIterable, Sendable {
    case subwoofer, woofer, midrange, tweeter, superTweeter, fullRange, auxiliary
}

public enum DriverPolarity: Int, Codable, CaseIterable, Sendable {
    case normal = 1
    case inverted = -1
}

public struct AcousticPosition: Codable, Hashable, Sendable {
    public var xMeters: Double
    public var yMeters: Double
    public var zMeters: Double

    public init(xMeters: Double = 0, yMeters: Double = 0, zMeters: Double = 0) {
        self.xMeters = xMeters
        self.yMeters = yMeters
        self.zMeters = zMeters
    }
}

public struct TerminalAssignment: Codable, Hashable, Sendable {
    public var positiveNode: Int?
    public var negativeNode: Int?

    public init(positiveNode: Int? = nil, negativeNode: Int? = nil) {
        self.positiveNode = positiveNode
        self.negativeNode = negativeNode
    }
}

public enum EnclosureConfiguration: Codable, Hashable, Sendable {
    case openBaffle(widthMeters: Double)
    case sealed(netVolumeLiters: Double)
    case vented(netVolumeLiters: Double, tuningHz: Double, portDiameterCentimeters: Double)
}

public struct DriverInstance: Codable, Hashable, Identifiable, Sendable {
    public let id: UUID
    public var name: String
    public var role: DriverRole
    public var driverRevision: SpeakerDriverRevision
    public var terminals: TerminalAssignment
    public var polarity: DriverPolarity
    public var acousticPosition: AcousticPosition
    public var enclosure: EnclosureConfiguration
    public var frequencyResponseDatasetID: UUID?
    public var impedanceDatasetID: UUID?

    public init(
        id: UUID = UUID(), name: String, role: DriverRole,
        driverRevision: SpeakerDriverRevision,
        terminals: TerminalAssignment = .init(), polarity: DriverPolarity = .normal,
        acousticPosition: AcousticPosition = .init(), enclosure: EnclosureConfiguration,
        frequencyResponseDatasetID: UUID? = nil, impedanceDatasetID: UUID? = nil
    ) {
        self.id = id
        self.name = name
        self.role = role
        self.driverRevision = driverRevision
        self.terminals = terminals
        self.polarity = polarity
        self.acousticPosition = acousticPosition
        self.enclosure = enclosure
        self.frequencyResponseDatasetID = frequencyResponseDatasetID
        self.impedanceDatasetID = impedanceDatasetID
    }
}

public struct LoudspeakerSystem: Codable, Hashable, Identifiable, Sendable {
    public let id: UUID
    public var name: String
    public var referenceVoltageRMS: Double
    public var listeningPosition: AcousticPosition
    public var drivers: [DriverInstance]

    public init(
        id: UUID = UUID(), name: String, referenceVoltageRMS: Double = 2.83,
        listeningPosition: AcousticPosition = .init(zMeters: 1),
        drivers: [DriverInstance] = []
    ) {
        self.id = id
        self.name = name
        self.referenceVoltageRMS = referenceVoltageRMS
        self.listeningPosition = listeningPosition
        self.drivers = drivers
    }
}

// MARK: - Backend-neutral simulation contract

public struct FrequencySweep: Codable, Hashable, Sendable {
    public let frequenciesHz: [Double]
    public init(frequenciesHz: [Double]) { self.frequenciesHz = frequenciesHz }
}

public struct SystemSimulationRequest: Codable, Hashable, Sendable {
    public let system: LoudspeakerSystem
    public let sweep: FrequencySweep
    public init(system: LoudspeakerSystem, sweep: FrequencySweep) {
        self.system = system
        self.sweep = sweep
    }
}

public struct ComplexTraceSample: Codable, Hashable, Sendable {
    public let frequencyHz: Double
    public let real: Double
    public let imaginary: Double
    public init(frequencyHz: Double, real: Double, imaginary: Double) {
        self.frequencyHz = frequencyHz
        self.real = real
        self.imaginary = imaginary
    }
}

public struct DriverSimulationTrace: Codable, Hashable, Identifiable, Sendable {
    public let id: UUID
    public let driverInstanceID: UUID
    public let terminalVoltage: [ComplexTraceSample]
    public let current: [ComplexTraceSample]
    public let acousticPressure: [ComplexTraceSample]
    public let excursionMillimeters: [Double]?
    public init(
        id: UUID = UUID(), driverInstanceID: UUID,
        terminalVoltage: [ComplexTraceSample], current: [ComplexTraceSample],
        acousticPressure: [ComplexTraceSample], excursionMillimeters: [Double]? = nil
    ) {
        self.id = id
        self.driverInstanceID = driverInstanceID
        self.terminalVoltage = terminalVoltage
        self.current = current
        self.acousticPressure = acousticPressure
        self.excursionMillimeters = excursionMillimeters
    }
}

public struct SimulationDiagnostics: Codable, Hashable, Sendable {
    public var warnings: [String]
    public var relativeResiduals: [Double]
    public var backendIdentifier: String
    public init(warnings: [String] = [], relativeResiduals: [Double] = [], backendIdentifier: String) {
        self.warnings = warnings
        self.relativeResiduals = relativeResiduals
        self.backendIdentifier = backendIdentifier
    }
}

public struct SystemSimulationResult: Codable, Hashable, Sendable {
    public let frequenciesHz: [Double]
    public let inputImpedance: [ComplexTraceSample]
    public let combinedAcousticPressure: [ComplexTraceSample]
    public let drivers: [DriverSimulationTrace]
    public let diagnostics: SimulationDiagnostics
    public init(
        frequenciesHz: [Double], inputImpedance: [ComplexTraceSample],
        combinedAcousticPressure: [ComplexTraceSample], drivers: [DriverSimulationTrace],
        diagnostics: SimulationDiagnostics
    ) {
        self.frequenciesHz = frequenciesHz
        self.inputImpedance = inputImpedance
        self.combinedAcousticPressure = combinedAcousticPressure
        self.drivers = drivers
        self.diagnostics = diagnostics
    }
}
