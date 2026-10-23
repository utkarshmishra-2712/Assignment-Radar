//
//  MoodleConfig.swift
//  AssignmentRadar
//
//  Central configuration for college Moodle instance.
//

import Foundation

enum MoodleConfig {
    /// The base URL for the college Moodle instance.
    static let baseURL = "http://lms.kiet.edu/moodle"

    /// Flag controlling whether insecure HTTP is allowed.
    static let allowInsecureHTTP = true
}
