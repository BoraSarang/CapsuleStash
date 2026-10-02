import Foundation
import os

// MARK: - 에러 코드 (quality.md 형식: E-{PLATFORM}-{CATEGORY}-{NUM4})

enum ErrorCode {
    static let storeLoad = "E-MAC-STORE-0001"
    static let storeSave = "E-MAC-STORE-0002"
    static let storeCorrupted = "E-MAC-STORE-0003"
    static let keychain = "E-MAC-STORE-0004"
    static let renderBlock = "E-MAC-RENDER-0001"
    static let hotkeyRegister = "E-MAC-HOTKEY-0001"
    static let vaultLocked = "E-MAC-VAULT-0001"
    static let clipboardCopy = "E-MAC-CLIP-0001"
    static let webOpen = "E-MAC-WEB-0001"
    static let launchAtLogin = "E-MAC-LAUNCH-0001"

    /// error_message_ko.json 에서 한국어 메시지를 읽는다. 없으면 code 자체를 반환.
    static func message(_ code: String) -> String {
        ErrorMessages.shared.message(for: code) ?? code
    }
}

// MARK: - DebugPanel용 로그 버퍼

final class DebugLogStore: ObservableObject {
    struct Entry: Identifiable {
        let id = UUID()
        let level: String
        let message: String
        let date: Date
    }

    static let shared = DebugLogStore()

    @Published private(set) var entries: [Entry] = []

    private let limit = 200

    var errorCount: Int { entries.filter { $0.level == "ERROR" }.count }
    var perfEntries: [Entry] { entries.filter { $0.level == "PERF" } }
    var cacheEntries: [Entry] { entries.filter { $0.level == "CACHE" } }

    func append(level: String, message: String) {
        if Thread.isMainThread {
            apply(level: level, message: message)
        } else {
            DispatchQueue.main.async { [weak self] in self?.apply(level: level, message: message) }
        }
    }

    func clear() { entries = [] }

    private func apply(level: String, message: String) {
        entries.append(Entry(level: level, message: message, date: Date()))
        if entries.count > limit {
            entries.removeFirst(entries.count - limit)
        }
    }
}

// MARK: - 로거 (모든 로그 경유 지점)

/// DebugLogger 경유 필수 (quality.md). `[PERF]`, `[CACHE]` 레벨 포함.
/// [HARD] 로그 마스킹: 비밀값은 `mask()` 로만 기록한다.
enum DebugLogger {
    private static let log = Logger(subsystem: "com.borasarang.CapsuleStash", category: "app")

    static func info(_ message: String) {
        record("INFO", message)
        log.info("[CapsuleStash] \(message, privacy: .public)")
    }

    static func feature(_ name: String) {
        record("INFO", "[FEATURE] \(name)")
        log.info("[CapsuleStash] [FEATURE] \(name, privacy: .public)")
    }

    static func perf(_ message: String) {
        record("PERF", "[PERF] \(message)")
        log.info("[CapsuleStash] [PERF] \(message, privacy: .public)")
    }

    static func cache(_ message: String) {
        record("CACHE", "[CACHE] \(message)")
        log.info("[CapsuleStash] [CACHE] \(message, privacy: .public)")
    }

    static func error(code: String, _ message: String) {
        let line = "[ERROR] \(code) \(message) — \(ErrorCode.message(code))"
        record("ERROR", line)
        log.error("[CapsuleStash] \(line, privacy: .public)")
    }

    /// 비밀값 마스킹: 앞 2자만 남기고 나머지를 마스킹. 길이 4 이하는 전부 마스킹.
    static func mask(_ secret: String) -> String {
        guard secret.count > 4 else { return "••••" }
        return String(secret.prefix(2)) + "••••\(secret.count)"
    }

    private static func record(_ level: String, _ message: String) {
        DebugLogStore.shared.append(level: level, message: message)
    }
}

// MARK: - 에러 메시지 테이블

final class ErrorMessages {
    static let shared = ErrorMessages()

    private var table: [String: String] = [:]

    private init() {
        // Bundled 리소스 우선, 실패 시 번들 리소스 경로 재시도, 마지막에 코드 기본값.
        if let url = Bundle.main.url(forResource: "error_message_ko", withExtension: "json"),
           let data = try? Data(contentsOf: url),
           let decoded = try? JSONDecoder().decode([String: String].self, from: data) {
            table = decoded
            DebugLogger.info("에러 메시지 테이블 로드: \(decoded.count)건")
        } else {
            DebugLogger.error(code: ErrorCode.storeLoad, "error_message_ko.json 로드 실패 — 코드값으로 대체")
        }
    }

    func message(for code: String) -> String? { table[code] }
}

// MARK: - 앱 에러 타입

enum CapsuleError: LocalizedError {
    case store(code: String, message: String)
    case render(code: String, message: String)
    case vaultLocked(code: String, message: String)

    var errorDescription: String? {
        switch self {
        case .store(let code, let message), .render(let code, let message), .vaultLocked(let code, let message):
            return "\(code) — \(message.isEmpty ? ErrorCode.message(code) : message)"
        }
    }
}