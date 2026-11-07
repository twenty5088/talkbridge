import SwiftUI
import TalkBridgeCore

/// 聲音「實際」從哪裡出來。
struct AudioRouteView: View {
    let route: AudioRouteInfo

    var body: some View {
        Label {
            Text("聲音輸出：\(route.kind.displayName)")
        } icon: {
            Image(systemName: route.kind.symbolName)
        }
        .font(.callout)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(AccessibilityID.routeView)
    }
}
