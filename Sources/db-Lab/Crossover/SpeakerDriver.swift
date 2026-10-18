import Foundation
import Combine

struct SpeakerDriver: Codable, Identifiable, Hashable {
    var id: UUID = UUID()
    var manufacturer: String
    var model: String
    var source: String
    var fsHz: Double
    var qes: Double
    var qms: Double
    var vasLiters: Double
    var reOhms: Double
    var leMilliHenries: Double
    var sdSquareCentimeters: Double
    var xmaxMillimeters: Double
    var sensitivityDb: Double
    var notes: String = ""
    var measurements: [DriverMeasurement] = []

    private enum CodingKeys: String, CodingKey {
        case id, manufacturer, model, source, fsHz, qes, qms, vasLiters
        case reOhms, leMilliHenries, sdSquareCentimeters, xmaxMillimeters
        case sensitivityDb, notes, measurements
    }

    init(
        id: UUID = UUID(),
        manufacturer: String,
        model: String,
        source: String,
        fsHz: Double,
        qes: Double,
        qms: Double,
        vasLiters: Double,
        reOhms: Double,
        leMilliHenries: Double,
        sdSquareCentimeters: Double,
        xmaxMillimeters: Double,
        sensitivityDb: Double,
        notes: String = "",
        measurements: [DriverMeasurement] = []
    ) {
        self.id = id
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

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(UUID.self, forKey: .id)
        manufacturer = try values.decode(String.self, forKey: .manufacturer)
        model = try values.decode(String.self, forKey: .model)
        source = try values.decode(String.self, forKey: .source)
        fsHz = try values.decode(Double.self, forKey: .fsHz)
        qes = try values.decode(Double.self, forKey: .qes)
        qms = try values.decode(Double.self, forKey: .qms)
        vasLiters = try values.decode(Double.self, forKey: .vasLiters)
        reOhms = try values.decode(Double.self, forKey: .reOhms)
        leMilliHenries = try values.decode(Double.self, forKey: .leMilliHenries)
        sdSquareCentimeters = try values.decode(Double.self, forKey: .sdSquareCentimeters)
        xmaxMillimeters = try values.decode(Double.self, forKey: .xmaxMillimeters)
        sensitivityDb = try values.decode(Double.self, forKey: .sensitivityDb)
        notes = try values.decodeIfPresent(String.self, forKey: .notes) ?? ""
        measurements = try values.decodeIfPresent([DriverMeasurement].self, forKey: .measurements) ?? []
    }

    var qts: Double {
        qes * qms / (qes + qms)
    }

    var displayName: String {
        "\(manufacturer) \(model)"
    }

    var validationMessage: String? {
        guard !manufacturer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return "Enter the driver manufacturer."
        }
        guard !model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return "Enter the driver model."
        }
        guard !source.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return "Record the manufacturer's datasheet or other data source."
        }
        guard fsHz.isFinite, fsHz > 0, qes.isFinite, qes > 0,
              qms.isFinite, qms > 0, vasLiters.isFinite, vasLiters > 0,
              reOhms.isFinite, reOhms > 0, leMilliHenries.isFinite, leMilliHenries >= 0,
              sdSquareCentimeters.isFinite, sdSquareCentimeters > 0,
              xmaxMillimeters.isFinite, xmaxMillimeters >= 0,
              sensitivityDb.isFinite, sensitivityDb > 0,
              qts.isFinite, qts > 0 else {
            return "Enter finite, positive driver parameters. Le and Xmax may be zero."
        }
        if measurements.contains(where: { $0.validationMessage != nil }) {
            return "Remove or correct invalid measured response or impedance data."
        }
        return nil
    }
}

@MainActor
final class DriverLibrary: ObservableObject {
    @Published private(set) var drivers: [SpeakerDriver] = []
    @Published private(set) var errorMessage: String?

    private let fileURL: URL
    private let encoder: JSONEncoder

    init(fileURL: URL? = nil) {
        self.fileURL = fileURL ?? Self.defaultFileURL()
        encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        load()
    }

    func save(_ driver: SpeakerDriver) throws {
        if let message = driver.validationMessage {
            throw DriverLibraryError.invalidDriver(message)
        }
        var updated = drivers
        if let index = updated.firstIndex(where: { $0.id == driver.id }) {
            updated[index] = driver
        } else {
            updated.append(driver)
        }
        try persist(updated)
        drivers = updated.sorted {
            $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
        }
        errorMessage = nil
    }

    func delete(_ driver: SpeakerDriver) throws {
        try persist(drivers.filter { $0.id != driver.id })
        drivers.removeAll { $0.id == driver.id }
        errorMessage = nil
    }

    func importJSON(_ data: Data) throws {
        let imported = try JSONDecoder().decode([SpeakerDriver].self, from: data)
        guard imported.allSatisfy({ $0.validationMessage == nil }) else {
            throw DriverLibraryError.invalidDriver("The imported file contains invalid driver data.")
        }
        var updated = drivers
        for driver in imported {
            if let index = updated.firstIndex(where: { $0.id == driver.id }) {
                updated[index] = driver
            } else {
                updated.append(driver)
            }
        }
        try persist(updated)
        drivers = updated.sorted {
            $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
        }
        errorMessage = nil
    }

    func exportJSON() throws -> Data {
        try encoder.encode(drivers)
    }

    func report(_ error: Error) {
        errorMessage = error.localizedDescription
    }

    private func load() {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
        do {
            let data = try Data(contentsOf: fileURL)
            let stored = try JSONDecoder().decode([SpeakerDriver].self, from: data)
            guard stored.allSatisfy({ $0.validationMessage == nil }) else {
                throw DriverLibraryError.invalidDriver("The saved driver library contains invalid data.")
            }
            drivers = stored.sorted {
                $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
            }
        } catch {
            errorMessage = "Could not load the speaker driver library: \(error.localizedDescription)"
        }
    }

    private func persist(_ drivers: [SpeakerDriver]) throws {
        do {
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try encoder.encode(drivers).write(to: fileURL, options: .atomic)
        } catch {
            throw DriverLibraryError.persistence(error.localizedDescription)
        }
    }

    private static func defaultFileURL() -> URL {
        let supportDirectory = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        )[0]
        return supportDirectory
            .appendingPathComponent("db-Lab", isDirectory: true)
            .appendingPathComponent("speaker-drivers.json")
    }
}

enum DriverLibraryError: LocalizedError {
    case invalidDriver(String)
    case persistence(String)

    var errorDescription: String? {
        switch self {
        case .invalidDriver(let message):
            message
        case .persistence(let message):
            "Could not save the speaker driver library: \(message)"
        }
    }
}
