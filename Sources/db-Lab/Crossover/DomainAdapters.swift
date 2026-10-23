import Foundation
import DBLabDomain

extension DriverMeasurement {
    var domainDataset: MeasurementDataset {
        let levelReference: AcousticLevelReference?
        if let voltage = reference?.referenceVoltageRMS {
            levelReference = .voltage(rms: voltage)
        } else if let power = reference?.referencePowerWatts {
            levelReference = .power(watts: power, nominalImpedanceOhms: 8)
        } else {
            levelReference = nil
        }
        return MeasurementDataset(
            id: id,
            kind: kind == .frequencyResponse ? .frequencyResponse : .impedance,
            sourceFileName: sourceFileName,
            sourceReference: sourceReference,
            importedAt: importedAt,
            hasPhaseData: hasPhaseData,
            samples: points.map {
                MeasurementSample(
                    frequencyHz: $0.frequencyHz,
                    magnitude: $0.magnitude,
                    phaseDegrees: $0.phaseDegrees
                )
            },
            calibration: MeasurementCalibration(
                acousticLevelReference: levelReference,
                distanceMeters: reference?.distanceMeters,
                angleDegrees: reference?.angleDegrees,
                fixture: reference?.fixture,
                smoothing: reference?.smoothing,
                phaseDescription: reference?.phaseDescription
            ),
            sourceSHA256: sourceSHA256,
            sourceByteCount: sourceByteCount
        )
    }
}

extension SpeakerDriver {
    var domainRevision: SpeakerDriverRevision {
        SpeakerDriverRevision(
            id: revisionID,
            driverID: id,
            revision: revision,
            supersedesRevisionID: supersedesRevisionID,
            createdAt: revisedAt,
            manufacturer: manufacturer,
            model: model,
            source: source,
            fsHz: fsHz,
            qes: qes,
            qms: qms,
            vasLiters: vasLiters,
            reOhms: reOhms,
            leMilliHenries: leMilliHenries,
            sdSquareCentimeters: sdSquareCentimeters,
            xmaxMillimeters: xmaxMillimeters,
            sensitivityDb: sensitivityDb,
            notes: notes,
            measurements: measurements.map(\.domainDataset)
        )
    }
}
