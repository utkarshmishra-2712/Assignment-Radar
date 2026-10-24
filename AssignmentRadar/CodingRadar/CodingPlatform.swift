//
//  CodingPlatform.swift
//  AssignmentRadar
//
//  Represents supported coding contest platforms in CodingRadar.
//

import Foundation

enum CodingPlatform: String, CaseIterable, Identifiable, Codable {
    case all = "All"
    case codeforces = "Codeforces"
    case codechef = "CodeChef"
    case leetcode = "LeetCode"
    case atcoder = "AtCoder"

    var id: String { rawValue }

    var tag: String {
        switch self {
        case .all: return "ALL"
        case .codeforces: return "CF"
        case .codechef: return "CC"
        case .leetcode: return "LC"
        case .atcoder: return "AC"
        }
    }
}
