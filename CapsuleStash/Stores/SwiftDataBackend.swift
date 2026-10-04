import Foundation
import SwiftData

// MARK: - T-11 SwiftData 영구 저장소 (하이브리드)
//
// DataStore의 Codable 구조체 인터페이스는 그대로 두고, 저장 백엔드만
// library.json에서 SwiftData(SQLite)로 교체한다. 화면·검색·테스트는 구조체 기준 유지.
// - 시크릿은 DB에 두지 않는다. persistableSnapshot(시크릿 제거済)을 매핑한다.
// - 블록 ID는 그대로 승계한다 (Keychain 항목과 연결되므로 [HARD]).
// - 관계 배열은 순서 미보장이므로 sortOrder로 복원한다 (Project용 순서 필드 추가).
// - DB가 비어 있고 library.json이 있으면 1회 마이그레이션한다.
// - DB 실패 시 JSON 폴백 (데이터 손실 방지).

// MARK: - 엔티티

@Model
final class SDWorkspace {
    @Attribute(.unique) var id: UUID
    var name: String
    /// 순서 (관계·페치 순서 미보장 대응)
    var sortOrder: Int
    @Relationship(deleteRule: .cascade, inverse: \SDProject.workspace)
    var projects: [SDProject]

    init(id: UUID = UUID(), name: String, sortOrder: Int = 0, projects: [SDProject] = []) {
        self.id = id
        self.name = name
        self.sortOrder = sortOrder
        self.projects = projects
    }
}

@Model
final class SDProject {
    @Attribute(.unique) var id: UUID
    var workspaceId: UUID
    var name: String
    var colorHex: String
    var note: String
    var tags: [String]
    var isFavorite: Bool
    var createdAt: Date
    var updatedAt: Date
    /// 워크스페이스 내 순서 (관계 배열 순서 미보장 대응)
    var sortOrder: Int
    @Relationship(deleteRule: .cascade, inverse: \SDBlock.project)
    var blocks: [SDBlock]
    var workspace: SDWorkspace?

    init(id: UUID = UUID(), workspaceId: UUID, name: String,
         colorHex: String = "#FF5C00", note: String = "",
         tags: [String] = [], isFavorite: Bool = false,
         createdAt: Date = Date(), updatedAt: Date = Date(),
         sortOrder: Int = 0, blocks: [SDBlock] = []) {
        self.id = id
        self.workspaceId = workspaceId
        self.name = name
        self.colorHex = colorHex
        self.note = note
        self.tags = tags
        self.isFavorite = isFavorite
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.sortOrder = sortOrder
        self.blocks = blocks
    }
}

@Model
final class SDBlock {
    @Attribute(.unique) var id: UUID
    var projectId: UUID
    var typeRaw: String
    var title: String
    var content: String
    var language: String?
    var url: String?
    var siteName: String?
    var savedAt: Date?
    var imageNames: [String]
    /// 비밀값 아님 (홈페이지·아이디만). 시크릿은 Keychain.
    var credHomepage: String
    var credUsername: String
    var hasCredential: Bool
    /// 웹 아카이브 실파일명 (T-09). 없으면 미저장.
    var archiveFile: String?
    /// 웹 아카이브 PDF 실파일명 (T-09). 없으면 미저장.
    var pdfFile: String?
    /// 웹 아카이브 썸네일 (T-28). 없으면 기본 타일.
    var thumbnailFile: String?
    var isCollapsed: Bool
    var sortOrder: Int
    var createdAt: Date
    var updatedAt: Date
    /// 버전 기록 JSON (BlockVersion 배열 직렬화). Transformable 대신 문자열로 둔다.
    var versionsJSON: String = ""
    var project: SDProject?

    init(id: UUID = UUID(), projectId: UUID, typeRaw: String, title: String,
         content: String = "", language: String? = nil, url: String? = nil,
         siteName: String? = nil, savedAt: Date? = nil, imageNames: [String] = [],
         credHomepage: String = "", credUsername: String = "", hasCredential: Bool = false,
         archiveFile: String? = nil, pdfFile: String? = nil, thumbnailFile: String? = nil,
         isCollapsed: Bool = false, sortOrder: Int = 0,
         createdAt: Date = Date(), updatedAt: Date = Date(),
         versionsJSON: String = "") {
        self.id = id
        self.projectId = projectId
        self.typeRaw = typeRaw
        self.title = title
        self.content = content
        self.language = language
        self.url = url
        self.siteName = siteName
        self.savedAt = savedAt
        self.imageNames = imageNames
        self.credHomepage = credHomepage
        self.credUsername = credUsername
        self.hasCredential = hasCredential
        self.archiveFile = archiveFile
        self.pdfFile = pdfFile
        self.thumbnailFile = thumbnailFile
        self.isCollapsed = isCollapsed
        self.sortOrder = sortOrder
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.versionsJSON = versionsJSON
    }
}

// MARK: - 백엔드

/// DataStore 뒤의 SwiftData 저장소. 구조체 ↔ 엔티티 경계 변환 담당.
enum SwiftDataBackend {
    static let fileName = "database.sqlite"

    /// 테스트 격리용. 기본값은 실제 Application Support (테스트 환경변수 존중).
    static var storeURL: URL {
        PersistenceStore.directoryURL.appendingPathComponent(fileName)
    }

    /// 기동 로드. DB 우선, 비어 있으면 library.json에서 1회 마이그레이션.
    /// 둘 다 없으면 nil (호출자가 시드로 시작).
    static func loadOrMigrate(directory: URL = PersistenceStore.directoryURL) -> [Workspace]? {
        let dbURL = directory.appendingPathComponent(fileName)
        do {
            let context = try makeContext(storeURL: dbURL)
            let stored = try load(from: context)
            if !stored.isEmpty {
                DebugLogger.cache("SwiftData 복원: \(stored.reduce(0) { $0 + $1.projects.count })개 문서")
                return stored
            }
        } catch {
            DebugLogger.error(code: ErrorCode.storeLoad, "SwiftData 열기 실패 — JSON 폴백")
            return PersistenceStore.load()
        }
        // DB 비어 있음 → JSON 마이그레이션 시도
        let jsonURL = directory.appendingPathComponent(PersistenceStore.fileName)
        guard let json = PersistenceStore.load(from: jsonURL), !json.isEmpty else { return nil }
        do {
            let context = try makeContext(storeURL: dbURL)
            insert(json, into: context)
            try context.save()
            DebugLogger.feature("library.json → SwiftData 마이그레이션: \(json.reduce(0) { $0 + $1.projects.count })개 문서")
            // 저장된 상태 그대로 반환 (JSON 원본이 아닌 DB 라운드트립 — 시크릿 제거 보장)
            return try load(from: context)
        } catch {
            DebugLogger.error(code: ErrorCode.storeSave, "SwiftData 마이그레이션 실패 — JSON 사용")
            return json
        }
    }

    /// 전체 스냅샷 저장 (기존 내용 교체).
    /// - Parameter workspaces: `persistableSnapshot` (시크릿 제거済) 을 전달한다.
    static func save(_ workspaces: [Workspace], directory: URL = PersistenceStore.directoryURL) throws {
        do {
            let context = try makeContext(storeURL: directory.appendingPathComponent(fileName))
            let existing = try context.fetch(FetchDescriptor<SDWorkspace>())
            for ws in existing { context.delete(ws) }
            insert(workspaces, into: context)
            try context.save()
            DebugLogger.cache("SwiftData 저장 완료: \(workspaces.reduce(0) { $0 + $1.projects.count })개 문서")
        } catch {
            DebugLogger.error(code: ErrorCode.storeSave, "SwiftData 기록 실패")
            throw error
        }
    }

    // MARK: - 내부

    static func makeContext(storeURL: URL? = nil) throws -> ModelContext {
        let url = storeURL ?? Self.storeURL
        let config = ModelConfiguration(url: url)
        let container = try ModelContainer(
            for: SDWorkspace.self, SDProject.self, SDBlock.self,
            configurations: config
        )
        return ModelContext(container)
    }

    private static func load(from context: ModelContext) throws -> [Workspace] {
        let entities = try context.fetch(FetchDescriptor<SDWorkspace>())
        return entities
            .sorted { $0.sortOrder < $1.sortOrder }
            .map(Workspace.init(entity:))
    }

    private static func insert(_ workspaces: [Workspace], into context: ModelContext) {
        for (wsIndex, ws) in workspaces.enumerated() {
            let wsEntity = SDWorkspace(id: ws.id, name: ws.name, sortOrder: wsIndex)
            for (projectIndex, project) in ws.projects.enumerated() {
                let projectEntity = SDProject(
                    id: project.id, workspaceId: ws.id, name: project.name,
                    colorHex: project.colorHex, note: project.note, tags: project.tags,
                    isFavorite: project.isFavorite, createdAt: project.createdAt,
                    updatedAt: project.updatedAt, sortOrder: projectIndex
                )
                for (blockIndex, block) in project.blocks.enumerated() {
                    projectEntity.blocks.append(SDBlock(entityOf: block, projectId: project.id, sortOrder: blockIndex))
                }
                projectEntity.workspace = wsEntity
                wsEntity.projects.append(projectEntity)
            }
            context.insert(wsEntity)
        }
    }
}

// MARK: - 경계 매핑 (구조체 ↔ 엔티티)

private extension Workspace {
    init(entity: SDWorkspace) {
        self.init(id: entity.id, name: entity.name, projects: entity.projects
            .sorted { $0.sortOrder < $1.sortOrder }
            .map { Project(entity: $0, workspaceId: entity.id) })
    }
}

private extension Project {
    init(entity: SDProject, workspaceId: UUID) {
        self.init(id: entity.id, workspaceId: workspaceId, name: entity.name,
                  colorHex: entity.colorHex, note: entity.note, tags: entity.tags,
                  isFavorite: entity.isFavorite, createdAt: entity.createdAt,
                  updatedAt: entity.updatedAt,
                  blocks: entity.blocks
                      .sorted { $0.sortOrder < $1.sortOrder }
                      .map { Block(entity: $0, projectId: entity.id) })
    }
}

private extension Block {
    init(entity: SDBlock, projectId: UUID) {
        let credential = entity.hasCredential
            ? Credential(homepage: entity.credHomepage, username: entity.credUsername)
            : nil
        var versions: [BlockVersion] = []
        if !entity.versionsJSON.isEmpty,
           let data = entity.versionsJSON.data(using: .utf8) {
            versions = (try? JSONDecoder().decode([BlockVersion].self, from: data)) ?? []
        }
        self.init(id: entity.id, projectId: projectId,
                  type: BlockType(rawValue: entity.typeRaw) ?? .text,
                  title: entity.title, content: entity.content, language: entity.language,
                  url: entity.url, siteName: entity.siteName, savedAt: entity.savedAt,
                  imageNames: entity.imageNames,
                  archiveFile: entity.archiveFile, pdfFile: entity.pdfFile,
                  thumbnailFile: entity.thumbnailFile,
                  credential: credential,
                  isCollapsed: entity.isCollapsed, sortOrder: entity.sortOrder,
                  createdAt: entity.createdAt, updatedAt: entity.updatedAt,
                  versions: versions)
    }
}

private extension SDBlock {
    /// 구조체 → 엔티티. [HARD] 시크릿은 절대 담지 않는다 (호출 전 persistableSnapshot).
    /// 순서는 저장 시점 배열 인덱스로 정규화한다 (동점 sortOrder의 SQLite 비결정 순서 방지).
    convenience init(entityOf block: Block, projectId: UUID, sortOrder: Int) {
        var versionsJSON = ""
        if !block.versions.isEmpty,
           let data = try? JSONEncoder().encode(block.versions) {
            versionsJSON = String(data: data, encoding: .utf8) ?? ""
        }
        self.init(id: block.id, projectId: projectId,
                  typeRaw: block.type.rawValue, title: block.title, content: block.content,
                  language: block.language, url: block.url, siteName: block.siteName,
                  savedAt: block.savedAt, imageNames: block.imageNames,
                  credHomepage: block.credential?.homepage ?? "",
                  credUsername: block.credential?.username ?? "",
                  hasCredential: block.credential != nil,
                  archiveFile: block.archiveFile, pdfFile: block.pdfFile,
                  thumbnailFile: block.thumbnailFile,
                  isCollapsed: block.isCollapsed, sortOrder: sortOrder,
                  createdAt: block.createdAt, updatedAt: block.updatedAt,
                  versionsJSON: versionsJSON)
    }
}
