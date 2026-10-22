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
    @State private var isTransferReviewExpanded = false
    @State private var recentlyDismissedReviews: [PlaidReviewItem] = []
    @State private var matchedTransferToUndo: UUID?
    @State private var showingMatchUndoConfirmation = false

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
                                    if Date().timeIntervalSince(lastSyncedAt) > 24 * 60 * 60 {
                                        Label("Last sync was over 24 hours ago. Balances may be out of date.", systemImage: "exclamationmark.triangle")
                                            .font(.caption)
                                            .foregroundStyle(.orange)
                                    }
                                } else {
                                    Label("No successful sync time available. Balances may be out of date.", systemImage: "clock")
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
                    if !recentlyDismissedReviews.isEmpty {
                        Button {
                            for item in recentlyDismissedReviews {
                                if !budget.plaidReviewItems.contains(where: { $0.sourceId == item.sourceId }) {
                                    budget.plaidReviewItems.append(item)
                                }
                            }
                            recentlyDismissedReviews.removeAll()
                            budget.saveNow()
                        } label: {
                            Label("Undo Review Dismissal", systemImage: "arrow.uturn.backward")
                        }
                    }

                    if budget.plaidReviewItems.isEmpty {
                        Text("No Plaid imports need review.")
                            .foregroundStyle(.secondary)
                    } else {
                        Text("Review uncertain bank movements here. Matching never creates a destination account without a real transaction from that account.")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        ForEach(budget.plaidReviewItems) { item in
                            VStack(alignment: .leading, spacing: 8) {
                                Text(item.title)
                                    .font(.headline)
                                Text(item.detail)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                if let amount = item.amount {
                                    Text(amount, format: .currency(code: "USD"))
                                        .font(.caption)
                                }
                                if let leg = budget.plaidTransferReviewLeg(sourceId: item.sourceId) {
                                    Text("\(leg.accountName) · \(leg.date.formatted(date: .abbreviated, time: .omitted))")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)

                                    let candidates = budget.plaidTransferReviewCandidates(sourceId: item.sourceId)
                                    if !candidates.isEmpty {
                                        Text("Possible matching bank transactions")
                                            .font(.caption.weight(.semibold))
                                        ForEach(candidates) { candidate in
                                            Button {
                                                if budget.confirmPlaidTransferReview(sourceId: item.sourceId, counterpartId: candidate.id) {
                                                    statusMessage = "Bank transfer confirmed between \(leg.accountName) and \(candidate.accountName)."
                                                } else {
                                                    errorMessage = "The candidate is no longer eligible. Sync again and review the latest transactions."
                                                }
                                            } label: {
                                                Label(
                                                    "Confirm with \(candidate.accountName) · \(candidate.date.formatted(date: .abbreviated, time: .omitted))",
                                                    systemImage: "arrow.left.arrow.right.circle"
                                                )
                                            }
                                            .buttonStyle(.bordered)
                                            .disabled(isWorking)
                                        }
                                    } else {
                                        Text("No matching transaction found in another linked bank account.")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    if leg.signedAmount > 0 &&
                                        budget.financialAccounts.contains(where: {
                                            $0.id == leg.accountId && $0.kind == .depository
                                        }) {
                                        Button {
                                            if budget.keepPlaidWithdrawalAsExpense(sourceId: item.sourceId) {
                                                statusMessage = "Kept as withdrawal. This choice will survive future Plaid syncs."
                                            } else {
                                                errorMessage = "Could not confirm this withdrawal. Sync again and review the account."
                                            }
                                        } label: {
                                            Label("Keep as Withdrawal / Expense", systemImage: "checkmark.shield")
                                        }
                                        .buttonStyle(.bordered)
                                        .disabled(isWorking)
                                    }
                                }
                                Text("Swiping to dismiss removes only this reminder, not the transaction. A future sync may flag it again.")
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                            }
                            .padding(.vertical, 6)
                        }
                        .onDelete { offsets in
                            recentlyDismissedReviews = offsets.map { budget.plaidReviewItems[$0] }
                            budget.plaidReviewItems.remove(atOffsets: offsets)
                            budget.saveNow()
                        }
                    }
                }

                Section("Transfer & Card Payment Review") {
                    Toggle("Find matching transactions", isOn: $isTransferReviewExpanded)
                    Text("Only real movements from your connected bank or credit-card accounts can be linked. Matching is never based on amount alone.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if isTransferReviewExpanded {
                        let suggestions = budget.plaidPotentialTransferReviews()
                        if suggestions.isEmpty {
                            Text("No eligible bank or credit-card matches were found. Sync the relevant accounts and check their transaction ledgers.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(suggestions) { source in
                                VStack(alignment: .leading, spacing: 8) {
                                    Text(source.title)
                                        .font(.subheadline.weight(.semibold))
                                    Text("\(source.accountName) · \(source.date.formatted(date: .abbreviated, time: .omitted)) · \(abs(source.signedAmount).formatted(.currency(code: "USD")))")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    ForEach(budget.plaidTransferReviewCandidates(sourceId: source.id)) { candidate in
                                        Button {
                                            if budget.confirmPlaidTransferReview(sourceId: source.id, counterpartId: candidate.id) {
                                                statusMessage = "Confirmed transfer from \(source.accountName) to \(candidate.accountName)."
                                            } else {
                                                errorMessage = "Could not confirm this match. Refresh transactions and try again."
                                            }
                                        } label: {
                                            Label(
                                                "Match with \(candidate.accountName) · \(candidate.date.formatted(date: .abbreviated, time: .omitted))",
                                                systemImage: "checkmark.circle"
                                            )
                                        }
                                        .buttonStyle(.bordered)
                                        .disabled(isWorking)
                                    }
                                    if source.signedAmount > 0 &&
                                        budget.financialAccounts.contains(where: {
                                            $0.id == source.accountId && $0.kind == .depository
                                        }) {
                                        Button("Keep as Withdrawal / Expense") {
                                            if budget.keepPlaidWithdrawalAsExpense(sourceId: source.id) {
                                                statusMessage = "Kept \(source.title) as a withdrawal."
                                            } else {
                                                errorMessage = "Could not classify this transaction. No changes were saved."
                                            }
                                        }
                                        .font(.caption)
                                        .disabled(isWorking)
                                    }
                                }
                                .padding(.vertical, 6)
                            }
                        }
                    }
                }

                Section("Correct a Linked Transfer or Payment") {
                    let linked = Array(budget.cashTransfers.filter {
                        $0.note.hasPrefix("[PLAID_PAIR:")
                    }.sorted { $0.date > $1.date }.prefix(50))
                    if linked.isEmpty {
                        Text("No linked bank or credit-card movements to review.")
                            .foregroundStyle(.secondary)
                    } else {
                        Text("If the wrong accounts were linked, undo the match. Both original transactions will return for review; balances reported by Plaid are not changed.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        ForEach(linked) { transfer in
                            VStack(alignment: .leading, spacing: 6) {
                                Text(transfer.name).font(.subheadline.weight(.semibold))
                                Text("\(transfer.fromAccountName) → \(transfer.toAccountName) · \(transfer.amount.formatted(.currency(code: "USD")))")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                if budget.canUndoPlaidTransferMatch(transferId: transfer.id) {
                                    Button("Undo Incorrect Match", role: .destructive) {
                                        matchedTransferToUndo = transfer.id
                                        showingMatchUndoConfirmation = true
                                    }
                                    .font(.caption)
                                    .disabled(isWorking)
                                } else {
                                    Text("Original transaction details unavailable; this match cannot be undone safely.")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .padding(.vertical, 4)
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
            .confirmationDialog(
                "Undo this account match?",
                isPresented: $showingMatchUndoConfirmation,
                titleVisibility: .visible
            ) {
                Button("Undo Match", role: .destructive) {
                    if let transferId = matchedTransferToUndo,
                       budget.undoPlaidTransferMatch(transferId: transferId) {
                        statusMessage = "Match undone. The original bank movements are ready for review."
                    } else {
                        errorMessage = "Could not restore both original transactions. No changes were made."
                    }
                    matchedTransferToUndo = nil
                }
            } message: {
                Text("The original bank-side transactions will be separated. The rejected pairing will not be recreated automatically.")
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
