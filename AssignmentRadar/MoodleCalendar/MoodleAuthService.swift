//
//  MoodleAuthService.swift
//  AssignmentRadar
//
//  Handles automatic Moodle token authentication, site information fetching,
//  and calendar deadline retrieval via Moodle Web Services without requiring
//  students to manually copy or paste calendar links.
//

import Foundation
import SwiftData

// MARK: - Moodle Authentication Errors
enum MoodleAuthError: LocalizedError {
    case invalidLogin
    case serviceDisabledOrUnavailable(detail: String?)
    case noInternet
    case missingToken
    case serverError(statusCode: Int)
    case custom(String)

    var errorDescription: String? {
        switch self {
        case .invalidLogin:
            return "Invalid username or password. Please check your college login credentials and try again."
        case .serviceDisabledOrUnavailable(let detail):
            if let detail = detail, !detail.isEmpty {
                return "Moodle Mobile Web Service is unavailable: \(detail)"
            }
            return "Moodle Mobile Web Service is currently disabled on this server. Please contact your college administrator."
        case .noInternet:
            return "No internet connection. Please check your network and try again."
        case .missingToken:
            return "Moodle did not return an access token. Please verify that Mobile services are enabled."
        case .serverError(let code):
            return "College server returned an error (HTTP \(code)). Please try again later."
        case .custom(let message):
            return message
        }
    }
}

// MARK: - Moodle Models
struct MoodleTokenResponse: Codable {
    let token: String?
    let privatetoken: String?
    let error: String?
    let errorcode: String?
}

struct MoodleSiteInfo: Codable {
    let sitename: String?
    let username: String?
    let firstname: String?
    let lastname: String?
    let fullname: String?
    let userid: Int?
    let userpictureurl: String?
    let functions: [MoodleFunctionInfo]?
    let error: String?
    let errorcode: String?
    let exception: String?
    let message: String?
}

struct MoodleFunctionInfo: Codable {
    let name: String
    let version: String?
}

struct MoodleExportTokenResponse: Codable {
    let token: String?
    let error: String?
    let errorcode: String?
    let exception: String?
    let message: String?
}

struct MoodleActionEventsResponse: Codable {
    let events: [MoodleActionEvent]?
    let error: String?
    let errorcode: String?
    let exception: String?
    let message: String?
}

struct MoodleActionEvent: Codable {
    let id: Int
    let name: String
    let description: String?
    let course: MoodleCourseInfo?
    let timesort: Int?
    let timestart: Int?
    let url: String?
}

struct MoodleCourseInfo: Codable {
    let id: Int?
    let fullname: String?
    let shortname: String?
}

// MARK: - Moodle Authentication & Sync Service
final class MoodleAuthService {
    static let shared = MoodleAuthService()

    private init() {}

    // MARK: - Sign In with Username & Password
    /// Posts username and password to /login/token.php.
    /// The password is kept in memory strictly for this request and discarded immediately.
    @MainActor
    func login(username: String, password: String, modelContext: ModelContext) async throws -> MoodleSiteInfo {
        let cleanUsername = username.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanUsername.isEmpty, !password.isEmpty else {
            throw MoodleAuthError.custom("Please enter both username and password.")
        }

        guard let tokenEndpoint = URL(string: "\(MoodleConfig.baseURL)/login/token.php") else {
            throw MoodleAuthError.custom("Invalid Moodle base URL configuration.")
        }

        // Prepare POST request with form url-encoded body
        var request = URLRequest(url: tokenEndpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 15.0
        request.setValue("AssignmentRadar/1.0", forHTTPHeaderField: "User-Agent")
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        // Build URL-encoded body
        var components = URLComponents()
        components.queryItems = [
            URLQueryItem(name: "username", value: cleanUsername),
            URLQueryItem(name: "password", value: password),
            URLQueryItem(name: "service", value: "moodle_mobile_app")
        ]
        request.httpBody = components.percentEncodedQuery?.data(using: .utf8)

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch let urlError as URLError {
            if urlError.code == .notConnectedToInternet || urlError.code == .networkConnectionLost || urlError.code == .timedOut {
                throw MoodleAuthError.noInternet
            }
            if urlError.code.rawValue == -1022 || urlError.code == .appTransportSecurityRequiresSecureConnection {
                throw MoodleAuthError.custom("Connection blocked by App Transport Security. Please ensure HTTP permissions are set.")
            }
            throw MoodleAuthError.custom("Connection failed: \(urlError.localizedDescription)")
        } catch {
            throw MoodleAuthError.custom("Unable to connect to Moodle: \(error.localizedDescription)")
        }

        if let httpResponse = response as? HTTPURLResponse, !(200...299).contains(httpResponse.statusCode) {
            throw MoodleAuthError.serverError(statusCode: httpResponse.statusCode)
        }

        // Decode token response
        guard let tokenResponse = try? JSONDecoder().decode(MoodleTokenResponse.self, from: data) else {
            throw MoodleAuthError.custom("Unexpected response from college login server.")
        }

        if let errorCode = tokenResponse.errorcode {
            if errorCode == "invalidlogin" {
                throw MoodleAuthError.invalidLogin
            }
            if errorCode == "servicenotavailable" || errorCode == "enablewebservices" {
                throw MoodleAuthError.serviceDisabledOrUnavailable(detail: tokenResponse.error)
            }
            throw MoodleAuthError.custom(tokenResponse.error ?? "Login failed (\(errorCode)).")
        }

        guard let token = tokenResponse.token, !token.isEmpty else {
            throw MoodleAuthError.missingToken
        }

        // Check if there was a previously saved account to detect account switching
        let previousUsername = KeychainStore.read(key: KeychainStore.moodleUsernameKey)?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let previousUserId = KeychainStore.read(key: KeychainStore.moodleUserIdKey)
        let isDifferentAccountName = previousUsername != nil && !previousUsername!.isEmpty && previousUsername != cleanUsername.lowercased()

        // Save token securely in Keychain
        KeychainStore.save(key: KeychainStore.moodleAuthTokenKey, value: token)
        KeychainStore.save(key: KeychainStore.moodleUsernameKey, value: cleanUsername)
        UserDefaults.standard.set(cleanUsername.lowercased(), forKey: "active_moodle_account")
        UserDefaults.standard.synchronize()

        // Fetch site and user details
        let siteInfo = try await fetchSiteInfo(token: token)

        let currentUserIdString = siteInfo.userid.map { String($0) }
        let isDifferentUserId = previousUserId != nil && !previousUserId!.isEmpty && currentUserIdString != nil && previousUserId != currentUserIdString

        // If logged in from a different account, flush all deadlines of the previous account
        if isDifferentAccountName || isDifferentUserId {
            flushMoodleDeadlines(in: modelContext)
        }

        // Store user profile details in Keychain
        if let userId = siteInfo.userid {
            KeychainStore.save(key: KeychainStore.moodleUserIdKey, value: String(userId))
        }
        if let fullname = siteInfo.fullname, !fullname.isEmpty {
            KeychainStore.save(key: KeychainStore.moodleUserFullNameKey, value: fullname)
        }
        if let sitename = siteInfo.sitename, !sitename.isEmpty {
            KeychainStore.save(key: KeychainStore.moodleSiteNameKey, value: sitename)
        }

        // Fetch deadlines and upsert into database (best-effort during initial login)
        do {
            _ = try await syncDeadlines(token: token, siteInfo: siteInfo, modelContext: modelContext)
        } catch {
            print("Initial deadline sync non-fatal error: \(error.localizedDescription)")
        }

        return siteInfo
    }

    // MARK: - Fetch Site Info
    func fetchSiteInfo(token: String) async throws -> MoodleSiteInfo {
        let endpoint = "\(MoodleConfig.baseURL)/webservice/rest/server.php?wstoken=\(token)&wsfunction=core_webservice_get_site_info&moodlewsrestformat=json"
        guard let url = URL(string: endpoint) else {
            throw MoodleAuthError.custom("Invalid site info endpoint URL.")
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 12.0
        request.setValue("AssignmentRadar/1.0", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await URLSession.shared.data(for: request)

        if let httpResponse = response as? HTTPURLResponse, !(200...299).contains(httpResponse.statusCode) {
            throw MoodleAuthError.serverError(statusCode: httpResponse.statusCode)
        }

        guard let siteInfo = try? JSONDecoder().decode(MoodleSiteInfo.self, from: data) else {
            throw MoodleAuthError.custom("Could not read site info from Moodle.")
        }

        if let exception = siteInfo.exception, !exception.isEmpty {
            if siteInfo.errorcode == "invalidtoken" {
                KeychainStore.delete(key: KeychainStore.moodleAuthTokenKey)
                throw MoodleAuthError.invalidLogin
            }
            throw MoodleAuthError.custom(siteInfo.message ?? "Failed to fetch user profile.")
        }

        return siteInfo
    }

    // MARK: - Sync Deadlines (Method A: Export Token / ICS, Method B: Action Events)
    @MainActor
    func syncDeadlines(token: String? = nil, siteInfo: MoodleSiteInfo? = nil, modelContext: ModelContext) async throws -> Int {
        let activeToken = token ?? KeychainStore.read(key: KeychainStore.moodleAuthTokenKey)

        // If no token, check if we have a saved calendar link
        guard let validToken = activeToken else {
            if let savedUrlString = KeychainStore.read(key: KeychainStore.moodleCalendarUrlKey),
               let savedUrl = URL(string: savedUrlString) {
                let items = try await MoodleSource(targetURL: savedUrl).fetchDeadlines()
                upsertItems(items, into: modelContext)
                recordSyncTimestamp()
                return items.count
            }
            throw MoodleAuthError.custom("No college account connected.")
        }

        // Method A: Try core_calendar_get_calendar_export_token to rebuild the ICS link
        if let exportToken = try? await fetchCalendarExportToken(token: validToken) {
            let userIdString = KeychainStore.read(key: KeychainStore.moodleUserIdKey)
                ?? (siteInfo?.userid.map { String($0) })
                ?? "0"

            let builtUrlString = "\(MoodleConfig.baseURL)/calendar/export_execute.php?userid=\(userIdString)&authtoken=\(exportToken)&preset_what=all&preset_time=recentupcoming"

            if let exportURL = URL(string: builtUrlString) {
                // Save generated link in Keychain only
                KeychainStore.save(key: KeychainStore.moodleCalendarUrlKey, value: builtUrlString)

                do {
                    let items = try await MoodleSource(targetURL: exportURL).fetchDeadlines()
                    if !items.isEmpty {
                        upsertItems(items, into: modelContext)
                        recordSyncTimestamp()
                        return items.count
                    }
                } catch MoodleSourceError.noEventsFound {
                    recordSyncTimestamp()
                    return 0
                } catch {
                    // Fall through to Method B
                }
            }
        }

        // Method B: Try core_calendar_get_action_events_by_timesort to read upcoming events directly
        do {
            let actionEvents = try await fetchActionEvents(token: validToken)
            let hostAndPath = MoodleConfig.baseURL
                .replacingOccurrences(of: "https://", with: "")
                .replacingOccurrences(of: "http://", with: "")

            let convertedItems = actionEvents.compactMap { event -> DeadlineItem? in
                let timestamp = event.timesort ?? event.timestart ?? 0
                guard timestamp > 0 else { return nil }

                let dueDate = Date(timeIntervalSince1970: TimeInterval(timestamp))
                let subject = event.course?.shortname
                    ?? event.course?.fullname
                    ?? "Course"

                let eventUID = "\(event.id)@\(hostAndPath)"
                let linkURL: URL? = event.url != nil ? URL(string: event.url!) : nil
                let isCompleted = CompletedDeadlinesStore.shared.isCompleted(id: eventUID)

                return DeadlineItem(
                    id: eventUID,
                    title: event.name,
                    subject: subject,
                    dueDate: dueDate,
                    source: "moodle",
                    link: linkURL,
                    isDone: isCompleted,
                    lastModified: Date()
                )
            }

            if !convertedItems.isEmpty {
                upsertItems(convertedItems, into: modelContext)
                recordSyncTimestamp()
                return convertedItems.count
            }

            recordSyncTimestamp()
            return 0
        } catch {
            // If we have a saved calendar link, attempt that as a fallback
            if let savedUrlString = KeychainStore.read(key: KeychainStore.moodleCalendarUrlKey),
               let savedUrl = URL(string: savedUrlString),
               let items = try? await MoodleSource(targetURL: savedUrl).fetchDeadlines() {
                upsertItems(items, into: modelContext)
                recordSyncTimestamp()
                return items.count
            }
            throw error
        }
    }

    // MARK: - Helper: Calendar Export Token
    private func fetchCalendarExportToken(token: String) async throws -> String? {
        let endpoint = "\(MoodleConfig.baseURL)/webservice/rest/server.php?wstoken=\(token)&wsfunction=core_calendar_get_calendar_export_token&moodlewsrestformat=json"
        guard let url = URL(string: endpoint) else { return nil }

        var request = URLRequest(url: url)
        request.timeoutInterval = 10.0
        request.setValue("AssignmentRadar/1.0", forHTTPHeaderField: "User-Agent")

        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            return nil
        }

        // Moodle can return either a raw string ("abcd123...") or a JSON object ({"token": "..."})
        if let directToken = try? JSONDecoder().decode(String.self, from: data), !directToken.isEmpty {
            return directToken
        }
        if let exportResponse = try? JSONDecoder().decode(MoodleExportTokenResponse.self, from: data),
           let token = exportResponse.token, !token.isEmpty {
            return token
        }

        return nil
    }

    // MARK: - Helper: Action Events by Timesort
    private func fetchActionEvents(token: String) async throws -> [MoodleActionEvent] {
        let pastWeekTimestamp = Int(Date().timeIntervalSince1970) - (7 * 86400)
        // Moodle enforces limitnum between 1 and 50 inclusive
        let endpoint = "\(MoodleConfig.baseURL)/webservice/rest/server.php?wstoken=\(token)&wsfunction=core_calendar_get_action_events_by_timesort&timesortfrom=\(pastWeekTimestamp)&limitnum=50&moodlewsrestformat=json"
        guard let url = URL(string: endpoint) else {
            throw MoodleAuthError.custom("Invalid calendar events endpoint URL.")
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 12.0
        request.setValue("AssignmentRadar/1.0", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await URLSession.shared.data(for: request)

        if let httpResponse = response as? HTTPURLResponse, !(200...299).contains(httpResponse.statusCode) {
            throw MoodleAuthError.serverError(statusCode: httpResponse.statusCode)
        }

        guard let eventsResponse = try? JSONDecoder().decode(MoodleActionEventsResponse.self, from: data) else {
            throw MoodleAuthError.custom("Could not read calendar events from Moodle.")
        }

        if let exception = eventsResponse.exception, !exception.isEmpty {
            throw MoodleAuthError.custom(eventsResponse.message ?? "Could not fetch upcoming deadlines.")
        }

        return eventsResponse.events ?? []
    }

    // MARK: - Upsert Logic (Matches existing deduplication & update rules)
    @MainActor
    func upsertItems(_ newItems: [DeadlineItem], into modelContext: ModelContext) {
        let descriptor = FetchDescriptor<DeadlineItem>()
        let existingItems = (try? modelContext.fetch(descriptor)) ?? []
        let existingMap = Dictionary(uniqueKeysWithValues: existingItems.map { ($0.id, $0) })

        let activeAccount = KeychainStore.read(key: KeychainStore.moodleUsernameKey)?
            .trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        for newItem in newItems {
            if newItem.account == nil {
                newItem.account = activeAccount
            }

            let isMarkedDone = newItem.isDone || CompletedDeadlinesStore.shared.isCompleted(id: newItem.id)
            if isMarkedDone {
                newItem.isDone = true
            }

            if let existing = existingMap[newItem.id] {
                if existing.isDone || isMarkedDone {
                    existing.isDone = true
                    CompletedDeadlinesStore.shared.markCompleted(id: existing.id)
                }

                let shouldUpdate: Bool
                if let newMod = newItem.lastModified, let existingMod = existing.lastModified {
                    shouldUpdate = newMod > existingMod
                } else if newItem.lastModified != nil && existing.lastModified == nil {
                    shouldUpdate = true
                } else {
                    shouldUpdate = false
                }

                if shouldUpdate {
                    existing.title = newItem.title
                    existing.subject = newItem.subject
                    existing.dueDate = newItem.dueDate
                    existing.link = newItem.link
                    existing.lastModified = newItem.lastModified
                    existing.account = newItem.account ?? activeAccount
                }
            } else {
                modelContext.insert(newItem)
            }
        }

        try? modelContext.save()
    }

    // MARK: - Sign Out
    /// Deletes the token, user info, and any saved calendar links from Keychain.
    /// Optionally flushes all previous account Moodle deadlines from the database.
    @MainActor
    func signOut(modelContext: ModelContext? = nil) {
        let activeUsername = KeychainStore.read(key: KeychainStore.moodleUsernameKey)
        if let context = modelContext {
            CompletedDeadlinesStore.shared.syncExistingCompletedItems(from: context, account: activeUsername)
            flushMoodleDeadlines(in: context)
        }
        KeychainStore.clearMoodleSession()
        UserDefaults.standard.removeObject(forKey: "active_moodle_account")
        UserDefaults.standard.synchronize()
    }

    // MARK: - Flush Moodle Deadlines
    /// Flushes all deadlines originating from Moodle when switching accounts or signing out.
    @MainActor
    func flushMoodleDeadlines(in modelContext: ModelContext) {
        let descriptor = FetchDescriptor<DeadlineItem>()
        if let allItems = try? modelContext.fetch(descriptor) {
            let moodleItems = allItems.filter { $0.source == "moodle" }
            for item in moodleItems {
                modelContext.delete(item)
            }
            try? modelContext.save()

            // Upon sign out or account flush, only sync guest items (account == nil) to widget
            let guestItems = allItems.filter { $0.source != "moodle" && ($0.account == nil || $0.account?.isEmpty == true) }
            WidgetDataStore.sync(from: guestItems)
        }
    }

    // MARK: - Session & Auto-Sync
    var hasActiveSession: Bool {
        guard let token = KeychainStore.read(key: KeychainStore.moodleAuthTokenKey), !token.isEmpty else {
            return false
        }
        return true
    }

    /// Determines whether an auto-sync is allowed (at most once every 15 minutes).
    var canAutoSync: Bool {
        guard hasActiveSession else { return false }
        guard let lastSyncStr = KeychainStore.read(key: KeychainStore.moodleLastSyncTimestampKey),
              let lastSync = Double(lastSyncStr) else {
            return true
        }
        let now = Date().timeIntervalSince1970
        return (now - lastSync) >= (15 * 60)
    }

    /// Quietly synchronizes upcoming deadlines if at least 15 minutes have elapsed.
    /// Returns true if a sync was executed, false otherwise.
    @MainActor
    func autoSyncIfNeeded(modelContext: ModelContext) async -> Bool {
        guard canAutoSync else { return false }
        do {
            _ = try await syncDeadlines(modelContext: modelContext)
            return true
        } catch {
            return false
        }
    }

    // MARK: - Timestamp Helper
    private func recordSyncTimestamp() {
        KeychainStore.save(
            key: KeychainStore.moodleLastSyncTimestampKey,
            value: String(Date().timeIntervalSince1970)
        )
    }
}

