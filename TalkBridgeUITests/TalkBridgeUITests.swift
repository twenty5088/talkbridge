import TalkBridgeCore
import XCTest

/// UI 測試一律用假服務（launch argument `-fakeScenario`），不依賴真實麥克風、網路或語言模型。
/// 等待一律用 waitForExistence / expectation，不用固定 sleep。
final class TalkBridgeUITests: XCTestCase {
    private let partnerSample = "Where is the train station?"

    override func setUp() {
        continueAfterFailure = false
    }

    @MainActor
    private func launch(_ scenario: String = "happyPath", extraArguments: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-fakeScenario", scenario, "-resetSettings"] + extraArguments
        app.launch()
        return app
    }

    @MainActor
    private func element(_ app: XCUIApplication, _ identifier: String) -> XCUIElement {
        app.descendants(matching: .any)[identifier].firstMatch
    }

    @MainActor
    private func waitForStatus(_ app: XCUIApplication, _ text: String, timeout: TimeInterval = 10,
                               file: StaticString = #filePath, line: UInt = #line) {
        let status = app.staticTexts[AccessibilityID.statusText]
        let predicate = NSPredicate(format: "label == %@", text)
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: status)
        let result = XCTWaiter().wait(for: [expectation], timeout: timeout)
        XCTAssertEqual(result, .completed, "狀態沒有變成「\(text)」，目前是「\(status.label)」", file: file, line: line)
    }

    /// 對方說一句，等到出現第一張對話卡片並播完。
    @MainActor
    private func runPartnerTurn(_ app: XCUIApplication) {
        app.buttons[AccessibilityID.partnerButton].tap()
        XCTAssertTrue(element(app, AccessibilityID.card(0)).waitForExistence(timeout: 10))
        waitForStatus(app, "等待中")
    }

    // 1
    @MainActor
    func testAppLaunches() {
        let app = launch()
        XCTAssertTrue(app.buttons[AccessibilityID.partnerButton].waitForExistence(timeout: 10))
        waitForStatus(app, "等待中")
    }

    // 2
    @MainActor
    func testLanguagePickerSelectsAllFive() {
        let app = launch()
        let picker = app.buttons[AccessibilityID.languagePicker]
        XCTAssertTrue(picker.waitForExistence(timeout: 10))
        for language in PartnerLanguage.allCases {
            picker.tap()
            let option = app.buttons[AccessibilityID.language(language)]
            XCTAssertTrue(option.waitForExistence(timeout: 5), "找不到 \(language.displayName)")
            option.tap()
            XCTAssertEqual(picker.value as? String, language.displayName)
        }
    }

    // 3
    @MainActor
    func testMainButtonsExistAndAreHittable() {
        let app = launch()
        let partner = app.buttons[AccessibilityID.partnerButton]
        let user = app.buttons[AccessibilityID.userButton]
        XCTAssertTrue(partner.waitForExistence(timeout: 10))
        XCTAssertTrue(partner.isHittable)
        XCTAssertTrue(user.isHittable)
        XCTAssertEqual(partner.label, "對方說話")
        XCTAssertEqual(user.label, "我說中文")
        user.tap()
        XCTAssertTrue(app.buttons[AccessibilityID.cancelCountdownButton].waitForExistence(timeout: 10))
        app.buttons[AccessibilityID.stopAllButton].tap()
        waitForStatus(app, "等待中")
    }

    // 4
    @MainActor
    func testPermissionDeniedShowsPermissionView() {
        let app = launch("permissionDenied")
        app.buttons[AccessibilityID.partnerButton].tap()
        XCTAssertTrue(element(app, AccessibilityID.permissionView).waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons[AccessibilityID.openSettingsButton].exists)
        waitForStatus(app, "需要權限")
    }

    // 5
    @MainActor
    func testFakeModeShowsOriginalAndTranslation() {
        let app = launch()
        runPartnerTurn(app)
        let original = element(app, AccessibilityID.cardOriginal(0))
        let translation = element(app, AccessibilityID.cardTranslation(0))
        XCTAssertTrue(original.label.contains(partnerSample))
        XCTAssertTrue(translation.label.contains("[zh-Hant-TW] \(partnerSample)"))
    }

    // 6
    @MainActor
    func testPlaybackControls() {
        let app = launch()
        app.buttons[AccessibilityID.userButton].tap()
        let cancel = app.buttons[AccessibilityID.cancelCountdownButton]
        XCTAssertTrue(cancel.waitForExistence(timeout: 10))
        cancel.tap()
        XCTAssertFalse(element(app, AccessibilityID.countdownText).exists)

        // 重新錄音：重新聽一次，又會進入倒數
        app.buttons[AccessibilityID.rerecordButton].tap()
        XCTAssertTrue(cancel.waitForExistence(timeout: 10))
        cancel.tap()

        // 編輯
        let edited = "Where is the station, please?"
        app.buttons[AccessibilityID.editTranslationButton].tap()
        let editor = app.textFields[AccessibilityID.translationEditor]
        XCTAssertTrue(editor.waitForExistence(timeout: 5))
        // 游標點到最右邊、刪掉原文，輸入整句新的翻譯；換行＝完成，收起鍵盤。
        editor.coordinate(withNormalizedOffset: CGVector(dx: 0.97, dy: 0.5)).tap()
        let current = editor.value as? String ?? ""
        editor.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: current.count + 2))
        editor.typeText(edited + "\n")

        // 播放 → 停止 → 重播
        app.buttons[AccessibilityID.playButton].tap()
        waitForStatus(app, "正在播放")
        app.buttons[AccessibilityID.stopPlaybackButton].tap()
        waitForStatus(app, "準備播放給對方")
        app.buttons[AccessibilityID.replayButton].tap()
        waitForStatus(app, "正在播放")
        // 雲端模擬器偶爾慢（#63 剛好超過 10 秒才回到等待中），等久一點。
        waitForStatus(app, "等待中", timeout: 20)
        XCTAssertEqual(element(app, AccessibilityID.cardTranslation(0)).label, "翻譯：\(edited)")
    }

    // 7
    @MainActor
    func testClearHistory() {
        let app = launch()
        runPartnerTurn(app)
        app.buttons[AccessibilityID.clearHistoryButton].tap()
        XCTAssertFalse(element(app, AccessibilityID.card(0)).exists)
    }

    // 8
    @MainActor
    func testLargestDynamicTypeKeepsControlsVisible() {
        let app = launch(extraArguments: ["-UIPreferredContentSizeCategoryName",
                                          "UICTContentSizeCategoryAccessibilityXXXL"])
        let window = app.windows.firstMatch
        XCTAssertTrue(app.buttons[AccessibilityID.partnerButton].waitForExistence(timeout: 10))
        let expected = [
            AccessibilityID.partnerButton: "對方說話",
            AccessibilityID.userButton: "我說中文",
            AccessibilityID.stopAllButton: "全部停止",
        ]
        for (identifier, label) in expected {
            let button = app.buttons[identifier]
            XCTAssertTrue(button.exists, identifier)
            XCTAssertTrue(button.isHittable, identifier)
            XCTAssertTrue(window.frame.contains(button.frame), "\(identifier) 超出畫面")
            XCTAssertEqual(button.label, label)
        }
    }

    // 9
    @MainActor
    func testAccessibilityIdentifiersExist() {
        let app = launch()
        XCTAssertTrue(app.buttons[AccessibilityID.partnerButton].waitForExistence(timeout: 10))
        for identifier in [AccessibilityID.partnerButton, AccessibilityID.userButton, AccessibilityID.stopAllButton,
                           AccessibilityID.languagePicker, AccessibilityID.modePicker, AccessibilityID.statusView,
                           AccessibilityID.statusText, AccessibilityID.routeView,
                           AccessibilityID.partnerDisplayButton, AccessibilityID.settingsButton] {
            XCTAssertTrue(element(app, identifier).exists, "缺少 \(identifier)")
        }
    }

    // 10
    @MainActor
    func testErrorStateHasRecoveryButton() {
        let app = launch("translationFailure")
        app.buttons[AccessibilityID.partnerButton].tap()
        let recovery = app.buttons[AccessibilityID.recoveryButton]
        XCTAssertTrue(recovery.waitForExistence(timeout: 10))
        XCTAssertEqual(recovery.label, "再試一次")
        waitForStatus(app, "發生錯誤")
        recovery.tap()
        // v2 P7：再試一次用同一句重新翻譯（不用重講），成功後照常播放再回到待機。
        waitForStatus(app, "正在播放")
        waitForStatus(app, "等待中")
    }

    // 11
    @MainActor
    func testPartnerDisplayOpensFlipsAndCloses() {
        let app = launch()
        app.buttons[AccessibilityID.partnerDisplayButton].tap()
        XCTAssertTrue(element(app, AccessibilityID.partnerDisplayView).waitForExistence(timeout: 5))
        let flip = app.buttons[AccessibilityID.flipButton]
        XCTAssertEqual(flip.value as? String, "未翻轉")
        flip.tap()
        XCTAssertEqual(flip.value as? String, "已翻轉")
        app.buttons[AccessibilityID.closePartnerDisplayButton].tap()
        XCTAssertTrue(app.buttons[AccessibilityID.partnerButton].waitForExistence(timeout: 5))
        XCTAssertFalse(element(app, AccessibilityID.partnerDisplayView).exists)
    }

    // 12
    @MainActor
    func testSpeakerOverrideFailureNoticeShown() {
        let app = launch("speakerOverrideFails")
        app.buttons[AccessibilityID.userButton].tap()
        let play = app.buttons[AccessibilityID.playButton]
        XCTAssertTrue(play.waitForExistence(timeout: 10))
        play.tap()
        let notice = element(app, AccessibilityID.noticeView)
        XCTAssertTrue(notice.waitForExistence(timeout: 5))
        XCTAssertTrue(notice.label.contains("外語仍從耳機播出"))
    }

    // 13（語言模型尚未下載）
    @MainActor
    func testLanguageNotReadyOffersDownload() {
        let app = launch("languageNotReady")
        app.buttons[AccessibilityID.partnerButton].tap()
        let recovery = app.buttons[AccessibilityID.recoveryButton]
        XCTAssertTrue(recovery.waitForExistence(timeout: 10))
        XCTAssertEqual(recovery.label, "下載語言")
        waitForStatus(app, "語言模型尚未準備")
        recovery.tap()
        waitForStatus(app, "等待中")
    }

    // 「說完停頓多久才翻譯」：預設 2 秒，可改成其他秒數
    @MainActor
    func testPauseSettingDefaultsToTwoSecondsAndCanChange() {
        let app = launch()
        app.buttons[AccessibilityID.settingsButton].tap()
        let picker = element(app, AccessibilityID.pausePicker)
        XCTAssertTrue(picker.waitForExistence(timeout: 10))
        let defaultText = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label CONTAINS %@", "2 秒（預設）")).firstMatch
        XCTAssertTrue(defaultText.waitForExistence(timeout: 5), "預設要顯示 2 秒")
        picker.tap()
        let three = app.buttons["3 秒"].firstMatch
        XCTAssertTrue(three.waitForExistence(timeout: 5))
        three.tap()
        let chosen = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label CONTAINS %@", "3 秒")).firstMatch
        XCTAssertTrue(chosen.waitForExistence(timeout: 5), "選了 3 秒要顯示出來")
    }

    // v2：倒數中按「我說中文」＝記住下一句，這句照常播完後再聽中文（不中斷）
    @MainActor
    func testQueuedNextSpeakerDuringCountdownPlaysThenListensChineseAgain() {
        let app = launch()
        app.buttons[AccessibilityID.userButton].tap()
        waitForStatus(app, "準備播放給對方", timeout: 15)
        let micHint = element(app, AccessibilityID.microphoneHint)
        XCTAssertTrue(micHint.waitForExistence(timeout: 5))
        XCTAssertTrue(micHint.label.contains("請稍等，麥克風已關閉"), "倒數時要提示麥克風關閉，目前是「\(micHint.label)」")
        app.buttons[AccessibilityID.userButton].tap()
        let queued = element(app, AccessibilityID.queuedHint)
        XCTAssertTrue(queued.waitForExistence(timeout: 5))
        XCTAssertTrue(queued.label.contains("下一句：我說中文"))
        waitForStatus(app, "正在播放", timeout: 15)
        // 手動模式本來播完就停；記住了下一句，所以會再聽一句中文並進入下一次待播。
        waitForStatus(app, "準備播放給對方", timeout: 20)
        XCTAssertFalse(element(app, AccessibilityID.queuedHint).exists, "用掉後不再顯示")
    }

    // Kevin 2026-11-08：設定裡可以替每個語言挑聲音，預設是「自動（品質最好）」
    @MainActor
    func testVoiceSettingDefaultsToAutomaticForEachLanguage() {
        let app = launch()
        app.buttons[AccessibilityID.settingsButton].tap()
        let english = element(app, AccessibilityID.voiceRow("en-US"))
        XCTAssertTrue(english.waitForExistence(timeout: 10))
        XCTAssertTrue(element(app, AccessibilityID.voiceRow("zh-TW")).exists, "中文也要能選聲音")
        XCTAssertTrue(english.label.contains("自動"), "預設是自動，目前是「\(english.label)」")
        english.tap()
        // 雲端模擬器換頁偶爾很慢（#62 曾 5 秒內沒換完），等久一點。
        XCTAssertTrue(element(app, AccessibilityID.voiceAutomatic).waitForExistence(timeout: 15))
    }

    // 2026-11-08 語音輸出總開關：關掉只看文字，對話照常；再按一次恢復
    @MainActor
    func testSpeechToggleShowsTextOnly() {
        let app = launch()
        let toggle = app.buttons[AccessibilityID.speechToggleButton]
        XCTAssertTrue(toggle.waitForExistence(timeout: 10))
        toggle.tap()
        XCTAssertTrue(element(app, AccessibilityID.speechOffHint).waitForExistence(timeout: 5))
        runPartnerTurn(app)
        XCTAssertTrue(element(app, AccessibilityID.cardTranslation(0)).exists, "關掉聲音仍要顯示翻譯")
        toggle.tap()
        XCTAssertFalse(element(app, AccessibilityID.speechOffHint).waitForExistence(timeout: 2))
    }

    // 2026-11-08 加快出聲：一句播完後顯示各階段時間；倒數預設 1 秒
    @MainActor
    func testTimingsShownAfterTurnAndCountdownDefaultsToOneSecond() {
        let app = launch()
        runPartnerTurn(app)
        let timings = element(app, AccessibilityID.timingsText)
        XCTAssertTrue(timings.waitForExistence(timeout: 10))
        XCTAssertTrue(timings.label.contains("翻譯"), "要顯示翻譯花的時間，目前是「\(timings.label)」")
        app.buttons[AccessibilityID.settingsButton].tap()
        XCTAssertTrue(element(app, AccessibilityID.pausePicker).waitForExistence(timeout: 10))
        // 設定清單只建立畫面上看得到的列：倒數選項在下面，要往下捲才會出現。
        let countdown = element(app, AccessibilityID.countdownPicker)
        for _ in 0..<4 where !countdown.exists { app.swipeUp() }
        XCTAssertTrue(countdown.waitForExistence(timeout: 5))
        let defaultText = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label CONTAINS %@", "1 秒（預設）")).firstMatch
        XCTAssertTrue(defaultText.waitForExistence(timeout: 5), "倒數預設要顯示 1 秒")
    }
}
