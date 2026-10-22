import Foundation

struct CrossoverProjectSnapshot: Codable, Identifiable {
    var id: UUID
    var name: String
    var targetFrequencyHz: Double
    var wooferDriverID: UUID?
    var tweeterDriverID: UUID?
    var wooferDriverSnapshot: SpeakerDriver? = nil
    var tweeterDriverSnapshot: SpeakerDriver? = nil
    var wooferEnclosure: EnclosureType
    var tweeterEnclosure: EnclosureType
    var wooferBoxVolumeLiters: Double
    var tweeterBoxVolumeLiters: Double
    var wooferPortTuningHz: Double
    var tweeterPortTuningHz: Double
    var wooferPortDiameterCentimeters: Double
    var tweeterPortDiameterCentimeters: Double
    var wooferBaffleWidthMeters: Double
    var tweeterBaffleWidthMeters: Double
    var crossoverAlignment: CrossoverAlignment
    var crossoverOrder: Int
    var inputNetID: Int?
    var wooferOutputNetID: Int?
    var tweeterOutputNetID: Int?
    var inputNetReference: PinRef? = nil
    var wooferOutputNetReference: PinRef? = nil
    var tweeterOutputNetReference: PinRef? = nil
    var wooferFrequencyResponseID: UUID?
    var tweeterFrequencyResponseID: UUID?
    var wooferImpedanceID: UUID?
    var tweeterImpedanceID: UUID?
    var symbols: [SymbolInstance]
    var wires: [WireSegment]
}

private struct CrossoverProjectArchive: Codable {
    let schemaVersion: Int
    let projects: [CrossoverProjectSnapshot]
}

enum CrossoverProjectStoreError: LocalizedError {
    case unsupportedVersion(Int)
    case duplicateProjectID(UUID)
    case invalidArchive(String)
    case persistence(String)

    var errorDescription: String? {
        switch self {
        case .unsupportedVersion(let version):
            "Crossover project archive version \(version) is not supported."
        case .duplicateProjectID(let id):
            "Crossover project archive contains the duplicate project ID \(id)."
        case .invalidArchive(let message):
            "Crossover project archive is invalid: \(message)"
        case .persistence(let message):
            "Could not save crossover projects: \(message)"
        }
    }
}

struct CrossoverProjectStore {
    private static let currentSchemaVersion = 1
    private let fileURL: URL
    private let encoder: JSONEncoder

    init(fileURL: URL? = nil) {
        if let fileURL {
            self.fileURL = fileURL
        } else {
            let supportDirectory = FileManager.default.urls(
                for: .applicationSupportDirectory,
                in: .userDomainMask
            )[0]
            self.fileURL = supportDirectory
                .appendingPathComponent("db-Lab", isDirectory: true)
                .appendingPathComponent("crossover-projects.json")
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        self.encoder = encoder
    }

    func load() throws -> [CrossoverProjectSnapshot] {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return [] }
        let data = try Data(contentsOf: fileURL)
        let archive = try JSONDecoder().decode(CrossoverProjectArchive.self, from: data)
        guard archive.schemaVersion == Self.currentSchemaVersion else {
            throw CrossoverProjectStoreError.unsupportedVersion(archive.schemaVersion)
        }
        var ids = Set<UUID>()
        for project in archive.projects {
            guard ids.insert(project.id).inserted else {
                throw CrossoverProjectStoreError.duplicateProjectID(project.id)
            }
            guard project.targetFrequencyHz.isFinite, project.targetFrequencyHz > 0,
                  (1...4).contains(project.crossoverOrder),
                  project.crossoverAlignment != .linkwitzRiley
                    || project.crossoverOrder == 2 || project.crossoverOrder == 4 else {
                throw CrossoverProjectStoreError.invalidArchive(
                    "A project has invalid crossover frequency or filter settings."
                )
            }
        }
        return archive.projects
    }

    func save(_ projects: [CrossoverProjectSnapshot]) throws {
        let archive = CrossoverProjectArchive(
            schemaVersion: Self.currentSchemaVersion,
            projects: projects
        )
        do {
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try encoder.encode(archive).write(to: fileURL, options: .atomic)
        } catch {
            throw CrossoverProjectStoreError.persistence(error.localizedDescription)
        }
    }
}
