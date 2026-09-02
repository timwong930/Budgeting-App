import Foundation
import Security

struct PlaidAuthenticatedSession: Codable, Sendable, Equatable {
    var accessToken: String
    var refreshToken: String
    var expiresAt: Date
    var userId: String
}

enum PlaidAuthError: LocalizedError {
    case invalidProjectURL
    case invalidResponse
    case anonymousSignInUnavailable(String)
    case sessionRefreshFailed(String)
    case missingUser
    case keychain(String)

    var errorDescription: String? {
        switch self {
        case .invalidProjectURL:
            return "The Supabase authentication URL is invalid."
        case .invalidResponse:
            return "Supabase authentication returned an invalid response."
        case .anonymousSignInUnavailable(let message):
            return message.isEmpty
                ? "Supabase anonymous sign-in is unavailable for Momo's Money."
                : message
        case .sessionRefreshFailed(let message):
            return message.isEmpty
                ? "The Plaid authentication session could not be refreshed. Re-authentication is required before syncing."
                : message
        case .missingUser:
            return "Supabase authentication did not return a user identity."
        case .keychain(let message):
            return message
        }
    }
}

enum PlaidSupabaseAuthConfiguration {
    static let projectURL = "https://zqjvfmkesfwdtgwkcuxc.supabase.co"
    static let publishableKey = "sb_publishable_pEelYoXuVLrUTHN1-36GQg_9-5ZRO-M"
}

actor PlaidAuthSessionStore {
    static let shared = PlaidAuthSessionStore()

    private let session: URLSession
    private var cachedSession: PlaidAuthenticatedSession?

    init(session: URLSession = .shared) {
        self.session = session
    }

    func accessToken() async throws -> String {
        let session = try await validSession()
        return session.accessToken
    }

    func userId() async throws -> String {
        let session = try await validSession()
        return session.userId
    }

    func validSession() async throws -> PlaidAuthenticatedSession {
        if let cachedSession, cachedSession.expiresAt.timeIntervalSinceNow > 120 {
            return cachedSession
        }

        if let stored = try PlaidAuthSessionKeychain.read() {
            if stored.expiresAt.timeIntervalSinceNow > 120 {
                cachedSession = stored
                return stored
            }

            do {
                let refreshed = try await refresh(stored)
                try PlaidAuthSessionKeychain.save(refreshed)
                cachedSession = refreshed
                return refreshed
            } catch let error as PlaidAuthError {
                throw error
            } catch {
                throw PlaidAuthError.sessionRefreshFailed(error.localizedDescription)
            }
        }

        let created = try await createAnonymousSession()
        try PlaidAuthSessionKeychain.save(created)
        cachedSession = created
        return created
    }

    private func createAnonymousSession() async throws -> PlaidAuthenticatedSession {
        guard let url = authURL(path: "/auth/v1/signup") else {
            throw PlaidAuthError.invalidProjectURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(PlaidSupabaseAuthConfiguration.publishableKey, forHTTPHeaderField: "apikey")
        request.httpBody = Data("{}".utf8)

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw PlaidAuthError.invalidResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            throw PlaidAuthError.anonymousSignInUnavailable(Self.authErrorMessage(from: data))
        }
        return try Self.decodeSession(from: data)
    }

    private func refresh(_ existing: PlaidAuthenticatedSession) async throws -> PlaidAuthenticatedSession {
        guard let url = authURL(path: "/auth/v1/token", queryItems: [URLQueryItem(name: "grant_type", value: "refresh_token")]) else {
            throw PlaidAuthError.invalidProjectURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(PlaidSupabaseAuthConfiguration.publishableKey, forHTTPHeaderField: "apikey")
        request.httpBody = try JSONEncoder().encode(PlaidRefreshRequest(refreshToken: existing.refreshToken))

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw PlaidAuthError.invalidResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            let message = Self.authErrorMessage(from: data)
            throw PlaidAuthError.sessionRefreshFailed(
                message.isEmpty
                    ? "The saved Plaid owner session expired and could not be refreshed. The app did not create a replacement identity because that could orphan connected accounts."
                    : message
            )
        }
        return try Self.decodeSession(from: data)
    }

    private func authURL(path: String, queryItems: [URLQueryItem] = []) -> URL? {
        guard var components = URLComponents(string: PlaidSupabaseAuthConfiguration.projectURL) else { return nil }
        components.path = path
        components.queryItems = queryItems.isEmpty ? nil : queryItems
        return components.url
    }

    private static func decodeSession(from data: Data) throws -> PlaidAuthenticatedSession {
        let response: PlaidAuthResponse
        do {
            response = try JSONDecoder().decode(PlaidAuthResponse.self, from: data)
        } catch {
            throw PlaidAuthError.invalidResponse
        }

        guard !response.user.id.isEmpty else { throw PlaidAuthError.missingUser }
        let expiresAt = response.expiresAt.map { Date(timeIntervalSince1970: TimeInterval($0)) }
            ?? Date().addingTimeInterval(TimeInterval(response.expiresIn))
        return PlaidAuthenticatedSession(
            accessToken: response.accessToken,
            refreshToken: response.refreshToken,
            expiresAt: expiresAt,
            userId: response.user.id
        )
    }

    private static func authErrorMessage(from data: Data) -> String {
        guard let payload = try? JSONDecoder().decode(PlaidAuthErrorResponse.self, from: data) else { return "" }
        return payload.message ?? payload.msg ?? payload.errorDescription ?? payload.error ?? ""
    }
}

private struct PlaidRefreshRequest: Encodable {
    var refreshToken: String

    enum CodingKeys: String, CodingKey {
        case refreshToken = "refresh_token"
    }
}

private struct PlaidAuthResponse: Decodable {
    var accessToken: String
    var refreshToken: String
    var expiresIn: Int
    var expiresAt: Int?
    var user: PlaidAuthUser

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case expiresIn = "expires_in"
        case expiresAt = "expires_at"
        case user
    }
}

private struct PlaidAuthUser: Decodable {
    var id: String
}

private struct PlaidAuthErrorResponse: Decodable {
    var message: String?
    var msg: String?
    var error: String?
    var errorDescription: String?

    enum CodingKeys: String, CodingKey {
        case message
        case msg
        case error
        case errorDescription = "error_description"
    }
}

private enum PlaidAuthSessionKeychain {
    private static let service = "Timothy-Wong.Budgeting-App.Plaid"
    private static let account = "supabase-owner-session"

    static func read() throws -> PlaidAuthenticatedSession? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = item as? Data else {
            throw PlaidAuthError.keychain("Could not read the Plaid owner session from Keychain.")
        }
        do {
            return try JSONDecoder().decode(PlaidAuthenticatedSession.self, from: data)
        } catch {
            throw PlaidAuthError.keychain("The saved Plaid owner session is unreadable. It was not replaced automatically to protect account ownership.")
        }
    }

    static func save(_ session: PlaidAuthenticatedSession) throws {
        let data = try JSONEncoder().encode(session)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]

        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            var addQuery = query
            addQuery.merge(attributes) { _, new in new }
            let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
            guard addStatus == errSecSuccess else {
                throw PlaidAuthError.keychain("Could not save the Plaid owner session to Keychain.")
            }
        } else if status != errSecSuccess {
            throw PlaidAuthError.keychain("Could not update the Plaid owner session in Keychain.")
        }
    }
}
