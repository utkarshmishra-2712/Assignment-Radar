//
//  ThemeManager.swift
//  AssignmentRadar
//
//  Manages the user's appearance selection (Light, Dark, System)
//  with persistent storage using @AppStorage, defaulting to Light.
//

import SwiftUI
import Combine

// MARK: - App Theme Option
enum AppTheme: String, CaseIterable, Identifiable {
    case light = "Light"
    case dark = "Dark"
    case system = "System"

    var id: String { rawValue }

    /// Returns the corresponding SwiftUI ColorScheme.
    /// Returns nil for "System" so iOS dynamically controls the scheme.
    var colorScheme: ColorScheme? {
        switch self {
        case .light:
            return .light
        case .dark:
            return .dark
        case .system:
            return nil
        }
    }

    /// SF Symbol name representing each theme option.
    var iconName: String {
        switch self {
        case .light:
            return "sun.max"
        case .dark:
            return "moon"
        case .system:
            return "circle.lefthalf.filled"
        }
    }
}

// MARK: - Theme Manager
final class ThemeManager: ObservableObject {
    /// Stores the user's appearance choice in UserDefaults with @AppStorage. Defaults to Light.
    @AppStorage("user_selected_appearance") var currentTheme: AppTheme = .light {
        didSet {
            objectWillChange.send()
        }
    }

    init() {
        // Read persisted value on initialization so @AppStorage starts with the saved theme
        if let saved = UserDefaults.standard.string(forKey: "user_selected_appearance"),
           let theme = AppTheme(rawValue: saved) {
            _currentTheme = AppStorage(wrappedValue: theme, "user_selected_appearance")
        }
    }
}
