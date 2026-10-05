import XCTest
@testable import CapsuleStash

/// T-58 휴지통(버리기·복원·완전 삭제·만료 정리) + 버전 기록 검증.
/// UserDefaults 오염 금지: `trash` 키 저장·복원. Keychain은 inMemory 격리.
final class TrashTests: XCTestCase {
    private var savedTrash: Any?

    override func setUp() {
        super.setUp()
        savedTrash = UserDefaults.standard.object(forKey: "trash")
        KeychainStore.inMemory = [:]
    }

    override func tearDown() {
        if let savedTrash {
            UserDefaults.standard.set(savedTrash, forKey: "trash")
        } else {
            UserDefaults.standard.removeObject(forKey: "trash")
        }
        KeychainStore.inMemory = nil
        super.tearDown()
    }

    @MainActor
    private func textBlock(_ store: DataStore, _ project: Project, title: String = "메모") throws -> Block {
        let block = Block(projectId: project.id, type: .text, title: title, content: "본문")
        store.insertBlock(block)
        guard let saved = store.locate(project)?.project.blocks.first(where: { $0.id == block.id }) else {
            throw XCTSkip("블록 저장 필요")
        }
        return saved
    }

    // MARK: - 버리기·복원

    @MainActor
    func testDeleteBlockGoesToTrash() throws {
        let dir = try TestHelpers.makeTempDir()
        let (store, project) = try TestHelpers.makeStoreWithProject(dir: dir)
        let block = try textBlock(store, project)
        store.deleteBlock(block)
        XCTAssertTrue(store.locate(project)?.project.blocks.isEmpty == true)
        XCTAssertEqual(store.trash.count, 1)
        guard case .block(let item) = store.trash.first else { return XCTFail("블록 항목이어야 함") }
        XCTAssertEqual(item.block.id, block.id)
    }

    @MainActor
    func testRestoreBlock() throws {
        let dir = try TestHelpers.makeTempDir()
        let (store, project) = try TestHelpers.makeStoreWithProject(dir: dir)
        let block = try textBlock(store, project)
        store.deleteBlock(block)
        XCTAssertTrue(store.restoreFromTrash(block.id))
        XCTAssertTrue(store.trash.isEmpty)
        XCTAssertEqual(store.locate(project)?.project.blocks.first?.id, block.id)
        XCTAssertFalse(store.restoreFromTrash(block.id), "두 번 복원 금지")
    }

    @MainActor
    func testDeleteRestoreProject() throws {
        let dir = try TestHelpers.makeTempDir()
        let (store, project) = try TestHelpers.makeStoreWithProject(dir: dir)
        _ = try textBlock(store, project)
        let wsId = store.workspaces.first!.id
        store.deleteProject(project)
        XCTAssertTrue(store.workspaces.first!.projects.isEmpty)
        XCTAssertEqual(store.trash.count, 1)
        XCTAssertTrue(store.restoreFromTrash(project.id))
        let restored = store.workspaces.first(where: { $0.id == wsId })?.projects.first
        XCTAssertEqual(restored?.id, project.id)
        XCTAssertEqual(restored?.blocks.count, 1, "블록까지 함께 복원")
    }

    @MainActor
    func testRestoreFallbacks() throws {
        let dir = try TestHelpers.makeTempDir()
        let (store, project) = try TestHelpers.makeStoreWithProject(dir: dir)
        let block = try textBlock(store, project)
        // 블록 먼저 버리고 문서까지 버리면 블록은 Inbox로
        store.deleteBlock(block)
        store.deleteProject(project)
        XCTAssertEqual(store.trash.count, 2)
        XCTAssertTrue(store.restoreFromTrash(block.id))
        XCTAssertEqual(store.ensureInboxProject().blocks.first?.id, block.id)
        // Workspace까지 지우면 문서는 첫 Workspace로
        let wsId = store.workspaces.first!.id
        store.deleteWorkspace(wsId)
        XCTAssertTrue(store.restoreFromTrash(project.id))
        XCTAssertEqual(store.workspaces.first?.projects.first?.id, project.id)
    }

    // MARK: - 완전 삭제 (첨부·시크릿 정리)

    @MainActor
    func testPermanentDeleteRemovesFiles() throws {
        let dir = try TestHelpers.makeTempDir()
        let (store, project) = try TestHelpers.makeStoreWithProject(dir: dir)
        let png = try TestHelpers.makeTestPNG(width: 50, height: 50)
        defer { try? FileManager.default.removeItem(at: png) }
        XCTAssertEqual(store.importFileDrops([png], to: project.id), 1)
        let block = store.locate(project)!.project.blocks.first!
        let stored = AttachmentStore.fileURL(kind: AttachmentStore.imagesKind,
                                             name: block.imageNames[0], baseDirectory: dir)!
        store.deleteBlock(block)
        XCTAssertTrue(FileManager.default.fileExists(atPath: stored.path), "휴지통 보관 중 첨부 유지")
        XCTAssertTrue(store.deleteForever(block.id))
        XCTAssertFalse(FileManager.default.fileExists(atPath: stored.path), "완전 삭제 시 첨부 정리")
        XCTAssertTrue(store.trash.isEmpty)
    }

    @MainActor
    func testPermanentDeleteRemovesSecrets() throws {
        let dir = try TestHelpers.makeTempDir()
        let (store, project) = try TestHelpers.makeStoreWithProject(dir: dir)
        let block = Block(projectId: project.id, type: .credential, title: "GH",
                          credential: Credential(homepage: "https://github.com", username: "me"))
        store.insertBlock(block)
        try KeychainStore.save(blockId: block.id, secrets: .init(password: "pw", secondSecret: ""))
        store.deleteBlock(block)
        XCTAssertNotNil(KeychainStore.load(blockId: block.id), "휴지통 보관 중 시크릿 유지")
        XCTAssertTrue(store.deleteForever(block.id))
        XCTAssertNil(KeychainStore.load(blockId: block.id), "완전 삭제 시 시크릿 정리")
    }

    @MainActor
    func testEmptyTrash() throws {
        let dir = try TestHelpers.makeTempDir()
        let (store, project) = try TestHelpers.makeStoreWithProject(dir: dir)
        _ = try textBlock(store, project, title: "a")
        _ = try textBlock(store, project, title: "b")
        let ids = store.locate(project)!.project.blocks.map(\.id)
        for id in ids {
            store.deleteBlock(store.locate(project)!.project.blocks.first(where: { $0.id == id })!)
        }
        XCTAssertEqual(store.trash.count, 2)
        XCTAssertEqual(store.emptyTrash(), 2)
        XCTAssertTrue(store.trash.isEmpty)
    }

    // MARK: - 만료 정리 (30일)

    @MainActor
    func testPurgeExpiredTrash() throws {
        let dir = try TestHelpers.makeTempDir()
        let (store, project) = try TestHelpers.makeStoreWithProject(dir: dir)
        let block = try textBlock(store, project)
        let old = TrashedBlock(block: block,
                               deletedAt: Date().addingTimeInterval(-31 * 24 * 3600))
        let fresh = TrashedBlock(block: block,
                                 deletedAt: Date().addingTimeInterval(-1 * 24 * 3600))
        store.trash = [.block(old)]
        store.purgeExpiredTrash()
        XCTAssertTrue(store.trash.isEmpty, "31일 지난 건 자동 완전 삭제")
        store.trash = [.block(fresh)]
        store.purgeExpiredTrash()
        XCTAssertEqual(store.trash.count, 1, "1일치는 유지")
    }

    // MARK: - 버전 기록

    @MainActor
    func testVersionSnapshotOnEdit() throws {
        let dir = try TestHelpers.makeTempDir()
        let (store, project) = try TestHelpers.makeStoreWithProject(dir: dir)
        var block = try textBlock(store, project)
        block.content = "바뀐 본문"
        store.updateBlock(block)
        let saved = store.locate(project)!.project.blocks.first!
        XCTAssertEqual(saved.versions.count, 1)
        XCTAssertEqual(saved.versions.first?.content, "본문")
        // 같은 내용 저장은 스냅샷 안 쌓음
        store.updateBlock(saved)
        XCTAssertEqual(store.locate(project)!.project.blocks.first!.versions.count, 1)
    }

    @MainActor
    func testVersionCapAndRestore() throws {
        let dir = try TestHelpers.makeTempDir()
        let (store, project) = try TestHelpers.makeStoreWithProject(dir: dir)
        var block = try textBlock(store, project)
        for i in 0..<25 {
            block.content = "v\(i)"
            store.updateBlock(block)
            block = store.locate(project)!.project.blocks.first!
        }
        XCTAssertEqual(block.versions.count, 20, "상한 20개")
        guard let oldest = block.versions.last else { return XCTFail("버전 없음") }
        XCTAssertTrue(store.restoreVersion(blockId: block.id, versionId: oldest.id))
        let restored = store.locate(project)!.project.blocks.first!
        XCTAssertEqual(restored.content, oldest.content)
        XCTAssertEqual(restored.versions.count, 20, "되돌리기도 스냅샷이라 상한 유지")
        XCTAssertFalse(store.restoreVersion(blockId: block.id, versionId: UUID()), "없는 버전 거부")
    }

    // MARK: - 버전 diff (순수 함수)

    func testDiffDetectsChanges() {
        let result = TextDiff.diff(old: "a\nb\nc", new: "a\nB\nc")
        XCTAssertEqual(result.changed, 2)
        let signs = result.lines.map(\.sign)
        XCTAssertTrue(signs.contains("-") && signs.contains("+"))
        XCTAssertTrue(TextDiff.diff(old: "same", new: "same").lines.isEmpty, "변경 없으면 빈 diff")
        XCTAssertEqual(TextDiff.diff(old: "", new: "").changed, 0)
    }

    func testDiffContextAndCap() {
        let old = (0..<10).map { "line\($0)" }.joined(separator: "\n")
        let new = (0..<10).map { $0 == 5 ? "CHANGED" : "line\($0)" }.joined(separator: "\n")
        let result = TextDiff.diff(old: old, new: new, context: 1, maxLines: 100)
        XCTAssertEqual(result.changed, 2)
        // 문맥 1줄: line4, -line5, +CHANGED, line6
        XCTAssertEqual(result.lines.count, 4)
        let capped = TextDiff.diff(old: old, new: new, context: 9, maxLines: 5)
        XCTAssertGreaterThan(capped.omitted, 0, "초과분 생략 표시")
        XCTAssertEqual(capped.lines.count, 5)
    }

    // MARK: - 워크스페이스 휴지통

    @MainActor
    func testDeleteRestoreWorkspace() throws {
        let dir = try TestHelpers.makeTempDir()
        let (store, project) = try TestHelpers.makeStoreWithProject(dir: dir)
        _ = try textBlock(store, project)
        let wsId = store.workspaces.first!.id
        store.deleteWorkspace(wsId)
        XCTAssertTrue(store.workspaces.isEmpty)
        XCTAssertEqual(store.trash.count, 1)
        guard case .workspace = store.trash.first else { return XCTFail("워크스페이스 항목이어야 함") }
        XCTAssertTrue(store.restoreFromTrash(wsId))
        XCTAssertEqual(store.workspaces.first?.id, wsId, "ID 유지 복원")
        XCTAssertEqual(store.workspaces.first?.projects.first?.blocks.count, 1, "블록까지 함께")
        XCTAssertTrue(store.trash.isEmpty)
    }

    @MainActor
    func testWorkspacePermanentDeleteCleansFiles() throws {
        let dir = try TestHelpers.makeTempDir()
        let (store, project) = try TestHelpers.makeStoreWithProject(dir: dir)
        let png = try TestHelpers.makeTestPNG(width: 40, height: 40)
        defer { try? FileManager.default.removeItem(at: png) }
        XCTAssertEqual(store.importFileDrops([png], to: project.id), 1)
        let name = store.locate(project)!.project.blocks.first!.imageNames[0]
        let stored = AttachmentStore.fileURL(kind: AttachmentStore.imagesKind, name: name, baseDirectory: dir)!
        let wsId = store.workspaces.first!.id
        store.deleteWorkspace(wsId)
        XCTAssertTrue(FileManager.default.fileExists(atPath: stored.path), "보관 중 유지")
        XCTAssertTrue(store.deleteForever(wsId))
        XCTAssertFalse(FileManager.default.fileExists(atPath: stored.path), "완전 삭제 시 정리")
    }

    // MARK: - 고아 첨부 정리

    @MainActor
    func testSweepOrphanAttachments() throws {
        let dir = try TestHelpers.makeTempDir()
        let (store, project) = try TestHelpers.makeStoreWithProject(dir: dir)
        let imgDir = dir.appendingPathComponent(AttachmentStore.imagesKind, isDirectory: true)
        try FileManager.default.createDirectory(at: imgDir, withIntermediateDirectories: true)
        try "keep".write(to: imgDir.appendingPathComponent("keep.png"), atomically: true, encoding: .utf8)
        try "orphan".write(to: imgDir.appendingPathComponent("orphan.png"), atomically: true, encoding: .utf8)
        let block = Block(projectId: project.id, type: .image, title: "I", imageNames: ["keep.png"])
        store.trash = [.block(TrashedBlock(block: block, deletedAt: Date()))]
        store.sweepOrphanAttachments()
        XCTAssertTrue(FileManager.default.fileExists(atPath: imgDir.appendingPathComponent("keep.png").path),
                      "참조 중은 유지 (휴지통 포함)")
        XCTAssertFalse(FileManager.default.fileExists(atPath: imgDir.appendingPathComponent("orphan.png").path),
                       "고아는 삭제")
    }

    // MARK: - 영속화

    @MainActor
    func testTrashPersistsAcrossInstances() throws {
        UserDefaults.standard.removeObject(forKey: "trash")
        let dir = try TestHelpers.makeTempDir()
        let first = DataStore(samples: false, loadSeeds: false, persist: true, attachmentBase: dir)
        first.createWorkspace(name: "W")
        let project = first.createProject(title: "P", in: first.workspaces.first!.id)!
        let block = Block(projectId: project.id, type: .text, title: "t", content: "c")
        first.insertBlock(block)
        first.deleteBlock(block)
        let second = DataStore(samples: false, loadSeeds: false, persist: false)
        XCTAssertEqual(second.trash.count, 1, "재기동 후에도 휴지통 유지")
        guard case .block(let item) = second.trash.first else { return XCTFail("블록 항목이어야 함") }
        XCTAssertEqual(item.block.content, "c")
    }
}
