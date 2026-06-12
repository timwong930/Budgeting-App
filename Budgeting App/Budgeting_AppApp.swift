//
//  Budgeting_AppApp.swift
//  Budgeting App
//
//  Created by Timothy Wong on 1/16/26.
//

import SwiftUI

@main
struct Budgeting_AppApp: App {
    @UIApplicationDelegateAdaptor(BudgetAppDelegate.self) private var appDelegate
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            MomoLaunchSplashContainer(scaleFactor: 1.6) {
                ContentView()
            }
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                Task { @MainActor in
                    let budget = BudgetModel()
                    await BudgetNotificationService.shared.rescheduleNotifications(for: budget)
                }
            }
        }
    }
}

enum PendingDeepLink {
    static var action: DeepLinkAction?
}

enum DeepLinkAction: Equatable {
    case ticker(String)
    case tab(BudgetMode)
    case addIncome
    case addExpense
}
