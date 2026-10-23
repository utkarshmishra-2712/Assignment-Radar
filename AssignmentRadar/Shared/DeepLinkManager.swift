//
//  DeepLinkManager.swift
//  AssignmentRadar
//
//  Manages custom deep link URLs (assignmentradar://import?url=...)
//  so links can be sent directly into the app, bypassing simulator clipboard issues.
//

import SwiftUI
import Combine

final class DeepLinkManager: ObservableObject {
    static let shared = DeepLinkManager()

    @Published var pendingURL: String? = nil
    @Published var shouldOpenImportSheet: Bool = false

    private init() {}

    /// Parses an incoming URL (e.g. assignmentradar://import?url=https://...)
    func handle(url: URL) {
        guard url.scheme?.lowercased() == "assignmentradar" else { return }

        // Match assignmentradar://import?url=<encoded_url>
        if url.host?.lowercased() == "import" {
            if let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
               let queryItem = components.queryItems?.first(where: { $0.name == "url" }),
               let rawURL = queryItem.value, !rawURL.isEmpty {
                DispatchQueue.main.async {
                    self.pendingURL = rawURL
                    self.shouldOpenImportSheet = true
                }
            }
        }
    }
}
