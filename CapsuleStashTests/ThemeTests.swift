import SwiftUI
import XCTest
@testable import CapsuleStash

/// 디자인 시스템 검증.
final class ThemeTests: XCTestCase {
    // MARK: - 디자인 시스템 (라이트·다크 적응형)

    func testPurposeHintExistsForAllTypes() {
        for type in BlockType.allCases {
            XCTAssertFalse(type.purposeHint.isEmpty, "\(type.rawValue)의 용도 설명이 있어야 함")
        }
        XCTAssertTrue(BlockType.webLink.purposeHint.contains("브라우저"))
        XCTAssertTrue(BlockType.webArchive.purposeHint.contains("오프라인"))
    }

    func testWebHost() {
        let withURL = Block(projectId: UUID(), type: .webLink, title: "x", url: "https://docs.docker.com/reference")
        XCTAssertEqual(withURL.webHost, "docs.docker.com")
        let withoutURL = Block(projectId: UUID(), type: .webLink, title: "x")
        XCTAssertNil(withoutURL.webHost)
        let invalid = Block(projectId: UUID(), type: .webLink, title: "x", url: "not a url %%")
        XCTAssertNil(invalid.webHost)
    }

    // MARK: - 디자인 시스템 (라이트·다크 적응형, T-18)

    func testThemeTokenTableIsComplete() {
        let names = ThemeToken.all.map(\.name)
        XCTAssertEqual(Set(names).count, names.count, "토큰 이름 중복 금지")
        for expected in ["ink", "sidebar", "sidebarElevated", "sidebarHover", "sidebarLine",
                         "sidebarText", "sidebarMuted", "paper", "titlebar", "card", "line",
                         "codeBackground", "codeForeground", "tagBackground", "muted",
                         "accent", "accentSoft", "sage", "gold",
                         "webBlue", "webBlueSoft", "tileTop", "tileBottom", "tileText"] {
            XCTAssertTrue(names.contains(expected), "\(expected) 토큰 누락")
        }
        for token in ThemeToken.all {
            XCTAssertLessThanOrEqual(token.light, 0xFFFFFF, "\(token.name) 라이트값 범위")
            XCTAssertLessThanOrEqual(token.dark, 0xFFFFFF, "\(token.name) 다크값 범위")
        }
    }

    func testThemeDarkValues() {
        func dark(_ name: String) -> String {
            let token = ThemeToken.all.first(where: { $0.name == name })!
            return String(format: "#%06X", token.dark)
        }
        XCTAssertEqual(dark("paper"), "#171613")
        XCTAssertEqual(dark("card"), "#22211C")
        XCTAssertEqual(dark("ink"), "#EDE8DB")
        XCTAssertEqual(dark("webBlue"), "#6B93F5")
        XCTAssertEqual(dark("accentSoft"), "#3A2415")
    }

    func testThemeDarkTokensResolve() {
        XCTAssertEqual(Self.tokenHex(Theme.paper, dark: true), "#171613", "다크 외관에서 페이퍼는 다크값")
        XCTAssertEqual(Self.tokenHex(Theme.card, dark: true), "#22211C")
        XCTAssertEqual(Self.tokenHex(Theme.ink, dark: true), "#EDE8DB")
        XCTAssertEqual(Self.tokenHex(Theme.badgeColor(for: .credential), dark: true), "#A67FF0")
        XCTAssertEqual(Self.tokenHex(Theme.badgeColor(for: .webLink), dark: true), "#6B93F5")
    }

    func testButtonPairsContrastInBothModes() {
        // primary = ink 채움 + paper 글자 — 양 모드에서 구분돼야 함 (하얀 뭉개짐 방지)
        for dark in [false, true] {
            XCTAssertNotEqual(Self.tokenHex(Theme.ink, dark: dark),
                              Self.tokenHex(Theme.paper, dark: dark),
                              "primary 버튼은 글자·채움이 구분돼야 함")
        }
    }

    func testThemeBadgeColorsMatchMockup() {
        XCTAssertEqual(Self.tokenHex(Theme.badgeColor(for: .text)), "#16150F")
        XCTAssertEqual(Self.tokenHex(Theme.badgeColor(for: .markdown)), "#16150F")
        XCTAssertEqual(Self.tokenHex(Theme.badgeColor(for: .code)), "#FF5C00")
        XCTAssertEqual(Self.tokenHex(Theme.badgeColor(for: .shell)), "#FF5C00")
        XCTAssertEqual(Self.tokenHex(Theme.badgeColor(for: .webLink)), "#2D5BD7")
        XCTAssertEqual(Self.tokenHex(Theme.badgeColor(for: .webArchive)), "#2D5BD7")
        XCTAssertEqual(Self.tokenHex(Theme.badgeColor(for: .image)), "#5F6F52")
        XCTAssertEqual(Self.tokenHex(Theme.badgeColor(for: .file)), "#5F6F52")
        XCTAssertEqual(Self.tokenHex(Theme.badgeColor(for: .credential)), "#7A2EE0")
    }

    func testThemeCoreTokensMatchMockup() {
        XCTAssertEqual(Self.tokenHex(Theme.ink), "#16150F")
        XCTAssertEqual(Self.tokenHex(Theme.sidebar), "#1B1A15")
        XCTAssertEqual(Self.tokenHex(Theme.paper), "#FAF7F0")
        XCTAssertEqual(Self.tokenHex(Theme.accent), "#FF5C00")
        XCTAssertEqual(Self.tokenHex(Theme.line), "#E8E0D1")
        XCTAssertEqual(Self.tokenHex(Theme.codeBackground), "#14130F")
    }

    /// SwiftUI Color → sRGB 16진수. 외관을 지정해 라이트·다크를 결정적으로 풀이한다.
    /// (테스트 Mac의 시스템 외관과 무관하게 항상 같은 결과.)
    /// 토큰 테이블이 바뀌면 테스트가 깨진다.
    private static func tokenHex(_ color: Color, dark: Bool = false) -> String {
        let appearance = NSAppearance(named: dark ? .darkAqua : .aqua)!
        var resolved: NSColor = .black
        appearance.performAsCurrentDrawingAppearance {
            resolved = NSColor(color).usingColorSpace(.sRGB) ?? .black
        }
        return String(
            format: "#%02X%02X%02X",
            Int((resolved.redComponent * 255).rounded()),
            Int((resolved.greenComponent * 255).rounded()),
            Int((resolved.blueComponent * 255).rounded())
        )
    }

}
