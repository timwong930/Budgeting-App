import Combine
import SwiftUI

struct InAppNotification: Identifiable, Equatable {
    let id = UUID()
    let title: String
    let message: String
    let symbol: String?
    let tab: String?
    let timestamp = Date()

    static func == (lhs: InAppNotification, rhs: InAppNotification) -> Bool {
        lhs.id == rhs.id
    }
}

@MainActor
final class InAppNotificationService: ObservableObject {
    static let shared = InAppNotificationService()

    @Published var notifications: [InAppNotification] = []

    private var dismissTasks: [UUID: Task<Void, Never>] = [:]

    private init() {}

    func post(title: String, message: String, symbol: String? = nil, tab: String? = nil) {
        let notification = InAppNotification(
            title: title,
            message: message,
            symbol: symbol,
            tab: tab
        )
        notifications.append(notification)

        let id = notification.id
        dismissTasks[id] = Task {
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            await MainActor.run {
                guard !Task.isCancelled else { return }
                self.dismiss(id)
            }
        }
    }

    func dismiss(_ id: UUID) {
        dismissTasks[id]?.cancel()
        dismissTasks[id] = nil
        notifications.removeAll { $0.id == id }
    }
}

struct InAppNotificationBanner: View {
    let notification: InAppNotification
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "bell.fill")
                .font(.caption)
                .foregroundStyle(.white)
                .frame(width: 24, height: 24)
                .background(Circle().fill(Color.accentColor))

            VStack(alignment: .leading, spacing: 1) {
                Text(notification.title)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Text(notification.message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Spacer(minLength: 4)

            Button {
                onDismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.tertiary)
                    .frame(width: 20, height: 20)
            }
            .buttonStyle(.plain)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.regularMaterial)
                .shadow(color: .black.opacity(0.1), radius: 8, y: 4)
        )
        .padding(.horizontal, 12)
        .transition(.move(edge: .top).combined(with: .opacity))
    }
}

struct InAppNotificationOverlay: View {
    @StateObject private var service = InAppNotificationService.shared

    var body: some View {
        VStack(spacing: 8) {
            ForEach(service.notifications) { notification in
                InAppNotificationBanner(
                    notification: notification,
                    onDismiss: { service.dismiss(notification.id) }
                )
                .onTapGesture {
                    service.dismiss(notification.id)
                }
                .transition(.move(edge: .top).combined(with: .opacity))
            }
            Spacer()
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: service.notifications.map(\.id))
        .padding(.top, 12)
    }
}
