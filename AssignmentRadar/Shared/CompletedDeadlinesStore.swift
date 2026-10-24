//
//  CompletedDeadlinesStore.swift
//  AssignmentRadar
//
//  Persistently tracks completed assignment identifiers per student account.
//  Ensures that when students log out and log back in, or when Moodle calendar feeds
//  re-synchronize, assignments marked as "Done" remain in the completed section.
//

import Foundation
import SwiftData

final class CompletedDeadlinesStore {
    static let shared = CompletedDeadlinesStore()

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// Derives the UserDefaults storage key for a specific Moodle account.
    /// If no account username is supplied or active, falls back to a generic device key.
    func storageKey(for account: String? = nil) -> String {
        let cleanAccount: String?
        if let account = account?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(), !account.isEmpty {
            cleanAccount = account
        } else if let active = KeychainStore.read(key: KeychainStore.moodleUsernameKey)?
            .trimmingCharacters(in: .whitespacesAndNewlines).lowercased(), !active.isEmpty {
            cleanAccount = active
        } else {
            cleanAccount = nil
        }

        if let clean = cleanAccount {
            return "assignment_radar_completed_ids_\(clean)"
        } else {
            return "assignment_radar_completed_ids_generic"
        }
    }

    /// Returns whether the given deadline item identifier was marked as complete.
    func isCompleted(id: String, forAccount account: String? = nil) -> Bool {
        let key = storageKey(for: account)
        let set = Set(defaults.stringArray(forKey: key) ?? [])
        if set.contains(id) {
            return true
        }

        // Handle possible prefix or ID format variations (e.g., event ID vs eventID@host)
        if id.contains("@") {
            let prefix = id.components(separatedBy: "@").first ?? ""
            if !prefix.isEmpty && set.contains(prefix) {
                return true
            }
        } else {
            if set.contains(where: { $0.hasPrefix("\(id)@") }) {
                return true
            }
        }

        // Check generic fallback if evaluating against an account key
        if key != "assignment_radar_completed_ids_generic" {
            let genericSet = Set(defaults.stringArray(forKey: "assignment_radar_completed_ids_generic") ?? [])
            if genericSet.contains(id) {
                return true
            }
            if id.contains("@") {
                let prefix = id.components(separatedBy: "@").first ?? ""
                if !prefix.isEmpty && genericSet.contains(prefix) {
                    return true
                }
            }
        }

        return false
    }

    /// Marks a deadline identifier as complete for the specified or currently active account.
    func markCompleted(id: String, forAccount account: String? = nil) {
        let key = storageKey(for: account)
        var set = Set(defaults.stringArray(forKey: key) ?? [])
        set.insert(id)
        if id.contains("@"), let prefix = id.components(separatedBy: "@").first, !prefix.isEmpty {
            set.insert(prefix)
        }
        defaults.set(Array(set), forKey: key)
    }

    /// Marks a deadline identifier as incomplete (e.g. Undo or deletion).
    func markIncomplete(id: String, forAccount account: String? = nil) {
        let key = storageKey(for: account)
        var set = Set(defaults.stringArray(forKey: key) ?? [])
        set = set.filter { item in
            !(item == id || item.hasPrefix("\(id)@") || (id.contains("@") && item == id.components(separatedBy: "@").first))
        }
        defaults.set(Array(set), forKey: key)

        if key != "assignment_radar_completed_ids_generic" {
            var genericSet = Set(defaults.stringArray(forKey: "assignment_radar_completed_ids_generic") ?? [])
            genericSet = genericSet.filter { item in
                !(item == id || item.hasPrefix("\(id)@") || (id.contains("@") && item == id.components(separatedBy: "@").first))
            }
            defaults.set(Array(genericSet), forKey: "assignment_radar_completed_ids_generic")
        }
    }

    /// Scans the database and persists any currently completed items for the specified or active account.
    @MainActor
    func syncExistingCompletedItems(from modelContext: ModelContext, account: String? = nil) {
        let descriptor = FetchDescriptor<DeadlineItem>()
        guard let allItems = try? modelContext.fetch(descriptor) else { return }
        for item in allItems where item.isDone {
            markCompleted(id: item.id, forAccount: account)
        }
    }
}
