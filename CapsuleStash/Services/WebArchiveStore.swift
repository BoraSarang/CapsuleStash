import Foundation

/// 웹 아카이브 실파일 보관소 (T-09).
/// `Application Support/CapsuleStash/{web-archives,pdf}` 아래에 보관하고,
/// `Block.archiveFile`/`pdfFile` 에는 파일명만 기록한다. (바이너리는 로그·검색에 올리지 않는다.)
enum WebArchiveStore {
    static let archiveKind = "web-archives"
    static let pdfKind = "pdf"
    /// 저장 시점 스크린샷 보관 폴더 (T-28).
    static let thumbnailKind = "thumbnails"

    /// Data를 보관 폴더에 쓰고 파일명을 반환한다. 실패 시 nil + 에러 로그.
    /// - Parameters:
    ///   - ext: 확장자 (`pdf` 면 pdf 폴더, 그 외 아카이브 폴더).
    ///   - kind: 지정하면 폴더를 직접 선택 (썸네일용).
    ///   - baseDirectory: 테스트 격리용. 기본값은 실제 Application Support.
    @discardableResult
    static func save(_ data: Data, ext: String, kind: String? = nil,
                     baseDirectory: URL? = nil) -> String? {
        let folder = kind ?? (ext == "pdf" ? pdfKind : archiveKind)
        let dir = (baseDirectory ?? PersistenceStore.directoryURL).appendingPathComponent(folder, isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        } catch {
            DebugLogger.error(code: ErrorCode.storeSave, "아카이브 폴더 생성 실패")
            return nil
        }
        let name = "archive-\(UUID().uuidString.prefix(8)).\(ext)"
        do {
            try data.write(to: dir.appendingPathComponent(name), options: .atomic)
            return name
        } catch {
            // [HARD] paths are user data — log file name only, never contents.
            DebugLogger.error(code: ErrorCode.storeSave, "아카이브 기록 실패: \(name)")
            return nil
        }
    }

    /// 경로 탈출(`..`, `/`) 방지 후 보관 파일 URL 반환. 없으면 nil.
    static func fileURL(kind: String, name: String, baseDirectory: URL? = nil) -> URL? {
        guard !name.isEmpty, !name.contains("/"), !name.contains("..") else { return nil }
        let base = baseDirectory ?? PersistenceStore.directoryURL
        let url = base.appendingPathComponent(kind, isDirectory: true).appendingPathComponent(name)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    static func remove(kind: String, name: String, baseDirectory: URL? = nil) {
        guard !name.isEmpty, !name.contains("/"), !name.contains("..") else { return }
        let base = baseDirectory ?? PersistenceStore.directoryURL
        let url = base
            .appendingPathComponent(kind, isDirectory: true).appendingPathComponent(name)
        try? FileManager.default.removeItem(at: url)
    }

    /// 블록의 아카이브 실파일 존재 여부 (카드 뱃지용).
    static func hasOfflineFiles(for block: Block) -> Bool {
        if let name = block.archiveFile,
           fileURL(kind: archiveKind, name: name) != nil { return true }
        if let name = block.pdfFile,
           fileURL(kind: pdfKind, name: name) != nil { return true }
        return false
    }
}
