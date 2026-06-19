import SwiftUI

struct PlaidSettingsView: View {
    @ObservedObject var budget: BudgetModel
    @Environment(\.dismiss) private var dismiss
    @AppStorage("plaid.backendURL") private var backendURL = ""

    @StateObject private var linkCoordinator = PlaidLinkCoordinator()
    @State private var syncKey = PlaidKeychain.readSyncKey()
    @State private var isWorking = false
    @State private var statusMessage: String?
    @State private var errorMessage: String?
    @State private var lastResult: PlaidSyncResult?

    private var client: PlaidAPIClient {
        PlaidAPIClient(
            configuration: PlaidBackendConfiguration(backendURL: backendURL),
            syncKey: syncKey
        )
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Production Backend") {
                    TextField("https://zqjvfmkesfwdtgwkcuxc.functions.supabase.co/functions/v1/plaid", text: $backendURL)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()

                    SecureField("App sync key", text: $syncKey)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()

                    Button("Save Sync Key") {
                        saveSyncKey()
                    }
                    .disabled(syncKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
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

    private func saveSyncKey() {
        do {
            try PlaidKeychain.saveSyncKey(syncKey)
            statusMessage = "Sync key saved to Keychain."
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func connectAccount(productScope: PlaidLinkProductScope) {
        Task {
            await runWork {
                try PlaidKeychain.saveSyncKey(syncKey)
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
                try PlaidKeychain.saveSyncKey(syncKey)
                try await performSync()
            }
        }
    }

    private func loadConnections() {
        guard !backendURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !syncKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return
        }
        Task {
            await runWork {
                let response = try await client.connections()
                budget.plaidConnectionStatuses = response.connections
                statusMessage = "Loaded \(response.connections.count) Plaid connection\(response.connections.count == 1 ? "" : "s")."
            }
        }
    }

    private func disconnect(_ connection: PlaidConnectionStatus) {
        Task {
            await runWork {
                let response = try await client.disconnect(itemId: connection.itemId)
                budget.plaidConnectionStatuses = response.connections
                statusMessage = "Disconnected \(connection.institutionName)."
            }
        }
    }

    private func performSync() async throws {
        let result = try await PlaidSyncCoordinator.shared.sync(budget: budget, force: true)
        lastResult = result
        statusMessage = "Synced Plaid accounts."
        errorMessage = nil
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
