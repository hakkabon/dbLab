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
final class AppState: ObservableObject {
    @Published var crossoverDocuments: [CrossoverDocument] = []
    @Published var selectedSidebarItem: SidebarItem?
    let driverLibrary: DriverLibrary

    init(driverLibrary: DriverLibrary = DriverLibrary()) {
        self.driverLibrary = driverLibrary
    }

    // MARK: – New document factories

    func newCrossover() {
        let document = CrossoverDocument()
        crossoverDocuments.append(document)
        selectedSidebarItem = .crossover(document.id)
    }

    // MARK: – Lookup helpers

    func crossoverDocument(id: UUID) -> CrossoverDocument? {
        crossoverDocuments.first { $0.id == id }
    }

}
