// ContentView.swift
// Root view: sidebar + detail split.

import SwiftUI

public struct ContentView: View {
    @EnvironmentObject var appState: AppState

    public init() {}

    public var body: some View {
        NavigationSplitView {
            SidebarView()
        } detail: {
            detailView
        }
        #if os(macOS)
        .frame(minWidth: 1000, minHeight: 650)
        #endif
    }

    @ViewBuilder
    private var detailView: some View {
        switch appState.selectedSidebarItem {
        case .crossover(let id):
            if let document = appState.crossoverDocument(id: id) {
                CrossoverWorkspaceView(document: document, driverLibrary: appState.driverLibrary)
            } else {
                WelcomeView()
            }
        case .driverLibrary:
            DriverLibraryView(library: appState.driverLibrary)
        case nil:
            WelcomeView()
        }
    }
}

// MARK: – Sidebar

struct SidebarView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        List(selection: $appState.selectedSidebarItem) {
            if let persistenceError = appState.persistenceError {
                Label(persistenceError, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                    .textSelection(.enabled)
            }
            Section("Library") {
                Label("Speaker Drivers", systemImage: "speaker")
                    .tag(SidebarItem.driverLibrary)
            }
            if !appState.crossoverDocuments.isEmpty {
                Section("Crossovers") {
                    ForEach(appState.crossoverDocuments) { document in
                        CrossoverSidebarRow(document: document)
                            .tag(SidebarItem.crossover(document.id))
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("db-Lab")
        .toolbar {
            ToolbarItemGroup {
                Menu {
                    Button("Crossover", action: appState.newCrossover)
                } label: {
                    Label("New", systemImage: "plus")
                }
            }
        }
    }
}

private struct CrossoverSidebarRow: View {
    @ObservedObject var document: CrossoverDocument

    var body: some View {
        Label(document.name, systemImage: "speaker.wave.2")
    }
}

// MARK: – Welcome screen

struct WelcomeView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        VStack(spacing: 32) {
            Image(systemName: "speaker.wave.2")
                .resizable()
                .scaledToFit()
                .frame(width: 80, height: 80)
                .foregroundStyle(.secondary)

            Text("db-Lab")
                .font(.largeTitle)
                .bold()

            Text("Passive Loudspeaker Crossover Designer")
                .font(.title3)
                .foregroundStyle(.secondary)

            WelcomeActionCard(
                title: "New Crossover",
                subtitle: "Set crossover targets and design a passive LCR network",
                icon: "speaker.wave.2",
                action: appState.newCrossover
            )
        }
        .padding(48)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.background)
    }
}

struct WelcomeActionCard: View {
    let title: String
    let subtitle: String
    let icon: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 12) {
                Image(systemName: icon)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 40, height: 40)
                    .foregroundStyle(Color.accentColor)

                Text(title)
                    .font(.headline)

                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(24)
            .frame(width: 240, height: 160)
            .background(.regularMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }
}
