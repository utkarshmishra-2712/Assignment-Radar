//
//  AssignmentRadarApp.swift
//  AssignmentRadar
//
//  Application entry point. Configures the ThemeManager,
//  the active ColorScheme, and the SwiftData container.
//

import SwiftUI
import SwiftData

@main
struct AssignmentRadarApp: App {
    @StateObject private var themeManager = ThemeManager()

    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            DeadlineItem.self,
        ])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            MainView()
                .environmentObject(themeManager)
                .preferredColorScheme(themeManager.currentTheme.colorScheme)
                .appRoundedFont()
                .onOpenURL { url in
                    DeepLinkManager.shared.handle(url: url)
                }
        }
        .modelContainer(sharedModelContainer)
    }
}
