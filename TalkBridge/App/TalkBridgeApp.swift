import SwiftUI

@main
struct TalkBridgeApp: App {
    @State private var environment = AppEnvironment.make()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            ContentView(environment: environment)
        }
        .onChange(of: scenePhase) { _, phase in
            // 不在背景錄音：切到背景就安全停止。
            if phase == .background {
                environment.conversation.appDidEnterBackground()
            }
        }
    }
}
