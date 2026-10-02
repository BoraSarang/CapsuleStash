import AppKit
import Foundation

/// 클립보드 복사 + 비밀값 자동 삭제.
/// [HARD] 로그에 실제 비밀값을 남기지 않는다.
enum ClipboardService {
    private static var clearTask: Task<Void, Never>?

    /// 마지막에 복사한 비밀값 지문 (종료 시 정리용). 값 자체는 보관하지 않는다.
    private static var lastSecretFingerprint: String?

    @discardableResult
    static func copy(_ text: String, label: String, isSecret: Bool = false) -> Bool {
        guard !text.isEmpty else {
            DebugLogger.error(code: ErrorCode.clipboardCopy, "복사할 내용이 비어 있음: \(label)")
            return false
        }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        guard pasteboard.setString(text, forType: .string) else {
            DebugLogger.error(code: ErrorCode.clipboardCopy, "클립보드 기록 실패: \(label)")
            return false
        }

        if isSecret {
            lastSecretFingerprint = text
            // 0초(안 함)로 설정했으면 자동 삭제를 예약하지 않는다
            if secretClearDelay > 0 {
                scheduleClear(after: secretClearDelay, fingerprint: text)
            }
            // [HARD] 마스킹 로그는 마스킹 문자열만 남긴다.
            DebugLogger.feature("비밀값 복사: \(label) (\(DebugLogger.mask(text))) — \(clearDelayDescription)")
        } else {
            DebugLogger.feature("복사: \(label) (\(text.count)자)")
        }
        return true
    }

    /// 설정(⌘,)에서 변경하는 비밀값 자동 삭제 간격. 기본 30초, 0=안 함.
    static var secretClearDelay: TimeInterval {
        UserDefaults.standard.object(forKey: "clipboardClearDelay") as? Double ?? 30
    }

    static var clearDelayDescription: String {
        let delay = secretClearDelay
        guard delay > 0 else { return "자동 삭제 안 함" }
        return "\(Int(delay))초 후 자동 삭제"
    }

    static func read() -> String? {
        NSPasteboard.general.string(forType: .string)
    }

    /// T-17 종료 시 정리: 클립보드에 마지막 비밀값이 그대로 있으면 비운다.
    /// [HARD] 값 자체를 로그에 남기지 않는다.
    static func clearSecretsOnQuit() {
        guard let fingerprint = lastSecretFingerprint,
              NSPasteboard.general.string(forType: .string) == fingerprint else { return }
        NSPasteboard.general.clearContents()
        lastSecretFingerprint = nil
        DebugLogger.info("종료 시 클립보드의 비밀값을 삭제함")
    }

    /// 지정 시간 뒤, 클립보드에 같은 값이 그대로 있을 때만 비운다.
    private static func scheduleClear(after seconds: TimeInterval, fingerprint: String) {
        clearTask?.cancel()
        clearTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            guard !Task.isCancelled else { return }
            let current = NSPasteboard.general.string(forType: .string)
            guard current == fingerprint else { return }
            NSPasteboard.general.clearContents()
            DebugLogger.info("복사한 비밀값을 클립보드에서 삭제함 (\(Int(seconds))초 경과)")
        }
    }
}