import AppKit
import SwiftUI

// MARK: - T-07 custom 디자인 토큰 (docs/DESIGN.md §2 · docs/mockup-v0.1.html 대응)
//
// T-18부터 라이트·다크 적응형이다. 모든 색상은 `ThemeToken.all` 단일 테이블에서 나와
// 라이트/다크 16진수를 한곳에서 관리한다. 테스트는 테이블을 직접 검증한다.
// 외관은 설정(⌘,)의 모양 선택(시스템/라이트/다크)에 따라 `applyAppearance()` 가 바꾼다.

/// 단일 진실 원천: 이름 + 라이트/다크 16진수. `Theme.xxx` 는 여기서 만든 적응형 Color다.
struct ThemeToken: Hashable {
    let name: String
    let light: UInt32
    let dark: UInt32

    static let all: [ThemeToken] = [
        .init(name: "ink", light: 0x16150F, dark: 0xEDE8DB),
        .init(name: "sidebar", light: 0x1B1A15, dark: 0x12110F),
        .init(name: "sidebarElevated", light: 0x242219, dark: 0x1D1C18),
        .init(name: "sidebarHover", light: 0x2A2820, dark: 0x27251F),
        .init(name: "sidebarLine", light: 0x38352A, dark: 0x35322A),
        .init(name: "sidebarText", light: 0xD9D3C4, dark: 0xD9D3C4),
        .init(name: "sidebarMuted", light: 0x8A857A, dark: 0x9A948A),
        .init(name: "paper", light: 0xFAF7F0, dark: 0x171613),
        .init(name: "titlebar", light: 0xE9E2D3, dark: 0x201F1B),
        .init(name: "card", light: 0xFFFFFF, dark: 0x22211C),
        .init(name: "line", light: 0xE8E0D1, dark: 0x35322B),
        .init(name: "codeBackground", light: 0x14130F, dark: 0x0E0D0B),
        .init(name: "codeForeground", light: 0xF2EAD9, dark: 0xF2EAD9),
        .init(name: "tagBackground", light: 0xEFE8D6, dark: 0x2C2A23),
        .init(name: "muted", light: 0x8A857A, dark: 0x9A948A),
        .init(name: "accent", light: 0xFF5C00, dark: 0xFF5C00),
        .init(name: "accentSoft", light: 0xFFE9D6, dark: 0x3A2415),
        .init(name: "sage", light: 0x5F6F52, dark: 0x8BA07B),
        .init(name: "gold", light: 0xC99A2E, dark: 0xC99A2E),
        .init(name: "webBlue", light: 0x2D5BD7, dark: 0x6B93F5),
        .init(name: "webBlueSoft", light: 0xE8F0FF, dark: 0x232E4A),
        .init(name: "tileTop", light: 0xD9CFB8, dark: 0x2E2C26),
        .init(name: "tileBottom", light: 0xA9B39A, dark: 0x232220),
        .init(name: "tileText", light: 0x5C574A, dark: 0xA39E93),
    ]
}

enum Theme {
    /// 모양 모드 (설정 저장 키 `appearanceMode`).
    enum AppearanceMode: String {
        case system, light, dark
    }

    /// 앱 기동·설정 변경 시 호출. `CapsuleStashApp.init()` 에서 실행된다.
    /// (`NSApp` 전역은 테스트 프로세스처럼 App 인스턴스가 없을 때 nil이라
    /// `NSApplication.shared` 경유로 설정한다.)
    static func applyAppearance() {
        let raw = UserDefaults.standard.string(forKey: "appearanceMode") ?? AppearanceMode.system.rawValue
        let mode = AppearanceMode(rawValue: raw) ?? .system
        switch mode {
        case .system: NSApplication.shared.appearance = nil
        case .light: NSApplication.shared.appearance = NSAppearance(named: .aqua)
        case .dark: NSApplication.shared.appearance = NSAppearance(named: .darkAqua)
        }
        DebugLogger.feature("Appearance 적용: \(raw)")
    }

    // MARK: 색 (ThemeToken.all 단일 테이블에서 생성)

    private static func color(_ name: String) -> Color {
        guard let token = ThemeToken.all.first(where: { $0.name == name }) else { return .clear }
        return adaptive(light: token.light, dark: token.dark)
    }

    /// 유효 외관에 따라 라이트/다크 16진수를 고르는 적응형 Color.
    /// 테스트 프로세스(aqua)에선 라이트로 풀린다.
    static func adaptive(light: UInt32, dark: UInt32) -> Color {
        Color(nsColor: NSColor(name: nil, dynamicProvider: { appearance in
            let hex = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
            return NSColor(hex: hex)
        }))
    }

    /// 본문 잉크 (타이틀바 · 블록 헤더 배경)
    static var ink: Color { color("ink") }
    /// 다크 사이드바 배경
    static var sidebar: Color { color("sidebar") }
    /// 사이드바 카드/푸터 배경
    static var sidebarElevated: Color { color("sidebarElevated") }
    /// 사이드바 호버
    static var sidebarHover: Color { color("sidebarHover") }
    /// 사이드바 구분선
    static var sidebarLine: Color { color("sidebarLine") }
    /// 사이드바 본문 텍스트
    static var sidebarText: Color { color("sidebarText") }
    /// 사이드바 보조 텍스트
    static var sidebarMuted: Color { color("sidebarMuted") }

    /// 콘텐츠 페이퍼 배경
    static var paper: Color { color("paper") }
    /// 타이틀바 배경
    static var titlebar: Color { color("titlebar") }
    /// 블록 카드 배경
    static var card: Color { color("card") }
    /// 카드/ 구분선
    static var line: Color { color("line") }
    /// 코드 블록 배경
    static var codeBackground: Color { color("codeBackground") }
    /// 코드 블록 전경
    static var codeForeground: Color { color("codeForeground") }
    /// 태그 칩 배경
    static var tagBackground: Color { color("tagBackground") }
    /// 본문 보조 텍스트
    static var muted: Color { color("muted") }

    /// 캡슐 오렌지 액센트
    static var accent: Color { color("accent") }
    static var accentSoft: Color { color("accentSoft") }
    static var sage: Color { color("sage") }
    static var gold: Color { color("gold") }

    /// 웹 링크 파랑 (뱃지·링크)
    static var webBlue: Color { color("webBlue") }
    static var webBlueSoft: Color { color("webBlueSoft") }
    /// 썸네일 타일 그러데이션·문구
    static var tileTop: Color { color("tileTop") }
    static var tileBottom: Color { color("tileBottom") }
    static var tileText: Color { color("tileText") }

    // MARK: 블록 타입 색 (mockup `.type.*` 대응)

    static func badgeColor(for type: BlockType) -> Color {
        switch type {
        case .text, .markdown: return ink
        case .code, .shell: return accent
        case .webLink, .webArchive: return webBlue
        case .image, .file: return sage
        case .credential: return adaptive(light: 0x7A2EE0, dark: 0xA67FF0)
        }
    }

    /// 프로젝트 색 (hex 문자열 → Color)
    static func color(hexString: String) -> Color {
        Color(hexString: hexString) ?? accent
    }

    // MARK: 폰트

    /// 세리프 표시 제목 (Instrument Serif 대체: macOS 시스템 세리프 New York)
    static func serif(_ size: CGFloat) -> Font {
        .system(size: size, weight: .regular, design: .serif)
    }

    static let monoCaption = Font.system(size: 11, weight: .semibold, design: .monospaced)
    static let monoBody = Font.system(size: 13, design: .monospaced)

    // MARK: 간격

    static let blockSpacing: CGFloat = 14
    static let blockPadding: CGFloat = 16
    static let contentPadding: CGFloat = 30
    static let cardRadius: CGFloat = 14
    static let controlRadius: CGFloat = 8
}

// MARK: - Color 유틸

extension NSColor {
    /// 0xRRGGBB (sRGB). Theme 적응형 Provider용.
    convenience init(hex: UInt32) {
        self.init(
            srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1
        )
    }
}

extension Color {
    /// 0xRRGGBB
    init(hex: UInt32) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: 1
        )
    }

    /// "#RRGGBB" / "RRGGBB" / "#RGB"
    init?(hexString: String) {
        var raw = hexString.trimmingCharacters(in: .whitespacesAndNewlines)
        if raw.hasPrefix("#") { raw.removeFirst() }
        guard let value = UInt32(raw, radix: 16) else { return nil }
        switch raw.count {
        case 3:
            let r = (value >> 8) & 0xF, g = (value >> 4) & 0xF, b = value & 0xF
            self.init(hex: UInt32(r * 17) << 16 | UInt32(g * 17) << 8 | UInt32(b * 17))
        case 6:
            self.init(hex: value)
        case 8:
            self.init(hex: value) // AARRGGBB 중 상위 무시 (투명도는 토큰에서 사용하지 않음)
        default:
            return nil
        }
    }
}