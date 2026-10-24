//
//  CodingProfile.swift
//  AssignmentRadar
//
//  SwiftData model representing a student's public coding profile
//  and linked handles across supported competitive programming platforms.
//

import Foundation
import SwiftData

@Model
final class CodingProfile {
    var id: String = "default_coding_profile"
    var displayName: String = "Coder"
    var leetcodeHandle: String? = nil
    var codeforcesHandle: String? = nil
    var codechefHandle: String? = nil
    var atcoderHandle: String? = nil
    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    init(
        id: String = "default_coding_profile",
        displayName: String = "Coder",
        leetcodeHandle: String? = nil,
        codeforcesHandle: String? = nil,
        codechefHandle: String? = nil,
        atcoderHandle: String? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.displayName = displayName
        self.leetcodeHandle = leetcodeHandle
        self.codeforcesHandle = codeforcesHandle
        self.codechefHandle = codechefHandle
        self.atcoderHandle = atcoderHandle
        self.createdAt = createdAt
        self.updatedAt = createdAt
    }

    var initials: String {
        let parts = displayName.split(separator: " ").filter { !$0.isEmpty }
        if parts.count >= 2 {
            let first = parts[0].prefix(1)
            let second = parts[1].prefix(1)
            return "\(first)\(second)".uppercased()
        } else if let firstPart = parts.first, !firstPart.isEmpty {
            return String(firstPart.prefix(2)).uppercased()
        }
        return "CP"
    }

    func handle(for platform: CodingPlatform) -> String? {
        switch platform {
        case .leetcode: return leetcodeHandle
        case .codeforces: return codeforcesHandle
        case .codechef: return codechefHandle
        case .atcoder: return atcoderHandle
        case .all: return nil
        }
    }

    func setHandle(_ handle: String?, for platform: CodingPlatform) {
        let clean = handle?.trimmingCharacters(in: .whitespacesAndNewlines)
        let value = (clean?.isEmpty == false) ? clean : nil
        switch platform {
        case .leetcode: leetcodeHandle = value
        case .codeforces: codeforcesHandle = value
        case .codechef: codechefHandle = value
        case .atcoder: atcoderHandle = value
        case .all: break
        }
        updatedAt = Date()
    }

    var connectedPlatformsCount: Int {
        var count = 0
        if leetcodeHandle?.isEmpty == false { count += 1 }
        if codeforcesHandle?.isEmpty == false { count += 1 }
        if codechefHandle?.isEmpty == false { count += 1 }
        if atcoderHandle?.isEmpty == false { count += 1 }
        return count
    }
}
