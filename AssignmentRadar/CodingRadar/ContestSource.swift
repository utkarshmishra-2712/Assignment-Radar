//
//  ContestSource.swift
//  AssignmentRadar
//
//  Protocol defining the contract for contest platform fetching.
//  Each platform implementation is isolated in its own file.
//

import Foundation

protocol ContestSource: Sendable {
    var platform: CodingPlatform { get }
    func fetchContests() async throws -> [ContestItem]
}
