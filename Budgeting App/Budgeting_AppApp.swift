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

    var body: some Scene {
        WindowGroup {
            ContentView()
                .onAppear {
                    BudgetBackgroundRefreshCoordinator.shared.scheduleAppRefresh()
                }
        }
    }
}
