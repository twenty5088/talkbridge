import XCTest
@testable import TalkBridgeCore

final class ConversationStateMachineTests: XCTestCase {
    private let allStates: [ConversationState] = [
        .idle, .listeningToPartner, .transcribingPartner, .translatingToChinese, .speakingChinese,
        .listeningToUser, .transcribingChinese, .translatingToPartnerLanguage,
        .readyToPlayForPartner(countdown: 2), .readyToPlayForPartner(countdown: nil), .speakingPartnerLanguage,
        .needsPermission, .languageNotReady, .error(.translationFailed),
    ]

    func testHappyPathA() throws {
        var machine = ConversationStateMachine()
        for next in [ConversationState.listeningToPartner, .transcribingPartner, .translatingToChinese, .speakingChinese, .idle] {
            try machine.transition(to: next)
        }
        XCTAssertEqual(machine.state, .idle)
    }

    func testHappyPathB() throws {
        var machine = ConversationStateMachine()
        let path: [ConversationState] = [
            .listeningToUser, .transcribingChinese, .translatingToPartnerLanguage,
            .readyToPlayForPartner(countdown: 2), .readyToPlayForPartner(countdown: 1),
            .speakingPartnerLanguage, .readyToPlayForPartner(countdown: nil), .speakingPartnerLanguage, .idle,
        ]
        for next in path { try machine.transition(to: next) }
        XCTAssertEqual(machine.state, .idle)
    }

    func testRejectsDoubleStartListening() throws {
        var machine = ConversationStateMachine()
        try machine.transition(to: .listeningToPartner)
        XCTAssertThrowsError(try machine.transition(to: .listeningToPartner))
        XCTAssertThrowsError(try machine.transition(to: .listeningToUser))
        XCTAssertEqual(machine.state, .listeningToPartner, "被拒絕的轉換不得改變狀態")
    }

    func testRejectsListeningWhileSpeaking() {
        XCTAssertFalse(ConversationStateMachine.isAllowed(from: .speakingChinese, to: .listeningToUser))
        XCTAssertFalse(ConversationStateMachine.isAllowed(from: .speakingChinese, to: .listeningToPartner))
        XCTAssertFalse(ConversationStateMachine.isAllowed(from: .speakingPartnerLanguage, to: .listeningToPartner))
        XCTAssertFalse(ConversationStateMachine.isAllowed(from: .speakingPartnerLanguage, to: .listeningToUser))
    }

    func testListeningOnlyStartsFromIdleOrReadyToPlay() {
        for state in allStates {
            let allowed = ConversationStateMachine.isAllowed(from: state, to: .listeningToUser)
            switch state {
            case .idle, .readyToPlayForPartner: XCTAssertTrue(allowed, "\(state)")   // 重新錄音
            default: XCTAssertFalse(allowed, "\(state)")
            }
            XCTAssertEqual(ConversationStateMachine.isAllowed(from: state, to: .listeningToPartner), state == .idle, "\(state)")
        }
    }

    func testReplayFromIdleAllowed() {
        // 重播只播放、不開麥克風，不違反「播放中不聆聽」。
        XCTAssertTrue(ConversationStateMachine.isAllowed(from: .idle, to: .speakingChinese))
        XCTAssertTrue(ConversationStateMachine.isAllowed(from: .idle, to: .speakingPartnerLanguage))
    }

    func testRejectsSkippingTranslation() {
        XCTAssertFalse(ConversationStateMachine.isAllowed(from: .transcribingPartner, to: .speakingChinese))
        XCTAssertFalse(ConversationStateMachine.isAllowed(from: .transcribingChinese, to: .readyToPlayForPartner(countdown: 2)))
        XCTAssertFalse(ConversationStateMachine.isAllowed(from: .listeningToPartner, to: .translatingToChinese))
    }

    func testRejectsCrossingDirections() {
        XCTAssertFalse(ConversationStateMachine.isAllowed(from: .transcribingPartner, to: .translatingToPartnerLanguage))
        XCTAssertFalse(ConversationStateMachine.isAllowed(from: .translatingToChinese, to: .speakingPartnerLanguage))
    }

    func testAnyStateCanStopOrFail() {
        for state in allStates {
            XCTAssertTrue(ConversationStateMachine.isAllowed(from: state, to: .idle), "\(state)")
            XCTAssertTrue(ConversationStateMachine.isAllowed(from: state, to: .error(.audioInterrupted)), "\(state)")
            XCTAssertTrue(ConversationStateMachine.isAllowed(from: state, to: .needsPermission), "\(state)")
            XCTAssertTrue(ConversationStateMachine.isAllowed(from: state, to: .languageNotReady), "\(state)")
        }
    }

    func testMicrophoneActiveOnlyWhileListening() {
        for state in allStates {
            let expected = state == .listeningToPartner || state == .listeningToUser
            XCTAssertEqual(state.isMicrophoneActive, expected, "\(state)")
        }
        XCTAssertTrue(ConversationState.speakingChinese.isSpeaking)
        XCTAssertTrue(ConversationState.speakingPartnerLanguage.isSpeaking)
        XCTAssertFalse(ConversationState.idle.isSpeaking)
    }

    func testStatusTextsAreChinese() {
        XCTAssertEqual(ConversationState.idle.statusText, "等待中")
        XCTAssertEqual(ConversationState.listeningToPartner.statusText, "正在聆聽")
        XCTAssertEqual(ConversationState.listeningToUser.statusText, "正在聆聽")
        XCTAssertEqual(ConversationState.transcribingPartner.statusText, "正在辨識")
        XCTAssertEqual(ConversationState.transcribingChinese.statusText, "正在辨識")
        XCTAssertEqual(ConversationState.translatingToChinese.statusText, "正在翻譯")
        XCTAssertEqual(ConversationState.translatingToPartnerLanguage.statusText, "正在翻譯")
        XCTAssertEqual(ConversationState.speakingChinese.statusText, "正在播放")
        XCTAssertEqual(ConversationState.speakingPartnerLanguage.statusText, "正在播放")
        XCTAssertEqual(ConversationState.readyToPlayForPartner(countdown: 2).statusText, "準備播放給對方")
        XCTAssertEqual(ConversationState.needsPermission.statusText, "需要權限")
        XCTAssertEqual(ConversationState.languageNotReady.statusText, "語言模型尚未準備")
        XCTAssertEqual(ConversationState.error(.translationFailed).statusText, "發生錯誤")
        for state in allStates { XCTAssertFalse(state.symbolName.isEmpty, "\(state)") }
    }
}
