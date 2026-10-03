import AppKit
import Carbon.HIToolbox
import Foundation

/// T-05 글로벌 단축키 수신 (Carbon `RegisterEventHotKey`).
/// 앱이 활성화되지 않은 상태에서도 ⌘⇧Space 로 Command Palette 를 띄운다.
final class GlobalHotKeyCenter {
    static let shared = GlobalHotKeyCenter()

    /// 기본 조합: ⌘. (T-36, HotkeyCombo.default와 동일 유지)
    static let defaultModifiers: NSEvent.ModifierFlags = [.command]
    static let defaultKeyCode: UInt32 = 47 // kVK_ANSI_Period

    private static let signature: OSType = 0x4353_5441 // 'CSTA'

    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?

    /// 등록 성공 여부 (설정 화면 상태 표시용)
    private(set) var isRegistered = false

    private let lock = NSLock()
    private var _trigger: (() -> Void)?

    private init() {}

    private var trigger: (() -> Void)? {
        get { lock.lock(); defer { lock.unlock() }; return _trigger }
        set { lock.lock(); _trigger = newValue; lock.unlock() }
    }

    @discardableResult
    func register(modifiers: NSEvent.ModifierFlags = defaultModifiers,
                  keyCode: UInt32 = defaultKeyCode,
                  onTrigger: @escaping () -> Void) -> Bool {
        unregister()
        trigger = onTrigger

        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                      eventKind: UInt32(kEventHotKeyPressed))

        let callback: EventHandlerUPP = { _, event, userData in
            guard let event, let userData else { return OSStatus(eventNotHandledErr) }
            var hotKeyID = EventHotKeyID()
            let status = GetEventParameter(
                event,
                EventParamName(kEventParamDirectObject),
                EventParamType(typeEventHotKeyID),
                nil,
                MemoryLayout<EventHotKeyID>.size,
                nil,
                &hotKeyID
            )
            guard status == noErr else { return status }
            let center = Unmanaged<GlobalHotKeyCenter>.fromOpaque(userData).takeUnretainedValue()
            guard hotKeyID.signature == GlobalHotKeyCenter.signature else {
                return OSStatus(eventNotHandledErr)
            }
            DispatchQueue.main.async { center.trigger?() }
            return noErr
        }

        let selfPointer = Unmanaged.passUnretained(self).toOpaque()
        let installStatus = InstallEventHandler(
            GetApplicationEventTarget(),
            callback,
            1,
            &eventType,
            selfPointer,
            &handlerRef
        )
        guard installStatus == noErr else {
            DebugLogger.error(code: ErrorCode.hotkeyRegister, "InstallEventHandler 실패 (\(installStatus))")
            return false
        }

        var hotKeyID = EventHotKeyID(signature: GlobalHotKeyCenter.signature, id: 1)
        let registerStatus = RegisterEventHotKey(
            keyCode,
            Self.carbonModifiers(modifiers),
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )
        guard registerStatus == noErr else {
            DebugLogger.error(code: ErrorCode.hotkeyRegister, "RegisterEventHotKey 실패 (\(registerStatus))")
            UnregisterEventHotKeySafely()
            return false
        }

        DebugLogger.feature("글로벌 단축키 등록: \(Self.describe(modifiers))+\(keyCode)")
        isRegistered = true
        return true
    }

    func unregister() {
        UnregisterEventHotKeySafely()
        isRegistered = false
        trigger = nil
    }

    private func UnregisterEventHotKeySafely() {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
            self.hotKeyRef = nil
        }
        if let handlerRef {
            RemoveEventHandler(handlerRef)
            self.handlerRef = nil
        }
    }

    /// NSEvent.ModifierFlags → Carbon 수정자 상수
    static func carbonModifiers(_ flags: NSEvent.ModifierFlags) -> UInt32 {
        var out: UInt32 = 0
        if flags.contains(.command) { out |= UInt32(cmdKey) }
        if flags.contains(.shift) { out |= UInt32(shiftKey) }
        if flags.contains(.option) { out |= UInt32(optionKey) }
        if flags.contains(.control) { out |= UInt32(controlKey) }
        return out
    }

    static func describe(_ flags: NSEvent.ModifierFlags) -> String {
        var parts: [String] = []
        if flags.contains(.control) { parts.append("⌃") }
        if flags.contains(.option) { parts.append("⌥") }
        if flags.contains(.shift) { parts.append("⇧") }
        if flags.contains(.command) { parts.append("⌘") }
        return parts.joined()
    }
}