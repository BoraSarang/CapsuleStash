import XCTest
@testable import CapsuleStash

/// 단축키·표시 언어 검증.
final class AppSettingsTests: XCTestCase {
    // MARK: - 글로벌 단축키 조합 (T-36)

    func testHotkeyComboDefaults() {
        // 실제 저장값을 건드리지 않게 저장·복원
        let savedCode = UserDefaults.standard.object(forKey: "hotkeyKeyCode")
        let savedMods = UserDefaults.standard.object(forKey: "hotkeyModifiers")
        defer {
            if let savedCode { UserDefaults.standard.set(savedCode, forKey: "hotkeyKeyCode") }
            else { UserDefaults.standard.removeObject(forKey: "hotkeyKeyCode") }
            if let savedMods { UserDefaults.standard.set(savedMods, forKey: "hotkeyModifiers") }
            else { UserDefaults.standard.removeObject(forKey: "hotkeyModifiers") }
        }
        UserDefaults.standard.removeObject(forKey: "hotkeyKeyCode")
        UserDefaults.standard.removeObject(forKey: "hotkeyModifiers")
        XCTAssertEqual(HotkeyCombo.saved(), .default, "미설정 시 기본 ⌘.")
        XCTAssertEqual(HotkeyCombo.default.keyCode, 47, "기본 ⌘. (kVK_ANSI_Period)")
        XCTAssertEqual(HotkeyCombo.default.modifiers, [.command])
        XCTAssertEqual(HotkeyCombo.default.display, "⌘.")
        // 기록 불가 값은 기본값으로 떨어진다
        XCTAssertEqual(HotkeyCombo.saved(keyCode: 9999, modifiers: 1048576), .default)
        XCTAssertEqual(HotkeyCombo.saved(keyCode: 47, modifiers: 0), .default, "수정자 없는 단독 키 금지")
    }

    func testHotkeyKeyNames() {
        XCTAssertEqual(HotkeyCombo.keyName(47), ".")
        XCTAssertEqual(HotkeyCombo.keyName(49), "Space")
        XCTAssertEqual(HotkeyCombo.keyName(0), "A")
        XCTAssertEqual(HotkeyCombo.keyChar(47), ".")
        XCTAssertNil(HotkeyCombo.keyChar(9999))
        XCTAssertTrue(HotkeyCombo.isRecordable(keyCode: 47, modifiers: [.command]))
        XCTAssertTrue(HotkeyCombo.isRecordable(keyCode: 8, modifiers: [.control, .shift]))
        XCTAssertFalse(HotkeyCombo.isRecordable(keyCode: 47, modifiers: [.shift]), "⌘·⌃ 중 하나 필요")
        XCTAssertFalse(HotkeyCombo.isRecordable(keyCode: 9999, modifiers: [.command]))
        XCTAssertEqual(HotkeyCombo(modifiers: [.command, .shift], keyCode: 8).display, "⇧⌘C")
    }

    // MARK: - 표시 언어 (T-25 한·영)
    func testAppLanguageResolve() {
        XCTAssertEqual(AppLanguage.resolve(saved: nil, systemCode: "ko"), "ko", "기본은 시스템 언어")
        XCTAssertEqual(AppLanguage.resolve(saved: nil, systemCode: "en"), "en")
        XCTAssertEqual(AppLanguage.resolve(saved: nil, systemCode: "ja"), "en", "미지원 시스템 언어는 영어")
        XCTAssertEqual(AppLanguage.resolve(saved: nil, systemCode: nil), "en")
        XCTAssertEqual(AppLanguage.resolve(saved: "ko", systemCode: "en"), "ko", "명시 선택 우선")
        XCTAssertEqual(AppLanguage.resolve(saved: "en", systemCode: "ko"), "en")
        XCTAssertEqual(AppLanguage.resolve(saved: "system", systemCode: "ko"), "ko")
        XCTAssertEqual(AppLanguage.resolve(saved: "system", systemCode: "fr"), "en")
    }

    /// 카탈로그 키 정합성. `String(localized:locale:)` 의 locale은 서식용이라
    /// 테이블 선택 검증에는 못 쓴다 — 컴파일된 .strings를 직접 읽는다.
    private func stringsTable(_ locale: String) -> [String: String] {
        guard let url = Bundle.main.url(forResource: "Localizable", withExtension: "strings",
                                        subdirectory: "\(locale).lproj"),
              let dict = NSDictionary(contentsOf: url) as? [String: String] else { return [:] }
        return dict
    }

    func testCatalogStaticStrings() {
        let en = stringsTable("en")
        let ko = stringsTable("ko")
        XCTAssertGreaterThan(en.count, 200, "출하 테이블이 비면 안 됨")
        XCTAssertEqual(Set(en.keys), Set(ko.keys), "한·영 키 대칭 (한쪽만 있으면 반대 언어에서 떨어짐)")
        XCTAssertEqual(en["검색"], "Search")
        XCTAssertEqual(en["취소"], "Cancel")
        XCTAssertEqual(en["계정 정보"], "Account Info")
        XCTAssertEqual(en["언어"], "Language")
        XCTAssertEqual(en["검색: docker, github, swift…"], "Search: docker, github, swift…")
        XCTAssertEqual(en["⌘1 ID ⌘2 PW"], "⌘1 ID ⌘2 Secret")
        XCTAssertEqual(ko["검색"], "검색")
        XCTAssertEqual(ko["취소"], "취소")
    }

    func testCatalogFormatKeys() {
        let en = stringsTable("en")
        XCTAssertEqual(en["블록 %lld개"], "%lld blocks")
        XCTAssertEqual(en["코드 %lld개"], "%lld code blocks")
        XCTAssertEqual(en["이미지 %lld개"], "%lld images")
        XCTAssertEqual(en["수정 %@"], "Modified %@")
        XCTAssertEqual(en["저장 %@"], "Saved %@")
        XCTAssertEqual(en["포함된 블록 %lld개가 모두 사라집니다."], "All %lld blocks will be deleted.")
        XCTAssertEqual(en["포함된 Project %lld개가 모두 사라집니다."], "All %lld projects will be deleted.")
        XCTAssertEqual(en["'%@' 삭제"], "Delete '%@'")
        XCTAssertEqual(en["%@에 새 Project"], "New Project in %@")
        XCTAssertEqual(en["%@ 복사"], "Copy %@")
    }

}
