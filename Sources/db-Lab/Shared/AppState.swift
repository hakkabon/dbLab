// AppState.swift
// Top-level application state and navigation model.

import SwiftUI
import Combine

enum SidebarItem: Hashable, Identifiable {
    case crossover(UUID)
    case driverLibrary

    var id: Self { self }
}

@MainActor
public final class AppState: ObservableObject {
    @Published var crossoverDocuments: [CrossoverDocument] = []
    @Published var selectedSidebarItem: SidebarItem?
    @Published private(set) var persistenceError: String?
    let driverLibrary: DriverLibrary
    private let projectStore: CrossoverProjectStore
    private var persistenceSubscriptions: [UUID: AnyCancellable] = [:]

    public convenience init() {
        self.init(driverLibrary: DriverLibrary(), projectStore: CrossoverProjectStore())
    }

    init(
        driverLibrary: DriverLibrary = DriverLibrary(),
        projectStore: CrossoverProjectStore = CrossoverProjectStore()
    ) {
        self.driverLibrary = driverLibrary
        self.projectStore = projectStore
        do {
            crossoverDocuments = try projectStore.load().map(CrossoverDocument.init(snapshot:))
            crossoverDocuments.forEach(observe)
        } catch {
            persistenceError = error.localizedDescription
        }
    }

    // MARK: – New document factories

    public func newCrossover() {
        let document = CrossoverDocument()
        crossoverDocuments.append(document)
        observe(document)
        selectedSidebarItem = .crossover(document.id)
        persistProjects()
    }

    // MARK: – Lookup helpers

    func crossoverDocument(id: UUID) -> CrossoverDocument? {
        crossoverDocuments.first { $0.id == id }
    }

    private func observe(_ document: CrossoverDocument) {
        persistenceSubscriptions[document.id] = document.objectWillChange
            .debounce(for: .milliseconds(50), scheduler: RunLoop.main)
            .sink { [weak self, weak document] _ in
                guard let self, document != nil else { return }
                self.persistProjects()
            }
    }

    private func persistProjects() {
        do {
            try projectStore.save(crossoverDocuments.map(\.snapshot))
            persistenceError = nil
        } catch {
            persistenceError = error.localizedDescription
        }
    }
}
