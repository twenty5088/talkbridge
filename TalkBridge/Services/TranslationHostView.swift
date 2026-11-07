import SwiftUI
import Translation

/// 整個 App 唯一掛 `.translationTask` 的地方（不讓 TranslationSession 散落在各個畫面）。
/// 放在根畫面背景，不佔空間、不給 VoiceOver 讀。
struct TranslationHostView: View {
    let service: AppleTranslationService

    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .translationTask(service.configuration) { session in
                let box = TranslationSessionBox(session: session)
                await AppleTranslationService.process(box, service: service)
            }
            .accessibilityHidden(true)
    }
}
