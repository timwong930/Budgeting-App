import SwiftUI

struct PlaidSettingsView: View {
    @ObservedObject var budget: BudgetModel
    @Environment(\.dismiss) private var dismiss
    @AppStorage("plaid.backendURL") private var backendURL = ""

    @StateObject private var linkCoordinator = PlaidLinkCoordinator()
    @State private var ownerUserID: String?
    @State private var isWorking = false
    @State private var statusMessage: String?
    @State private var errorMessage: String?
    @State private var lastResult: PlaidSyncResult?

    private var client: PlaidAPIClient {
        PlaidAPIClient(configuration: PlaidBackendConfiguration(backendURL: backendURL))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Production Backend") {
                    TextField("https://zqjvfmkesfwdtgwkcuxc.functions.supabase.co/functions/v1/plaid", text: $backendURL)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()

                    VStack(alignment: .leading, spacing: 4) {
                        Label("Authenticated Plaid access", systemImage: "lock.shield")
                            .font(.subheadline.weight(.semibold))
                        Text("Plaid requests use a device-bound Supabase user session stored in Keychain. The old shared sync key is only used once to claim existing connections, then removed from this device.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        if let ownerUserID {
                            Text("Owner \(shortOwnerID(ownerUserID))")
                                .font(.caption2.monospaced())
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Section("Sync") {
                    Button {
                        connectAccount(productScope: .banking)
                    } label: {
                        Label("Connect Bank or Card", systemImage: "creditcard")
                    }
                    .disabled(isWorking)

                    Button {
                        connectAccount(productScope: .investments)
                    } label: {
                        Label("Connect Investment Account", systemImage: "chart.line.uptrend.xyaxis")
                    }
                    .disabled(isWorking)

                    Button {
                        syncNow()
                    } label: {
                        Label("Sync Now", systemImage: "arrow.triangle.2.circlepath")
                    }
                    .disabled(isWorking)

                    if isWorking {
                        ProgressView()
                    }
                    if let statusMessage {
                        Text(statusMessage)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if let errorMessage {
                        Text(errorMessage)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                    if let lastResult {
                        PlaidSyncResultSummary(result: lastResult)
                    }
                }

                Section("Linked Institutions") {
                    if budget.plaidConnectionStatuses.isEmpty {
                        Text("No Plaid institutions linked yet.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(budget.plaidConnectionStatuses) { connection in
                            VStack(alignment: .leading, spacing: 6) {
                                HStack {
                                    Text(connection.institutionName)
                                        .font(.headline)
                                    Spacer()
                                    Text(connection.health.rawValue)
                                        .font(.caption)
                                        .foregroundStyle(connection.health == .connected ? .green : .orange)
                                }
                                if let lastSyncedAt = connection.lastSyncedAt {
                                    Text("Last sync \(lastSyncedAt.formatted(date: .abbreviated, time: .shortened))")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                if let errorMessage = connection.errorMessage {
                                    Text(errorMessage)
                                        .font(.caption)
                                        .foregroundStyle(.red)
                                }
                                Button("Disconnect", role: .destructive) {
                                    disconnect(connection)
                                }
                                .font(.caption)
                                .disabled(isWorking)
                            }
                        }
                    }
                }

                Section("Review Queue") {
                    if budget.plaidReviewItems.isEmpty {
                        Text("No Plaid imports need review.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(budget.plaidReviewItems) { item in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(item.title)
                                    .font(.headline)
                                Text(item.detail)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                if let amount = item.amount {
                                    Text(amount, format: .currency(code: "USD"))
                                        .font(.caption)
                                }
                            }
                        }
                        .onDelete { offsets in
                            budget.plaidReviewItems.remove(atOffsets: offsets)
                        }
                    }
                }

                Section("Production Checklist") {
                    Text("Plaid Dashboard must use Production or Limited Production, and the backend domain must be registered as the OAuth redirect URI.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("Universal Links require the Associated Domains entitlement and an apple-app-site-association file served by the backend.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Plaid Sync")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .onAppear {
                loadConnections()
            }
            .onOpenURL { url in
                linkCoordinator.resume(from: url)
            }
        }
    }

    private func connectAccount(productScope: PlaidLinkProductScope) {
        Task {
            await runWork {
                _ = try await prepareAuthenticatedClient()
                let token = try await client.createLinkToken(productScope: productScope)
                await MainActor.run {
                    linkCoordinator.open(
                        linkToken: token.linkToken,
                        onSuccess: { publicToken, institutionName in
                            exchangePublicToken(publicToken, institutionName: institutionName)
                        },
                        onExit: { description in
                            if let description {
                                errorMessage = description
                            }
                            isWorking = false
                        }
                    )
                }
            }
        }
    }

    private func exchangePublicToken(_ publicToken: String, institutionName: String?) {
        Task {
            await runWork {
                _ = try await prepareAuthenticatedClient()
                let response = try await client.exchangePublicToken(
                    PlaidExchangePublicTokenRequest(publicToken: publicToken, institutionName: institutionName)
                )
                budget.plaidConnectionStatuses = response.connections
                try await performSync()
            }
        }
    }

    private func syncNow() {
        Task {
            await runWork {
                try await performSync()
            }
        }
    }

    private func loadConnections() {
        guard !backendURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        Task {
            await runWork {
                let claimed = try await prepareAuthenticatedClient()
                let response = try await client.connections()
                budget.plaidConnectionStatuses = response.connections
                if claimed > 0 {
                    statusMessage = "Secured \(claimed) existing Plaid connection\(claimed == 1 ? "" : "s") to this authenticated owner."
                } else {
                    statusMessage = "Loaded \(response.connections.count) Plaid connection\(response.connections.count == 1 ? "" : "s")."
                }
            }
        }
    }

    private func disconnect(_ connection: PlaidConnectionStatus) {
        Task {
            await runWork {
                _ = try await prepareAuthenticatedClient()
                let response = try await client.disconnect(itemId: connection.itemId)
                budget.plaidConnectionStatuses = response.connections
                statusMessage = "Disconnected \(connection.institutionName)."
            }
        }
    }

    private func performSync() async throws {
        _ = try await prepareAuthenticatedClient()
        let result = try await PlaidSyncCoordinator.shared.sync(budget: budget, force: true)
        lastResult = result
        statusMessage = "Synced Plaid accounts with authenticated ownership."
        errorMessage = nil
    }

    @discardableResult
    private func prepareAuthenticatedClient() async throws -> Int {
        let userID = try await PlaidAuthSessionStore.shared.userId()
        let claim = try await client.claimLegacyOwnershipIfNeeded()
        ownerUserID = userID
        if let claim {
            budget.plaidConnectionStatuses = claim.connections
        }
        return claim?.claimed ?? 0
    }

    private func shortOwnerID(_ value: String) -> String {
        guard value.count > 12 else { return value }
        return "\(value.prefix(8))…\(value.suffix(4))"
    }

    private func runWork(_ operation: @escaping () async throws -> Void) async {
        await MainActor.run {
            isWorking = true
            errorMessage = nil
            statusMessage = nil
        }
        do {
            try await operation()
        } catch {
            await MainActor.run {
                errorMessage = error.localizedDescription
            }
        }
        await MainActor.run {
            isWorking = false
        }
    }
}

private struct PlaidSyncResultSummary: View {
    let result: PlaidSyncResult

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Imported \(result.importedTransactions), reconciled \(result.reconciledTransactions), removed \(result.removedTransactions)")
            Text("Holdings \(result.updatedHoldings), investments \(result.importedInvestmentTransactions), review \(result.reviewItems)")
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }
}
