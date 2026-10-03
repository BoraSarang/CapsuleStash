import Foundation

/// Application Support 아래 JSON 저장소.
/// [HARD] Credential 시크릿은 `DataStore.persistableSnapshot` 단계에서 비워지므로
/// 이 레이어에는 홈페이지·아이디만 기록된다. 시크릿은 Keychain에 별도 보관.
enum PersistenceStore {
    static let directoryName = "CapsuleStash"
    static let fileName = "library.json"

    /// 테스트 격리용. `xcodebuild test` 스킴이 `CAPSULESTASH_TEST_DIR` 환경변수로
    /// 지정하면 실제 Application Support 대신 그 폴더를 쓴다.
    /// (테스트 타깃이 앱을 테스트 호스트로 실행하므로, 없으면 테스트 때마다
    /// 실제 사용자 파일을 읽고 마이그레이션 저장까지 해버린다.)
    static var directoryURL: URL {
        if let testDir = ProcessInfo.processInfo.environment["CAPSULESTASH_TEST_DIR"], !testDir.isEmpty {
            return URL(fileURLWithPath: testDir, isDirectory: true)
        }
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        return base.appendingPathComponent(directoryName, isDirectory: true)
    }

    static var fileURL: URL { directoryURL.appendingPathComponent(fileName) }

    static func load() -> [Workspace]? {
        load(from: fileURL)
    }

    /// 지정 URL에서 읽는다 (T-11 SwiftData 마이그레이션·테스트 격리용).
    static func load(from url: URL) -> [Workspace]? {
        guard FileManager.default.fileExists(atPath: url.path) else {
            DebugLogger.info("저장 파일 없음 — 시드 데이터로 시작")
            return nil
        }
        do {
            let data = try Data(contentsOf: url)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            if let current = try? decoder.decode([Workspace].self, from: data) {
                return current
            }
            // v1(Workspace→Project→Collection) 파일은 2단으로 마이그레이션하고 즉시 v2로 저장한다
            let legacy = try decoder.decode([LegacyV1Workspace].self, from: data)
            let migrated = DataStore.migrate(legacy)
            let docs = migrated.reduce(0) { $0 + $1.projects.count }
            try? save(migrated)
            DebugLogger.feature("v1(3단)→v2(2단) 마이그레이션: 문서 \(docs)개")
            return migrated
        } catch {
            DebugLogger.error(code: ErrorCode.storeCorrupted, "library.json 디코딩 실패")
            return nil
        }
    }

    static func save(_ workspaces: [Workspace]) throws {
        do {
            try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(workspaces)
            try data.write(to: fileURL, options: .atomic)
            DebugLogger.cache("저장 완료: \((data.count / 1024))KB")
        } catch {
            DebugLogger.error(code: ErrorCode.storeSave, "library.json 기록 실패")
            throw error
        }
    }

    /// 첨부 파일(이미지/PDF/아카이브) 보관 폴더
    static func attachmentsURL(kind: String) -> URL {
        directoryURL.appendingPathComponent(kind, isDirectory: true)
    }

    /// 경로 탈출(`..`, `/`) 방지 후 보관 파일 URL 반환 (AttachmentStore·WebArchiveStore 공유).
    static func safeFileURL(kind: String, name: String, baseDirectory: URL? = nil) -> URL? {
        guard !name.isEmpty, !name.contains("/"), !name.contains("..") else { return nil }
        let base = baseDirectory ?? directoryURL
        return base.appendingPathComponent(kind, isDirectory: true).appendingPathComponent(name)
    }
}

// MARK: - v1 (3단: Workspace→Project→Collection) 레거시
// 실제 library.json 구조와 1:1 대응. 디코딩 전용으로만 쓴다.

struct LegacyV1Workspace: Codable {
    let id: UUID
    var name: String
    var projects: [LegacyV1Project]
}

struct LegacyV1Project: Codable {
    let id: UUID
    var workspaceId: UUID
    var name: String
    var colorHex: String
    var collections: [LegacyV1Collection]
}

struct LegacyV1Collection: Codable {
    let id: UUID
    var projectId: UUID
    var title: String
    var note: String
    var tags: [String]
    var isFavorite: Bool
    var createdAt: Date
    var updatedAt: Date
    var blocks: [LegacyV1Block]
}

struct LegacyV1Block: Codable {
    let id: UUID
    var collectionId: UUID
    var type: BlockType
    var title: String
    var content: String
    var language: String?
    var url: String?
    var siteName: String?
    var savedAt: Date?
    var imageNames: [String]
    var credential: Credential?
    var isCollapsed: Bool
    var sortOrder: Int
    var createdAt: Date
    var updatedAt: Date
}