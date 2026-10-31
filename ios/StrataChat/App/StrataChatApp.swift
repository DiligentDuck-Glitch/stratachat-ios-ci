import SwiftUI

@main
struct StrataChatApp: App {
    @Environment(\.scenePhase) private var scenePhase
    
    init() {
        BackgroundTaskManager.shared.registerBackgroundTasks()
    }
    
    var body: some Scene {
        WindowGroup {
            MainChatView()
                .preferredColorScheme(.dark)
                .onAppear {
                    NotificationManager.shared.requestAuthorization()
                }
        }
        .onChange(of: scenePhase) { phase in
            switch phase {
            case .background:
                BackgroundTaskManager.shared.scheduleAppRefresh()
            case .active:
                break
            case .inactive:
                break
            @unknown default:
                break
            }
        }
    }
}
