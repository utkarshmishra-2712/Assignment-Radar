//
//  MoodleSource.swift
//  AssignmentRadar
//
//  Downloads an ICS calendar feed from Moodle using URLSession,
//  tries the user's scheme first with automatic fallback, and returns parsed DeadlineItem models.
//

import Foundation

// MARK: - Moodle Source Errors
enum MoodleSourceError: LocalizedError {
    case invalidURL
    case noInternet
    case noEventsFound
    case downloadFailed
    case insecureHTTPBlocked
    case serverError(statusCode: Int)

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Please enter a valid Moodle calendar link."
        case .noInternet:
            return "No internet connection. Please check your network and try again."
        case .noEventsFound:
            return "No assignment deadlines were found in this calendar feed."
        case .insecureHTTPBlocked:
            return "This Moodle server uses plain HTTP, which iOS App Transport Security blocks by default. Please enable 'Allow Arbitrary Loads' in Xcode Target Settings."
        case .downloadFailed:
            return "Could not connect to Moodle. Please verify the link and try again."
        case .serverError(let code):
            return "Moodle returned an error (HTTP \(code)). Please check your calendar link."
        }
    }
}

// MARK: - Moodle Source Service
final class MoodleSource: DeadlineSource {
    private let targetURL: URL

    init(targetURL: URL) {
        self.targetURL = targetURL
    }

    /// Fetches deadlines from the Moodle ICS feed, respecting the original scheme first with fallback.
    func fetchDeadlines() async throws -> [DeadlineItem] {
        let candidateURLs = makeCandidateURLs(from: targetURL)
        var lastError: Error?

        for url in candidateURLs {
            do {
                let data = try await downloadData(from: url)
                guard let icsString = String(data: data, encoding: .utf8)
                        ?? String(data: data, encoding: .isoLatin1) else {
                    throw MoodleSourceError.downloadFailed
                }

                let items = ICSParser.parse(icsString)
                if items.isEmpty {
                    throw MoodleSourceError.noEventsFound
                }

                return items
            } catch let error as MoodleSourceError {
                throw error
            } catch let error as URLError {
                if error.code == .notConnectedToInternet || error.code == .networkConnectionLost {
                    throw MoodleSourceError.noInternet
                }
                if error.code.rawValue == -1022 || error.code == .appTransportSecurityRequiresSecureConnection {
                    lastError = MoodleSourceError.insecureHTTPBlocked
                } else {
                    lastError = error
                }
                continue
            } catch {
                lastError = error
                continue
            }
        }

        if let sourceError = lastError as? MoodleSourceError {
            throw sourceError
        }

        throw MoodleSourceError.downloadFailed
    }

    // MARK: - Helper Methods
    private func downloadData(from url: URL) async throws -> Data {
        var request = URLRequest(url: url)
        request.timeoutInterval = 10.0
        // Set standard user agent to avoid bot blocking by older Moodle servers
        request.setValue("AssignmentRadar/1.0", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await URLSession.shared.data(for: request)

        if let httpResponse = response as? HTTPURLResponse {
            guard (200...299).contains(httpResponse.statusCode) else {
                throw MoodleSourceError.serverError(statusCode: httpResponse.statusCode)
            }
        }

        return data
    }

    /// Generates candidate URLs: tries the original requested scheme first, then falls back.
    private func makeCandidateURLs(from url: URL) -> [URL] {
        var candidates: [URL] = []
        var urlString = url.absoluteString

        // Replace webcal:// with http://
        if urlString.lowercased().hasPrefix("webcal://") {
            urlString = "http://" + urlString.dropFirst("webcal://".count)
        }

        guard let parsed = URL(string: urlString) else { return [url] }

        // If user already specified http://, try http first without waiting for https port 443 timeout!
        if urlString.lowercased().hasPrefix("http://") {
            candidates.append(parsed)
            if let httpsFallback = URL(string: urlString.replacingOccurrences(of: "http://", with: "https://")) {
                candidates.append(httpsFallback)
            }
        } else if urlString.lowercased().hasPrefix("https://") {
            candidates.append(parsed)
            if let httpFallback = URL(string: urlString.replacingOccurrences(of: "https://", with: "http://")) {
                candidates.append(httpFallback)
            }
        } else {
            candidates.append(parsed)
        }

        return candidates
    }
}
