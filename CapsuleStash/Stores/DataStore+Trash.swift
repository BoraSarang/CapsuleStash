import Foundation

// MARK: - T-58 휴지통 (삭제된 문서·블록, 30일 보관 후 자동 완전 삭제)

/// 휴지통 항목. 문서·블록·워크스페이스를 원래 자리 정보와 함께 보관한다.
struct TrashedProject: Hashable, Codable {
    var project: Project
    var workspaceId: UUID
    var workspaceName: String
    var deletedAt: Date
}

struct TrashedWorkspace: Hashable, Codable {
    var workspace: Workspace
    var deletedAt: Date
}

struct TrashedBlock: Hashable, Codable {
    var block: Block
    var deletedAt: Date
}

enum TrashedItem: Identifiable, Hashable {
    case project(TrashedProject)
    case block(TrashedBlock)
    case workspace(TrashedWorkspace)

    var id: UUID {
        switch self {
        case .project(let item): return item.project.id
        case .block(let item): return item.block.id
        case .workspace(let item): return item.workspace.id
        }
    }

    var deletedAt: Date {
        switch self {
        case .project(let item): return item.deletedAt
        case .block(let item): return item.deletedAt
        case .workspace(let item): return item.deletedAt
        }
    }
}

extension TrashedItem: Codable {
    private enum Kind: String, Codable { case project, block, workspace }
    private enum Keys: String, CodingKey { case kind, project, block, workspace }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: Keys.self)
        switch try container.decode(Kind.self, forKey: .kind) {
        case .project:
            self = .project(try container.decode(TrashedProject.self, forKey: .project))
        case .block:
            self = .block(try container.decode(TrashedBlock.self, forKey: .block))
        case .workspace:
            self = .workspace(try container.decode(TrashedWorkspace.self, forKey: .workspace))
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: Keys.self)
        switch self {
        case .project(let item):
            try container.encode(Kind.project, forKey: .kind)
            try container.encode(item, forKey: .project)
        case .block(let item):
            try container.encode(Kind.block, forKey: .kind)
            try container.encode(item, forKey: .block)
        case .workspace(let item):
            try container.encode(Kind.workspace, forKey: .kind)
            try container.encode(item, forKey: .workspace)
        }
    }
}

extension DataStore {
    /// 휴지통 보관일. 지나면 기동 시 자동 완전 삭제한다.
    static let trashLifetime: TimeInterval = 30 * 24 * 3600
    /// 버전 기록 상한 (블록당). 오래된 것부터 버린다.
    static let versionLimit = 20

    /// 휴지통 화면을 연다 (문서 선택 해제).
    func showTrash() {
        selectedProjectId = nil
        isTrashSelected = true
    }

    var trashCount: Int { trash.count }

    // MARK: 영속화 (스마트 그룹과 같은 UserDefaults 방식)

    func loadTrash() {
        guard let data = UserDefaults.standard.data(forKey: Self.trashKey),
              let items = try? JSONDecoder().decode([TrashedItem].self, from: data) else { return }
        trash = items
    }

    func persistTrash() {
        guard persistEnabled else { return }
        if let data = try? JSONEncoder().encode(trash) {
            UserDefaults.standard.set(data, forKey: Self.trashKey)
        }
    }

    /// 기한 지난 항목을 완전 삭제한다 (첨부·시크릿 포함).
    func purgeExpiredTrash(now: Date = Date()) {
        let expired = trash.filter { now.timeIntervalSince($0.deletedAt) > Self.trashLifetime }
        guard !expired.isEmpty else { return }
        for item in expired { deleteForever(item.id) }
        DebugLogger.feature("휴지통 자동 비우기: \(expired.count)개")
    }

    // MARK: 버리기·되돌리기
    //
    // 버리기(deleteBlock/deleteProject → 휴지통)는 DataStore 본체에 있다.
    // 여기서는 꺼내기·완전 삭제·비우기·만료 정리·버전만 다룬다.

    /// 휴지통에서 꺼낸다. 원래 자리가 없으면 Inbox 문서로 (블록) / 첫 Workspace로 (문서).
    /// 워크스페이스는 통째로 복원된다 (ID 유지라 충돌 없음).
    @discardableResult
    func restoreFromTrash(_ id: UUID) -> Bool {
        guard let index = trash.firstIndex(where: { $0.id == id }) else { return false }
        switch trash[index] {
        case .workspace(let item):
            trash.remove(at: index)
            reinsertWorkspace(item.workspace)
            if let first = item.workspace.projects.first { select(first) }
        case .project(let item):
            trash.remove(at: index)
            if workspaces.contains(where: { $0.id == item.workspaceId }) {
                reinsertProject(item.project, to: item.workspaceId)
            } else if !workspaces.isEmpty {
                reinsertProject(item.project, to: workspaces[0].id)
            } else {
                createWorkspace(name: "복원")
                reinsertProject(item.project, to: workspaces[0].id)
            }
            select(item.project)
        case .block(var item):
            trash.remove(at: index)
            if allProjects.contains(where: { $0.project.id == item.block.projectId }) {
                insertBlock(item.block)
            } else {
                let inbox = ensureInboxProject()
                item.block.projectId = inbox.id
                insertBlock(item.block)
            }
        }
        persistTrash()
        commit()
        DebugLogger.feature("휴지통 복원")
        return true
    }

    /// 완전 삭제. 첨부·아카이브·Keychain 시크릿까지 정리한다.
    @discardableResult
    func deleteForever(_ id: UUID) -> Bool {
        guard let index = trash.firstIndex(where: { $0.id == id }) else { return false }
        switch trash.remove(at: index) {
        case .project(let item):
            for block in item.project.blocks { removeBlockFiles(block) }
        case .block(let item):
            removeBlockFiles(item.block)
        case .workspace(let item):
            for project in item.workspace.projects {
                for block in project.blocks { removeBlockFiles(block) }
            }
        }
        persistTrash()
        DebugLogger.feature("휴지통 완전 삭제")
        return true
    }

    /// 휴지통 비우기. - Returns: 지운 항목 수.
    @discardableResult
    func emptyTrash() -> Int {
        let ids = trash.map(\.id)
        for id in ids { deleteForever(id) }
        return ids.count
    }

    // MARK: - 버전 기록

    /// 내용 편집 전 스냅샷을 남긴다. 제목·본문·언어·URL 변경 때만 (접기·순서 변경은 제외).
    /// 호출자가 versions 없이 만든 Block을 넘겨도 현행 기록을 보존한다.
    static func snapshotForUpdate(current: Block, next: Block) -> Block {
        var merged = next
        merged.versions = current.versions
        guard current.title != next.title || current.content != next.content
            || current.language != next.language || current.url != next.url else {
            return merged
        }
        // 거대 본문은 스냅샷 제외 (버전 20개 × 수백KB 폭증 방지). 기록 자체는 유지.
        guard current.content.count <= 100_000 else { return merged }
        let snapshot = BlockVersion(title: current.title, content: current.content,
                                    language: current.language, savedAt: current.updatedAt)
        merged.versions = ([snapshot] + current.versions).prefix(versionLimit).map { $0 }
        return merged
    }

    /// 버전으로 되돌린다. 되돌리기 전 현재 상태도 스냅샷으로 남겨서 취소 가능하다.
    @discardableResult
    func restoreVersion(blockId: UUID, versionId: UUID) -> Bool {
        var restored = false
        mutateBlock(blockId) { block in
            guard let version = block.versions.first(where: { $0.id == versionId }) else { return }
            let current = BlockVersion(title: block.title, content: block.content,
                                       language: block.language, savedAt: block.updatedAt)
            block.versions = ([current] + block.versions.filter { $0.id != versionId })
                .prefix(Self.versionLimit).map { $0 }
            block.title = version.title
            block.content = version.content
            block.language = version.language
            restored = true
        }
        if restored {
            commit()
            DebugLogger.feature("버전 복원")
        }
        return restored
    }
}
