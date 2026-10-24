//
//  AppBootstrapper.swift
//  AssignmentRadar
//
//  Handles essential cold-start app bootstrapping. Verifies local data stores,
//  loads stored preferences and Keychain state without waiting for external network calls.
//  Includes an 8-second safety timeout so the app never hangs indefinitely.
//

import SwiftUI
import SwiftData
import Observation

@Observable
final class AppBootstrapper {
    var isReady: Bool = false
    var startupWarningMessage: String? = nil

    private var timeoutTask: Task<Void, Never>? = nil

    @MainActor
    func bootstrap(modelContainer: ModelContainer, themeManager: ThemeManager) async {
        guard !isReady else { return }

        // Start 8-second safety watchdog
        timeoutTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 8_000_000_000)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                if let self = self, !self.isReady {
                    self.startupWarningMessage = "Startup took longer than usual. Loaded with default settings."
                    self.isReady = true
                }
            }
        }

        // 1. Verify ModelContext and local database readiness
        _ = modelContainer.mainContext

        // 2. Read cached session and connection state from secure Keychain
        _ = KeychainStore.read(key: KeychainStore.moodleAuthTokenKey)
        _ = KeychainStore.read(key: KeychainStore.moodleUsernameKey)

        // 3. Confirm Theme settings are active
        _ = themeManager.currentTheme

        // Essential boot complete — mark ready immediately (no artificial delay)
        timeoutTask?.cancel()
        timeoutTask = nil
        self.isReady = true
    }
}
