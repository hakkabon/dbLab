import Foundation
import CryptoKit
import DBLabDomain

struct DriverMeasurementReference: Codable, Hashable, Sendable {
    var referenceVoltageRMS: Double?
    var referencePowerWatts: Double?
    var distanceMeters: Double?
    var angleDegrees: Double?
    var fixture: String?
    var smoothing: String?
    var phaseDescription: String?

    var domainCalibration: MeasurementCalibration {
        let level: AcousticLevelReference?
        if let referenceVoltageRMS {
            level = .voltage(rms: referenceVoltageRMS)
        } else if let referencePowerWatts {
            level = .power(watts: referencePowerWatts, nominalImpedanceOhms: 8)
        } else {
            level = nil
        }
        return MeasurementCalibration(
            acousticLevelReference: level,
            distanceMeters: distanceMeters,
            angleDegrees: angleDegrees,
            fixture: fixture,
            smoothing: smoothing,
            phaseDescription: phaseDescription
        )
    }
}

enum DriverMeasurementKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case frequencyResponse
    case impedance

    var id: String { rawValue }

    var title: String {
        switch self {
        case .frequencyResponse: "Frequency response"
        case .impedance: "Impedance"
        }
    }

    var magnitudeUnit: String {
        switch self {
        case .frequencyResponse: "dB SPL"
        case .impedance: "Ω"
        }
    }

    var extensionHint: String {
        switch self {
        case .frequencyResponse: "FRD"
        case .impedance: "ZMA"
        }
    }
}

struct DriverMeasurementPoint: Codable, Hashable, Identifiable, Sendable {
    var frequencyHz: Double
    var magnitude: Double
    var phaseDegrees: Double

    var id: Double { frequencyHz }
}

struct DriverMeasurement: Codable, Hashable, Identifiable, Sendable {
    var id = UUID()
    var kind: DriverMeasurementKind
    var sourceFileName: String
    var sourceReference: String
    var importedAt: Date
    var hasPhaseData: Bool
    var points: [DriverMeasurementPoint]
    var reference: DriverMeasurementReference? = nil
    var sourceSHA256: String? = nil
    var sourceByteCount: Int? = nil

    func normalizedMagnitude(_ magnitude: Double) -> Double {
        guard kind == .frequencyResponse,
              let gain = reference?.domainCalibration.gainDecibels() else { return magnitude }
        return magnitude + gain
    }

    var validationMessage: String? {
        guard !sourceFileName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return "The measurement source file name is missing."
        }
        guard !sourceReference.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return "Record the measurement source or conditions."
        }
        guard points.count >= 2 else {
            return "A measurement must contain at least two frequency points."
        }
        if let reference {
            if let voltage = reference.referenceVoltageRMS,
               !voltage.isFinite || voltage <= 0 {
                return "Measurement reference voltage must be positive and finite."
            }
            if let distance = reference.distanceMeters,
               !distance.isFinite || distance <= 0 {
                return "Measurement distance must be positive and finite."
            }
            if let angle = reference.angleDegrees, !angle.isFinite {
                return "Measurement angle must be finite."
            }
        }
        var previousFrequency = 0.0
        for point in points {
            guard point.frequencyHz.isFinite, point.frequencyHz > previousFrequency,
                  point.magnitude.isFinite, point.phaseDegrees.isFinite else {
                return "Measurements must contain finite values with unique, positive, increasing frequencies."
            }
            if kind == .impedance, point.magnitude <= 0 {
                return "Impedance magnitude must be greater than zero."
            }
            previousFrequency = point.frequencyHz
        }
        return nil
    }
}

enum DriverMeasurementImportError: LocalizedError {
    case emptyFile
    case fileTooLarge
    case invalidUTF8
    case missingSourceReference
    case noDataRows
    case tooManyRows
    case malformedRow(line: Int, message: String)
    case duplicateFrequency(Double)

    var errorDescription: String? {
        switch self {
        case .emptyFile:
            "The measurement file is empty."
        case .fileTooLarge:
            "Measurement files must be smaller than 20 MB."
        case .invalidUTF8:
            "The measurement file must be plain-text UTF-8."
        case .missingSourceReference:
            "Enter a source URL, reference, or measurement conditions before importing."
        case .noDataRows:
            "No measurement rows were found. Expected frequency, magnitude, and optional phase columns."
        case .tooManyRows:
            "The measurement file exceeds the 100,000-row limit."
        case .malformedRow(let line, let message):
            "Invalid measurement at line \(line): \(message)"
        case .duplicateFrequency(let frequency):
            "The measurement file contains a duplicate frequency: \(frequency) Hz."
        }
    }
}

enum DriverMeasurementParser {
    private static let maxFileBytes = 20 * 1_024 * 1_024
    private static let maxRows = 100_000

    static func parse(
        _ data: Data,
        kind: DriverMeasurementKind,
        fileName: String,
        sourceReference: String,
        importedAt: Date = Date()
    ) throws -> DriverMeasurement {
        guard !data.isEmpty else { throw DriverMeasurementImportError.emptyFile }
        guard data.count <= maxFileBytes else { throw DriverMeasurementImportError.fileTooLarge }
        guard let contents = String(data: data, encoding: .utf8) else {
            throw DriverMeasurementImportError.invalidUTF8
        }
        guard !sourceReference.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw DriverMeasurementImportError.missingSourceReference
        }

        var rows: [DriverMeasurementPoint] = []
        var rowsHavePhase: Bool?
        for (lineIndex, rawLine) in contents.components(separatedBy: .newlines).enumerated() {
            let line = rawLine
                .replacingOccurrences(of: "\u{feff}", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty,
                  !line.hasPrefix("#"),
                  !line.hasPrefix(";"),
                  !line.hasPrefix("*"),
                  !line.hasPrefix("//") else {
                continue
            }

            let columns = line
                .replacingOccurrences(of: ",", with: " ")
                .split(whereSeparator: \.isWhitespace)
            guard (2...3).contains(columns.count) else {
                if rows.isEmpty, columns.contains(where: { Double($0) == nil }) {
                    continue
                }
                throw DriverMeasurementImportError.malformedRow(
                    line: lineIndex + 1,
                    message: "Expected two or three numeric columns."
                )
            }

            let values = columns.compactMap { column -> Double? in
                let normalized = column
                    .replacingOccurrences(of: "D", with: "E")
                    .replacingOccurrences(of: "d", with: "e")
                return Double(normalized)
            }
            guard values.count == columns.count else {
                if rows.isEmpty { continue }
                throw DriverMeasurementImportError.malformedRow(
                    line: lineIndex + 1,
                    message: "Expected numeric values."
                )
            }
            guard values.allSatisfy(\.isFinite), values[0] > 0 else {
                throw DriverMeasurementImportError.malformedRow(
                    line: lineIndex + 1,
                    message: "Frequency must be positive and all values must be finite."
                )
            }
            if kind == .impedance, values[1] <= 0 {
                throw DriverMeasurementImportError.malformedRow(
                    line: lineIndex + 1,
                    message: "Impedance magnitude must be greater than zero."
                )
            }
            let hasPhase = values.count == 3
            if let rowsHavePhase, rowsHavePhase != hasPhase {
                throw DriverMeasurementImportError.malformedRow(
                    line: lineIndex + 1,
                    message: "Use the same number of columns on every data row."
                )
            }
            rowsHavePhase = hasPhase
            rows.append(DriverMeasurementPoint(
                frequencyHz: values[0],
                magnitude: values[1],
                phaseDegrees: values.count == 3 ? values[2] : 0
            ))
            guard rows.count <= maxRows else { throw DriverMeasurementImportError.tooManyRows }
        }
        guard !rows.isEmpty else { throw DriverMeasurementImportError.noDataRows }

        rows.sort { $0.frequencyHz < $1.frequencyHz }
        for (first, second) in zip(rows, rows.dropFirst()) where first.frequencyHz == second.frequencyHz {
            throw DriverMeasurementImportError.duplicateFrequency(first.frequencyHz)
        }

        let measurement = DriverMeasurement(
            kind: kind,
            sourceFileName: URL(fileURLWithPath: fileName).lastPathComponent,
            sourceReference: sourceReference.trimmingCharacters(in: .whitespacesAndNewlines),
            importedAt: importedAt,
            hasPhaseData: rowsHavePhase ?? false,
            points: rows,
            sourceSHA256: SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined(),
            sourceByteCount: data.count
        )
        if let message = measurement.validationMessage {
            throw DriverMeasurementImportError.malformedRow(line: 0, message: message)
        }
        return measurement
    }
}
