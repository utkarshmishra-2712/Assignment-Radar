//
//  KeychainStore.swift
//  AssignmentRadar
//
//  Securely stores, reads, and deletes sensitive strings (like Moodle calendar URLs)
//  in the iOS Keychain. Never uses UserDefaults or plaintext logging.
//

import Foundation
import Security

enum KeychainStore {
    private static let service = "com.assignmentradar.securestore"
    static let moodleCalendarUrlKey = "moodle_calendar_feed_url"
    static let moodleAuthTokenKey = "moodle_auth_token"
    static let moodleUserIdKey = "moodle_user_id"
    static let moodleUserFullNameKey = "moodle_user_fullname"
    static let moodleUsernameKey = "moodle_username"
    static let moodleSiteNameKey = "moodle_site_name"
    static let moodleLastSyncTimestampKey = "moodle_last_sync_timestamp"
    static let geminiApiKey = "gemini_api_key"
    static let geminiModelKey = "gemini_model_name"

    /// Clears all Moodle authentication tokens, profile info, and saved calendar links from Keychain.
    static func clearMoodleSession() {
        delete(key: moodleAuthTokenKey)
        delete(key: moodleUserIdKey)
        delete(key: moodleUserFullNameKey)
        delete(key: moodleUsernameKey)
        delete(key: moodleSiteNameKey)
        delete(key: moodleCalendarUrlKey)
        delete(key: moodleLastSyncTimestampKey)
    }

    /// Saves or updates a secret string in the iOS Keychain.
    @discardableResult
    static func save(key: String, value: String) -> Bool {
        guard let data = value.data(using: .utf8) else { return false }

        // First, attempt to update an existing item
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]

        let attributesToUpdate: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
        ]

        let status = SecItemUpdate(query as CFDictionary, attributesToUpdate as CFDictionary)

        if status == errSecSuccess {
            return true
        }

        if status == errSecItemNotFound {
            // Item does not exist yet, add it
            var newItem = query
            newItem[kSecValueData as String] = data
            newItem[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock

            let addStatus = SecItemAdd(newItem as CFDictionary, nil)
            return addStatus == errSecSuccess
        }

        return false
    }

    /// Reads a secret string from the iOS Keychain.
    static func read(key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var dataTypeRef: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &dataTypeRef)

        guard status == errSecSuccess, let data = dataTypeRef as? Data else {
            return nil
        }

        return String(data: data, encoding: .utf8)
    }

    /// Deletes a secret string from the iOS Keychain.
    @discardableResult
    static func delete(key: String) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]

        let status = SecItemDelete(query as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }

    /// Checks if a value exists for the given key without exposing the value.
    static func exists(key: String) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: false,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        let status = SecItemCopyMatching(query as CFDictionary, nil)
        return status == errSecSuccess
    }
}
