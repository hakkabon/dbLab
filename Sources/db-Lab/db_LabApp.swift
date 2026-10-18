// db_LabApp.swift
// db-Lab — passive loudspeaker crossover design app.
//
// Entry point: this file contains the @main App struct.
// Swift requires exactly one file named "main.swift" OR one @main struct
// in an executable target. We use @main here.

import SwiftUI

@main
struct DbLabApp: App {
    @StateObject private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appState)
        }
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Crossover") {
                    appState.newCrossover()
                }
                .keyboardShortcut("n", modifiers: [.command])
            }
        }
    }
}
