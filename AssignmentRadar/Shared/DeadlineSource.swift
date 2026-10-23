//
//  DeadlineSource.swift
//  AssignmentRadar
//
//  Protocol adopted by deadline providers (e.g. Moodle ICS feed, Photo OCR).
//

import Foundation

/// Blueprint for services that fetch deadlines asynchronously.
protocol DeadlineSource {
    /// Fetches a collection of deadline items from an external or local source.
    func fetchDeadlines() async throws -> [DeadlineItem]
}
