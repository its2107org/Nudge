import SwiftUI
import UserNotifications
import AppIntents

@main
struct NudgeApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var store = ReminderStore.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(store)
                .task {
                    await AlertScheduler.requestPermissions()
                    await AlertScheduler.rescheduleAll()
                }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                store.reload()
                Task { await AlertScheduler.rescheduleAll() }
            }
        }
    }
}

final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        Task { @MainActor in AlertScheduler.registerCategories() }
        NudgeShortcuts.updateAppShortcutParameters()
        return true
    }

    // Show reminders even while the app is open.
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .sound, .list]
    }

    // "Done" pressed on a notification.
    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        guard response.actionIdentifier == NudgeNotification.doneAction,
              let idString = response.notification.request.content.userInfo[NudgeNotification.reminderKey] as? String,
              let id = UUID(uuidString: idString) else { return }
        await MainActor.run { _ = ReminderStore.shared.markDone(id) }
        await AlertScheduler.rescheduleAll()
    }
}
