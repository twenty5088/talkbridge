// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "TalkBridgeCore",
    platforms: [.iOS(.v18), .macOS(.v15)],
    products: [
        .library(name: "TalkBridgeCore", targets: ["TalkBridgeCore"]),
        .library(name: "TalkBridgeFakes", targets: ["TalkBridgeFakes"]),
    ],
    targets: [
        .target(name: "TalkBridgeCore"),
        // 只給單元測試與 UI 測試模式使用的假服務，與正式實作分開。
        .target(name: "TalkBridgeFakes", dependencies: ["TalkBridgeCore"]),
        .testTarget(name: "TalkBridgeCoreTests", dependencies: ["TalkBridgeCore", "TalkBridgeFakes"]),
    ],
    swiftLanguageModes: [.v6]
)
