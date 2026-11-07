import XCTest
@testable import TalkBridgeCore

final class AppErrorTests: XCTestCase {
    private let allErrors: [AppError] = [
        .microphoneDenied, .speechRecognitionDenied, .recognizerUnavailable(localeID: "th-TH"),
        .languageUnsupported, .translationModelNotInstalled, .modelDownloadCancelled,
        .noSpeechDetected, .emptyTranscript, .translationFailed, .synthesisInterrupted,
        .audioSessionFailed, .headsetDisconnected, .appBackgrounded, .audioInterrupted,
        .maxDurationReached, .missingDeviceLanguageResources,
    ]

    func testEveryErrorHasChineseMessageAndRecovery() {
        XCTAssertEqual(allErrors.count, 16)
        for error in allErrors {
            XCTAssertFalse(error.userMessage.isEmpty, "\(error)")
            XCTAssertFalse(error.category.isEmpty, "\(error)")
            XCTAssertFalse(error.recovery.buttonTitle.isEmpty, "\(error)")
        }
        XCTAssertEqual(Set(allErrors.map(\.category)).count, allErrors.count, "每個錯誤的開發分類要不同")
    }

    func testSpecificMappings() {
        XCTAssertEqual(AppError.microphoneDenied.recovery, .openSettings)
        XCTAssertEqual(AppError.speechRecognitionDenied.recovery, .openSettings)
        XCTAssertEqual(AppError.translationModelNotInstalled.recovery, .prepareLanguage)
        XCTAssertEqual(AppError.languageUnsupported.recovery, .chooseAnotherLanguage)
        XCTAssertEqual(AppError.translationFailed.recovery, .retry)
        XCTAssertEqual(AppError.microphoneDenied.userMessage, "沒有麥克風權限，請到「設定」開啟 TalkBridge 的麥克風。")
        XCTAssertEqual(AppError.microphoneDenied.category, "permission.microphone")
    }

    func testRecoveryButtonTitles() {
        XCTAssertEqual(RecoveryAction.openSettings.buttonTitle, "前往設定")
        XCTAssertEqual(RecoveryAction.retry.buttonTitle, "再試一次")
        XCTAssertEqual(RecoveryAction.prepareLanguage.buttonTitle, "下載語言")
        XCTAssertEqual(RecoveryAction.chooseAnotherLanguage.buttonTitle, "換一種語言")
        XCTAssertEqual(RecoveryAction.dismiss.buttonTitle, "知道了")
    }

    func testRecognizerUnavailableMessageNamesNoContent() {
        // 訊息可以提到語言代碼，但不得包含任何使用者說話內容（錯誤型別本身不攜帶內容）。
        XCTAssertTrue(AppError.recognizerUnavailable(localeID: "th-TH").userMessage.contains("th-TH"))
    }
}
