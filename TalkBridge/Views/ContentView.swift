import SwiftUI
import TalkBridgeCore

/// Task 11 暫時版：只確認服務能組裝、能編譯。完整畫面在 Task 12。
struct ContentView: View {
    let environment: AppEnvironment

    var body: some View {
        VStack(spacing: 16) {
            Text("TalkBridge")
                .font(.largeTitle)
            Text(environment.conversation.state.statusText)
            Button("對方說話") { environment.conversation.partnerButtonTapped() }
            Button("我說中文") { environment.conversation.userButtonTapped() }
        }
        .background {
            if let translationService = environment.translationService {
                TranslationHostView(service: translationService)
            }
        }
        .task {
            await environment.conversation.startObservingAudioEvents()
        }
    }
}
