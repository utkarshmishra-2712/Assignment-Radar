//
//  ContestRepository.swift
//  AssignmentRadar
//
//  Coordinates parallel multi-platform contest fetching, SwiftData caching,
//  idempotent upserts, cleanup of ended contests, and quiet status banners.
//

import Foundation
import SwiftData
import SwiftUI
import Observation

@Observable
@MainActor
final class ContestRepository {
    static let shared = ContestRepository()

    var isRefreshing: Bool = false
    var showUpdatedNotice: Bool = false
    var unavailablePlatformNotice: String? = nil

    private var lastRefreshTime: Date? = nil
    private let refreshCooldownInterval: TimeInterval = 15 * 60 // 15 minutes

    private let sources: [ContestSource] = [
        CodeforcesSource(),
        CodeChefSource(),
        LeetCodeSource(),
        AtCoderSource()
    ]

    func refreshIfNeeded(modelContext: ModelContext, force: Bool = false) async {
        let now = Date()
        if !force, let last = lastRefreshTime, now.timeIntervalSince(last) < refreshCooldownInterval {
            return
        }

        guard !isRefreshing else { return }
        isRefreshing = true
        unavailablePlatformNotice = nil

        var fetchedLists: [CodingPlatform: [ContestItem]] = [:]
        var failedPlatforms: [CodingPlatform] = []

        await withTaskGroup(of: (CodingPlatform, Result<[ContestItem], Error>).self) { group in
            for source in sources {
                group.addTask {
                    do {
                        let items = try await source.fetchContests()
                        return (source.platform, .success(items))
                    } catch {
                        return (source.platform, .failure(error))
                    }
                }
            }

            for await (platform, result) in group {
                switch result {
                case .success(let items):
                    fetchedLists[platform] = items
                case .failure:
                    failedPlatforms.append(platform)
                }
            }
        }

        // Fetch existing cached records from SwiftData
        let descriptor = FetchDescriptor<ContestItem>()
        let existingItems = (try? modelContext.fetch(descriptor)) ?? []
        var existingByID: [String: ContestItem] = [:]
        for item in existingItems {
            existingByID[item.id] = item
        }

        // Upsert all fetched items
        for (_, items) in fetchedLists {
            for newItem in items {
                if let existing = existingByID[newItem.id] {
                    // Update in-place to preserve calendarEventID
                    existing.name = newItem.name
                    existing.startDate = newItem.startDate
                    existing.durationSeconds = newItem.durationSeconds
                    existing.url = newItem.url
                    existing.lastFetched = newItem.lastFetched
                } else {
                    modelContext.insert(newItem)
                }
            }
        }

        // Clean up ended contests (where endDate < now)
        for item in existingItems {
            if item.endDate < now {
                modelContext.delete(item)
            }
        }

        try? modelContext.save()

        lastRefreshTime = Date()
        isRefreshing = false

        // Surface quiet notices
        if !failedPlatforms.isEmpty {
            let names = failedPlatforms.map(\.rawValue).joined(separator: ", ")
            unavailablePlatformNotice = "\(names) unavailable right now"
        }

        if !fetchedLists.isEmpty {
            withAnimation(.easeInOut(duration: 0.3)) {
                showUpdatedNotice = true
            }
            Task {
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                await MainActor.run {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        self.showUpdatedNotice = false
                    }
                }
            }
        }
    }
}
