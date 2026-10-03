import Foundation

/// T-51 자동 백업 (기동 시 1일 1회 스냅샷, 7세대 보관).
/// 백업 본문은 `LibraryTransfer.exportJSON` 이라 시크릿이 닿지 않는다 ([HARD]).
/// 복원은 가져오기 경로(`importWorkspaces`, 새 ID 재발급)를 재사용한다.
enum BackupStore {
    static let folderName = "backups"
    static let keepGenerations = 7
    static let lastBackupAtKey = "lastBackupAt"
    static let autoBackupEnabledKey = "autoBackupEnabled"

    /// 테스트가 임시 폴더로 바꿔 검증할 수 있게 var.
    static var baseDirectory: URL? = nil

    static var directoryURL: URL {
        (baseDirectory ?? PersistenceStore.directoryURL).appendingPathComponent(folderName, isDirectory: true)
    }

    /// `backup-20261004-003015.json`. 파일명 순 정렬 = 시간 순이라 가지치기가 쉽다.
    static func filename(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "'backup'-yyyyMMdd-HHmmss'.json'"
        return formatter.string(from: date)
    }

    /// 1일 1회: 백업 없으면 true, 마지막 백업과 다른 날이면 true. 순수 함수.
    static func shouldBackup(lastBackup: Date?, now: Date,
                             calendar: Calendar = .current) -> Bool {
        guard let lastBackup else { return true }
        return !calendar.isDate(lastBackup, inSameDayAs: now)
    }

    /// 최신 `keep`개만 남기고 지울 목록. 파일명 정렬 = 시간 정렬. 순수 함수.
    static func pruneCandidates(files: [URL], keep: Int = keepGenerations) -> [URL] {
        let sorted = files.sorted { $0.lastPathComponent > $1.lastPathComponent }
        return Array(sorted.dropFirst(keep))
    }

    static func listBackups() -> [URL] {
        let files = (try? FileManager.default.contentsOfDirectory(
            at: directoryURL, includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles])) ?? []
        return files
            .filter { $0.lastPathComponent.hasPrefix("backup-") && $0.pathExtension == "json" }
            .sorted { $0.lastPathComponent > $1.lastPathComponent }
    }

    /// 백업 1건 기록 + 7세대 가지치기 + 시각 저장. 실패하면 throw.
    @discardableResult
    static func performBackup(workspaces: [Workspace], now: Date = Date()) throws -> URL {
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        let data = try LibraryTransfer.exportJSON(workspaces: workspaces)
        let url = directoryURL.appendingPathComponent(filename(for: now))
        try data.write(to: url, options: .atomic)
        for old in pruneCandidates(files: listBackups()) {
            try? FileManager.default.removeItem(at: old)
        }
        UserDefaults.standard.set(now.timeIntervalSince1970, forKey: lastBackupAtKey)
        // [HARD] paths are user data — log file name only, never contents.
        DebugLogger.cache("백업 기록: \(url.lastPathComponent)")
        return url
    }

    static func savedLastBackupAt() -> Date? {
        let timestamp = UserDefaults.standard.double(forKey: lastBackupAtKey)
        return timestamp > 0 ? Date(timeIntervalSince1970: timestamp) : nil
    }

    static var isAutoBackupEnabled: Bool {
        // 키가 없으면(첫 실행) 켜짐이 기본값.
        UserDefaults.standard.object(forKey: autoBackupEnabledKey) as? Bool ?? true
    }

    /// 기동 시 1회: 자동 백업 켜짐 + 오늘 아직 안 했으면 기록한다. 조용히 실패한다.
    static func maybeBackupIfDue(workspaces: [Workspace], now: Date = Date()) {
        guard isAutoBackupEnabled else { return }
        guard shouldBackup(lastBackup: savedLastBackupAt(), now: now) else { return }
        do {
            try performBackup(workspaces: workspaces, now: now)
        } catch {
            DebugLogger.error(code: ErrorCode.storeSave, "자동 백업 실패")
        }
    }
}
