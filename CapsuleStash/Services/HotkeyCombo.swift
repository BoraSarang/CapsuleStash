import AppKit
import Carbon.HIToolbox
import SwiftUI

/// 글로벌 단축키 조합 + 저장·표시 (T-36).
/// 기본값 `⌘.` (⌘⇧Space 중복 제보로 변경).
struct HotkeyCombo: Equatable {
    var modifiers: NSEvent.ModifierFlags
    var keyCode: UInt32

    static let keyCodeKey = "hotkeyKeyCode"
    static let modifiersKey = "hotkeyModifiers"

    /// 기본값: ⌘. (kVK_ANSI_Period = 47)
    static let `default` = HotkeyCombo(modifiers: [.command], keyCode: 47)

    /// 저장값, 없거나 기록 불가면 기본값. 테스트 격리용으로 값을 주입받는다.
    static func saved(keyCode: Int? = nil, modifiers rawFlags: Int? = nil) -> HotkeyCombo {
        let code = keyCode ?? UserDefaults.standard.object(forKey: keyCodeKey) as? Int
        let raw = rawFlags ?? UserDefaults.standard.object(forKey: modifiersKey) as? Int
        guard let code, code >= 0, let raw, raw >= 0 else { return .default }
        let combo = HotkeyCombo(modifiers: NSEvent.ModifierFlags(rawValue: UInt(raw)),
                                keyCode: UInt32(code))
        return isRecordable(keyCode: combo.keyCode, modifiers: combo.modifiers) ? combo : .default
    }

    func save() {
        UserDefaults.standard.set(Int(keyCode), forKey: Self.keyCodeKey)
        UserDefaults.standard.set(Int(modifiers.rawValue), forKey: Self.modifiersKey)
    }

    /// 표시: "⌘." / "⌘⇧Space". 설정·툴바 힌트용.
    var display: String {
        GlobalHotKeyCenter.describe(modifiers) + Self.keyName(keyCode)
    }

    /// SwiftUI 메뉴 단축키용 문자. 매핑 없으면 nil (내부 단축키 생략).
    var keyEquivalent: KeyEquivalent? {
        guard let char = Self.keyChar(keyCode) else { return nil }
        if modifiers.contains(.shift), char.isLetter,
           let upper = String(char).uppercased().first {
            return KeyEquivalent(upper)
        }
        return KeyEquivalent(char)
    }

    var eventModifiers: SwiftUI.EventModifiers {
        SwiftUI.EventModifiers(rawValue: Int(modifiers.rawValue))
    }

    /// 기록 가능 여부: command 또는 control 포함 + 표시 가능한 키.
    static func isRecordable(keyCode: UInt32, modifiers: NSEvent.ModifierFlags) -> Bool {
        guard keyChar(keyCode) != nil else { return false }
        return modifiers.contains(.command) || modifiers.contains(.control)
    }

    /// 키 표시명 ("Space", ".", "A" …). 모르면 "Key N".
    static func keyName(_ code: UInt32) -> String {
        if code == UInt32(kVK_Space) { return "Space" }
        if let char = keyChar(code) { return String(char).uppercased() }
        return "Key \(code)"
    }

    /// SwiftUI KeyEquivalent용 문자. 없으면 nil.
    static func keyChar(_ code: UInt32) -> Character? {
        switch code {
        case 0: return "a"
        case 1: return "s"
        case 2: return "d"
        case 3: return "f"
        case 4: return "h"
        case 5: return "g"
        case 6: return "z"
        case 7: return "x"
        case 8: return "c"
        case 9: return "v"
        case 11: return "b"
        case 12: return "q"
        case 13: return "w"
        case 14: return "e"
        case 15: return "r"
        case 16: return "y"
        case 17: return "t"
        case 18: return "1"
        case 19: return "2"
        case 20: return "3"
        case 21: return "4"
        case 22: return "6"
        case 23: return "5"
        case 24: return "="
        case 25: return "9"
        case 26: return "7"
        case 27: return "-"
        case 28: return "8"
        case 29: return "0"
        case 30: return "]"
        case 31: return "o"
        case 32: return "u"
        case 33: return "["
        case 34: return "i"
        case 35: return "p"
        case 37: return "l"
        case 38: return "j"
        case 39: return "'"
        case 40: return "k"
        case 41: return ";"
        case 42: return "\\"
        case 43: return ","
        case 44: return "/"
        case 45: return "n"
        case 46: return "m"
        case 47: return "."
        case 50: return "`"
        case UInt32(kVK_Space): return " "
        default: return nil
        }
    }
}
