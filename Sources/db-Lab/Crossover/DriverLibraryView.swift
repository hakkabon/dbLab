import SwiftUI
import UniformTypeIdentifiers

struct DriverLibraryView: View {
    @ObservedObject var library: DriverLibrary
    @State private var selectedDriver: SpeakerDriver?
    @State private var isEditorPresented = false
    @State private var isImporterPresented = false
    @State private var isExporterPresented = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Speaker Driver Library")
                        .font(.largeTitle.weight(.semibold))
                    Text("Manage manufacturer data and Thiele/Small parameters.")
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Import JSON", systemImage: "square.and.arrow.down") {
                    isImporterPresented = true
                }
                Button("Export JSON", systemImage: "square.and.arrow.up") {
                    isExporterPresented = true
                }
                .disabled(library.drivers.isEmpty)
                Button("Add Driver", systemImage: "plus") {
                    selectedDriver = nil
                    isEditorPresented = true
                }
                .buttonStyle(.borderedProminent)
            }

            if let errorMessage = library.errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                    .textSelection(.enabled)
            }

            if library.drivers.isEmpty {
                ContentUnavailableView(
                    "No Speaker Drivers",
                    systemImage: "speaker",
                    description: Text("Add manufacturer data manually or import a db-Lab driver-library JSON file.")
                )
            } else {
                List {
                    ForEach(library.drivers) { driver in
                        HStack(alignment: .top, spacing: 16) {
                            VStack(alignment: .leading, spacing: 5) {
                                Text(driver.displayName).font(.headline)
                                Text("Fs \(driver.fsHz.formatted(.number.precision(.significantDigits(3)))) Hz"
                                     + "  ·  Qts \(driver.qts.formatted(.number.precision(.significantDigits(3))))"
                                     + "  ·  Vas \(driver.vasLiters.formatted(.number.precision(.significantDigits(3)))) L")
                                    .font(.callout)
                                    .foregroundStyle(.secondary)
                                Text("Source: \(driver.source)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .textSelection(.enabled)
                            }
                            Spacer()
                            Button("Edit") {
                                selectedDriver = driver
                                isEditorPresented = true
                            }
                            Button(role: .destructive) {
                                do {
                                    try library.delete(driver)
                                } catch {
                                    library.report(error)
                                }
                            } label: {
                                Image(systemName: "trash")
                            }
                            .buttonStyle(.borderless)
                        }
                        .padding(.vertical, 5)
                    }
                }
                .listStyle(.inset)
            }

            Text("Library data is stored locally in Application Support. JSON import merges by driver ID; exported files contain the complete library.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(24)
        .navigationTitle("Speaker Drivers")
        .sheet(isPresented: $isEditorPresented) {
            DriverEditorView(driver: selectedDriver) { driver in
                try library.save(driver)
            }
        }
        .fileImporter(
            isPresented: $isImporterPresented,
            allowedContentTypes: [.json],
            allowsMultipleSelection: false
        ) { result in
            do {
                guard let url = try result.get().first else { return }
                let accessed = url.startAccessingSecurityScopedResource()
                defer {
                    if accessed { url.stopAccessingSecurityScopedResource() }
                }
                try library.importJSON(Data(contentsOf: url))
            } catch {
                library.report(error)
            }
        }
        .fileExporter(
            isPresented: $isExporterPresented,
            document: DriverLibraryFile(drivers: library.drivers),
            contentType: .json,
            defaultFilename: "speaker-drivers"
        ) { result in
            if case .failure(let error) = result {
                library.report(error)
            }
        }
    }
}

private struct DriverEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var draft: SpeakerDriver
    @State private var saveError: String?
    let onSave: (SpeakerDriver) throws -> Void

    init(driver: SpeakerDriver?, onSave: @escaping (SpeakerDriver) throws -> Void) {
        _draft = State(initialValue: driver ?? SpeakerDriver(
            manufacturer: "",
            model: "",
            source: "",
            fsHz: 0,
            qes: 0,
            qms: 0,
            vasLiters: 0,
            reOhms: 0,
            leMilliHenries: 0,
            sdSquareCentimeters: 0,
            xmaxMillimeters: 0,
            sensitivityDb: 0
        ))
        self.onSave = onSave
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Manufacturer data") {
                    TextField("Manufacturer", text: $draft.manufacturer)
                    TextField("Model", text: $draft.model)
                    TextField("Data source (URL or document reference)", text: $draft.source)
                    TextField("Notes", text: $draft.notes, axis: .vertical)
                        .lineLimit(2...5)
                }

                Section("Thiele/Small parameters") {
                    numberField("Fs", value: $draft.fsHz, unit: "Hz")
                    numberField("Qes", value: $draft.qes)
                    numberField("Qms", value: $draft.qms)
                    LabeledContent("Qts (calculated)") {
                        Text(draft.qts.isFinite ? draft.qts.formatted(.number.precision(.significantDigits(4))) : "—")
                            .monospacedDigit()
                    }
                    numberField("Vas", value: $draft.vasLiters, unit: "L")
                    numberField("Re", value: $draft.reOhms, unit: "Ω")
                    numberField("Le", value: $draft.leMilliHenries, unit: "mH")
                    numberField("Sd", value: $draft.sdSquareCentimeters, unit: "cm²")
                    numberField("Xmax", value: $draft.xmaxMillimeters, unit: "mm")
                    numberField("Sensitivity (2.83 V / 1 m)", value: $draft.sensitivityDb, unit: "dB")
                }

                if let message = draft.validationMessage {
                    Section {
                        Label(message, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                    }
                }
                if let saveError {
                    Section {
                        Label(saveError, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle(draft.model.isEmpty ? "Add Speaker Driver" : "Edit Speaker Driver")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        do {
                            try onSave(draft)
                            dismiss()
                        } catch {
                            saveError = error.localizedDescription
                        }
                    }
                    .disabled(draft.validationMessage != nil)
                }
            }
            .frame(minWidth: 420, minHeight: 620)
        }
    }

    private func numberField(_ title: String, value: Binding<Double>, unit: String = "") -> some View {
        LabeledContent(title) {
            HStack {
                TextField(title, value: value, format: .number.precision(.significantDigits(5)))
                    .multilineTextAlignment(.trailing)
                    .frame(maxWidth: 180)
                if !unit.isEmpty {
                    Text(unit).foregroundStyle(.secondary)
                }
            }
        }
    }
}

private struct DriverLibraryFile: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    var drivers: [SpeakerDriver]

    init(drivers: [SpeakerDriver]) {
        self.drivers = drivers
    }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }
        drivers = try JSONDecoder().decode([SpeakerDriver].self, from: data)
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return FileWrapper(regularFileWithContents: try encoder.encode(drivers))
    }
}
