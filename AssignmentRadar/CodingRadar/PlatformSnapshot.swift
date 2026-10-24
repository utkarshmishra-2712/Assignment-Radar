//
//  PlatformSnapshot.swift
//  AssignmentRadar
//
//  SwiftData model caching a platform's public metrics, rating history,
//  daily activity heatmap, and topic counts for fast offline loading.
//

import Foundation
import SwiftData

// MARK: - Codable Data Structures for Snapshots

struct RatingPoint: Codable, Identifiable {
    var id: String { "\(timestamp)_\(rating)" }
    let timestamp: TimeInterval
    let rating: Int
    let contestName: String?
    let rank: Int?
}

struct TopicSolveCount: Codable, Identifiable {
    var id: String { topicName }
    let topicName: String
    let problemsSolved: Int
}

struct DailyActivityItem: Codable, Identifiable {
    var id: TimeInterval { timestamp }
    let timestamp: TimeInterval
    let count: Int
}

struct DifficultyBandItem: Codable, Identifiable {
    var id: String { bandName }
    let bandName: String
    let count: Int
}

@Model
final class PlatformSnapshot {
    var id: String = "" // e.g. "leetcode_preet_baranawal_108"
    var platformRaw: String = ""
    var handle: String = ""
    var rating: Int? = nil
    var maxRating: Int? = nil
    var rankTitle: String? = nil
    var solvedTotal: Int? = nil
    var solvedEasy: Int? = nil
    var solvedMedium: Int? = nil
    var solvedHard: Int? = nil
    var contestsCount: Int? = nil
    var streak: Int? = nil
    var totalActiveDays: Int? = nil
    var ratingHistoryData: Data? = nil
    var dailyActivityData: Data? = nil
    var topicCountsData: Data? = nil
    var difficultyBandsData: Data? = nil
    var lastFetched: Date = Date()
    var statusRaw: String = "notConnected" // "connected", "notFound", "unavailable", "notConnected"
    var errorMessage: String? = nil

    var platform: CodingPlatform {
        CodingPlatform(rawValue: platformRaw) ?? .all
    }

    init(
        platform: CodingPlatform,
        handle: String,
        rating: Int? = nil,
        maxRating: Int? = nil,
        rankTitle: String? = nil,
        solvedTotal: Int? = nil,
        solvedEasy: Int? = nil,
        solvedMedium: Int? = nil,
        solvedHard: Int? = nil,
        contestsCount: Int? = nil,
        streak: Int? = nil,
        totalActiveDays: Int? = nil,
        ratingHistory: [RatingPoint]? = nil,
        dailyActivity: [DailyActivityItem]? = nil,
        topicCounts: [TopicSolveCount]? = nil,
        difficultyBands: [DifficultyBandItem]? = nil,
        lastFetched: Date = Date(),
        status: String = "connected",
        errorMessage: String? = nil
    ) {
        self.id = "\(platform.rawValue.lowercased())_\(handle.lowercased())"
        self.platformRaw = platform.rawValue
        self.handle = handle
        self.rating = rating
        self.maxRating = maxRating
        self.rankTitle = rankTitle
        self.solvedTotal = solvedTotal
        self.solvedEasy = solvedEasy
        self.solvedMedium = solvedMedium
        self.solvedHard = solvedHard
        self.contestsCount = contestsCount
        self.streak = streak
        self.totalActiveDays = totalActiveDays
        self.lastFetched = lastFetched
        self.statusRaw = status
        self.errorMessage = errorMessage

        if let history = ratingHistory {
            self.ratingHistoryData = try? JSONEncoder().encode(history)
        }
        if let activity = dailyActivity {
            self.dailyActivityData = try? JSONEncoder().encode(activity)
        }
        if let topics = topicCounts {
            self.topicCountsData = try? JSONEncoder().encode(topics)
        }
        if let bands = difficultyBands {
            self.difficultyBandsData = try? JSONEncoder().encode(bands)
        }
    }

    var ratingHistory: [RatingPoint] {
        guard let data = ratingHistoryData else { return [] }
        return (try? JSONDecoder().decode([RatingPoint].self, from: data)) ?? []
    }

    var dailyActivity: [DailyActivityItem] {
        guard let data = dailyActivityData else { return [] }
        return (try? JSONDecoder().decode([DailyActivityItem].self, from: data)) ?? []
    }

    var topicCounts: [TopicSolveCount] {
        guard let data = topicCountsData else { return [] }
        return (try? JSONDecoder().decode([TopicSolveCount].self, from: data)) ?? []
    }

    var difficultyBands: [DifficultyBandItem] {
        guard let data = difficultyBandsData else { return [] }
        return (try? JSONDecoder().decode([DifficultyBandItem].self, from: data)) ?? []
    }
}
