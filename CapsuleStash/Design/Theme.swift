import AppKit
import SwiftUI

// MARK: - T-07 custom 디자인 토큰 (docs/DESIGN.md §2 · docs/mockup-v0.1.html 대응)
//
// 이 디자인 시스템은 라이트(paper) 전용이다. 시스템 다크모드에서는
// TextField/TextEditor/Menu/팝오버 같은 시스템 컨트롤이 뒤집히면서 고정색과 충돌해
// 글자가 안 보이는 등의 깨짐이 발생하므로, 앱 전체 appearance를 라이트로 고정한다.
// 다크모드 대응은 2차(T-18). 모든 화면 색상은 반드시 아래 토큰만 사용한다.

enum Theme {
    /// 앱 기동 시 1회 호출. `CapsuleStashApp.init()` 에서 실행된다.
    /// (`NSApp` 전역은 테스트 프로세스처럼 App 인스턴스가 없을 때 nil이라
    /// `NSApplication.shared` 경유로 설정한다.)
    static func applyFixedAppearance() {
        NSApplication.shared.appearance = NSAppearance(named: .aqua)
        DebugLogger.feature("Appearance 고정: 라이트(aqua) — custom 토큰 전용")
    }

    // MARK: 색

    /// 본문 잉크 (타이틀바 · 블록 헤더 배경)
    static let ink = Color(hex: 0x16150F)
    /// 다크 사이드바 배경
    static let sidebar = Color(hex: 0x1B1A15)
    /// 사이드바 카드/푸터 배경
    static let sidebarElevated = Color(hex: 0x242219)
    /// 사이드바 호버
    static let sidebarHover = Color(hex: 0x2A2820)
    /// 사이드바 구분선
    static let sidebarLine = Color(hex: 0x38352A)
    /// 사이드바 본문 텍스트
    static let sidebarText = Color(hex: 0xD9D3C4)
    /// 사이드바 보조 텍스트
    static let sidebarMuted = Color(hex: 0x8A857A)

    /// 콘텐츠 페이퍼 배경
    static let paper = Color(hex: 0xFAF7F0)
    /// 타이틀바 배경
    static let titlebar = Color(hex: 0xE9E2D3)
    /// 블록 카드 배경
    static let card = Color.white
    /// 카드/ 구분선
    static let line = Color(hex: 0xE8E0D1)
    /// 코드 블록 배경
    static let codeBackground = Color(hex: 0x14130F)
    /// 코드 블록 전경
    static let codeForeground = Color(hex: 0xF2EAD9)
    /// 태그 칩 배경
    static let tagBackground = Color(hex: 0xEFE8D6)
    /// 본문 보조 텍스트
    static let muted = Color(hex: 0x8A857A)

    /// 캡슐 오렌지 액센트
    static let accent = Color(hex: 0xFF5C00)
    static let accentSoft = Color(hex: 0xFFE9D6)
    static let sage = Color(hex: 0x5F6F52)
    static let gold = Color(hex: 0xC99A2E)

    // MARK: 블록 타입 색 (mockup `.type.*` 대응)

    static func badgeColor(for type: BlockType) -> Color {
        switch type {
        case .text, .markdown: return ink
        case .code, .shell: return accent
        case .webLink, .webArchive: return Color(hex: 0x2D5BD7)
        case .image, .file: return sage
        case .credential: return Color(hex: 0x7A2EE0)
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