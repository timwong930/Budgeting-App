import Foundation
import Security

enum PlaidClientError: LocalizedError {
    case missingBackendURL
    case missingSyncKey
    case invalidBackendURL
    case invalidResponse
    case server(String)

    var errorDescription: String? {
        switch self {
        case .missingBackendURL:
            return "Add your Plaid backend URL in Settings."
        case .missingSyncKey:
            return "Add your Plaid sync key in Settings."
        case .invalidBackendURL:
            return "Plaid backend URL is invalid."
        case .invalidResponse:
            return "Plaid backend returned an invalid response."
        case .server(let message):
            return message
        }
    }
}

struct PlaidBackendConfiguration: Codable, Sendable, Equatable {
    var backendURL: String

    init(backendURL: String = "") {
        self.backendURL = backendURL
    }
}

struct PlaidLinkTokenResponse: Codable, Sendable, Equatable {
    var linkToken: String
    var expiration: Date?
}

struct PlaidLinkTokenRequest: Codable, Sendable, Equatable {
    var productScope: PlaidLinkProductScope
}

enum PlaidLinkProductScope: String, Codable, Sendable, Equatable {
    case banking
    case investments
}

struct PlaidExchangePublicTokenRequest: Codable, Sendable, Equatable {
    var publicToken: String
    var institutionName: String?
}

struct PlaidConnectionsResponse: Codable, Sendable, Equatable {
    var connections: [PlaidConnectionStatus]
}

struct PlaidAPIClient {
    var configuration: PlaidBackendConfiguration
    var syncKey: String
    var session: URLSession = .shared

    func createLinkToken(productScope: PlaidLinkProductScope) async throws -> PlaidLinkTokenResponse {
        try await send(path: "/api/plaid/link-token", method: "POST", body: PlaidLinkTokenRequest(productScope: productScope))
    }

    func exchangePublicToken(_ request: PlaidExchangePublicTokenRequest) async throws -> PlaidConnectionsResponse {
        try await send(path: "/api/plaid/exchange-public-token", method: "POST", body: request)
    }

    func connections() async throws -> PlaidConnectionsResponse {
        try await send(path: "/api/plaid/connections", method: "GET", body: Optional<EmptyRequest>.none)
    }

    func sync() async throws -> PlaidSyncPayload {
        try await send(path: "/api/plaid/sync", method: "POST", body: EmptyRequest())
    }

    func disconnect(itemId: String) async throws -> PlaidConnectionsResponse {
        try await send(path: "/api/plaid/items/\(itemId)", method: "DELETE", body: Optional<EmptyRequest>.none)
    }

    private func send<RequestBody: Encodable, ResponseBody: Decodable>(
        path: String,
        method: String,
        body: RequestBody?
    ) async throws -> ResponseBody {
        let cleanKey = syncKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanKey.isEmpty else { throw PlaidClientError.missingSyncKey }

        var urlString = configuration.backendURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !urlString.isEmpty else { throw PlaidClientError.missingBackendURL }
        if urlString.hasSuffix("/") {
            urlString.removeLast()
        }
        guard let url = URL(string: urlString + path), url.scheme?.hasPrefix("http") == true else {
            throw PlaidClientError.invalidBackendURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(cleanKey, forHTTPHeaderField: "X-App-Sync-Key")
        if let body {
            request.httpBody = try JSONEncoder.plaidBackend.encode(body)
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw PlaidClientError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else {
            if let error = try? JSONDecoder.plaidBackend.decode(PlaidBackendErrorResponse.self, from: data) {
                throw PlaidClientError.server(error.error)
            }
            throw PlaidClientError.server("Plaid backend request failed with status \(http.statusCode).")
        }
        return try JSONDecoder.plaidBackend.decode(ResponseBody.self, from: data)
    }
}

private struct EmptyRequest: Codable {}

private struct PlaidBackendErrorResponse: Codable {
    var error: String
}

extension JSONDecoder {
    static var plaidBackend: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let value = try container.decode(String.self)
            if let date = Date.plaidLocalDateOnly(from: value) {
                return date
            }
            if let date = ISO8601DateFormatter.plaidBackend.date(from: value) {
                return date
            }
            if let date = ISO8601DateFormatter.plaidBackendWithFractionalSeconds.date(from: value) {
                return date
            }
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Expected ISO 8601 or yyyy-MM-dd date string."
            )
        }
        return decoder
    }
}

extension JSONEncoder {
    static var plaidBackend: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }
}

private extension ISO8601DateFormatter {
    static let plaidBackend: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    static let plaidBackendWithFractionalSeconds: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
}

private extension Date {
    static func plaidLocalDateOnly(from value: String) -> Date? {
        let parts = value.split(separator: "-")
        guard parts.count == 3,
              let year = Int(parts[0]),
              let month = Int(parts[1]),
              let day = Int(parts[2]) else {
            return nil
        }
        return Calendar.current.date(from: DateComponents(year: year, month: month, day: day, hour: 12))
    }
}

enum PlaidKeychain {
    private static let service = "Timothy-Wong.Budgeting-App.Plaid"
    private static let syncKeyAccount = "app-sync-key"

    static func readSyncKey() -> String {
        read(account: syncKeyAccount) ?? ""
    }

    static func saveSyncKey(_ value: String) throws {
        try save(value, account: syncKeyAccount)
    }

    private static func read(account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private static func save(_ value: String, account: String) throws {
        let data = Data(value.utf8)
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
                throw PlaidClientError.server("Could not save Plaid sync key to Keychain.")
            }
        } else if status != errSecSuccess {
            throw PlaidClientError.server("Could not update Plaid sync key in Keychain.")
        }
    }
}

@MainActor
final class PlaidSyncCoordinator {
    static let shared = PlaidSyncCoordinator()

    private static let backendURLKey = "plaid.backendURL"
    private static let lastSuccessfulSyncKey = "plaid.lastSuccessfulSyncAt"
    private static let lastSyncErrorKey = "plaid.lastSyncError"
    private let automaticSyncInterval: TimeInterval = 5 * 60
    private var isSyncing = false

    var lastSuccessfulSyncAt: Date? {
        UserDefaults.standard.object(forKey: Self.lastSuccessfulSyncKey) as? Date
    }

    private init() {}

    @discardableResult
    func sync(budget: BudgetModel, force: Bool = false) async throws -> PlaidSyncResult? {
        guard !isSyncing else { return nil }
        let defaults = UserDefaults.standard
        let backendURL = defaults.string(forKey: Self.backendURLKey)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let syncKey = PlaidKeychain.readSyncKey().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !backendURL.isEmpty, !syncKey.isEmpty else { return nil }

        if !force,
           let lastSync = defaults.object(forKey: Self.lastSuccessfulSyncKey) as? Date,
           Date().timeIntervalSince(lastSync) < automaticSyncInterval {
            return nil
        }

        isSyncing = true
        defer { isSyncing = false }

        do {
            let payload = try await PlaidAPIClient(
                configuration: PlaidBackendConfiguration(backendURL: backendURL),
                syncKey: syncKey
            ).sync()
            let previousReviews = budget.plaidReviewItems
            budget.preparePlaidPendingTransactionReplacements(payload)
            var result = budget.applyPlaidSyncReconciled(payload)
            budget.finalizePlaidHoldingSnapshots(payload)
            result.reviewItems += budget.restoreUnresolvedPlaidReviews(previousReviews, payload: payload)
            budget.saveNow()
            defaults.set(Date(), forKey: Self.lastSuccessfulSyncKey)
            defaults.removeObject(forKey: Self.lastSyncErrorKey)
            return result
        } catch {
            defaults.set(error.localizedDescription, forKey: Self.lastSyncErrorKey)
            throw error
        }
    }
}
