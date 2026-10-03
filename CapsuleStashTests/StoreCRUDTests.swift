import XCTest
@testable import CapsuleStash

/// 태그·편집·접기·순서·마이그레이션 검증.
final class StoreCRUDTests: XCTestCase {
    // MARK: - 태그 / 블록 편집

    @MainActor
    func testAddTagTrimsHashAndDedupes() {
        let store = TestHelpers.makeStore()
        guard let project = store.selectedProject else { return XCTFail("Project 없음") }
        store.addTag("  #swift  ", to: project)
        XCTAssertTrue(store.selectedProject?.tags.contains("swift") == true)
        let count = store.selectedProject?.tags.count ?? 0
        store.addTag("swift", to: project)
        XCTAssertEqual(store.selectedProject?.tags.count, count, "중복 태그는 추가되면 안 됨")
        store.addTag("   ", to: project)
        XCTAssertEqual(store.selectedProject?.tags.count, count, "빈 태그는 추가되면 안 됨")
    }

    @MainActor
    func testRemoveTag() {
        let store = TestHelpers.makeStore()
        guard let project = store.selectedProject else { return XCTFail("Project 없음") }
        store.addTag("todelete", to: project)
        XCTAssertTrue(store.selectedProject?.tags.contains("todelete") == true)
        store.removeTag("todelete", from: project)
        XCTAssertFalse(store.selectedProject?.tags.contains("todelete") == true)
    }

    @MainActor
    func testUpdateBlockPersistsChanges() {
        let store = TestHelpers.makeStore()
        guard var block = store.selectedProject?.sortedBlocks.first else { return XCTFail("블록 없음") }
        block.title = "바뀐 제목"
        block.content = "바뀐 내용"
        store.updateBlock(block)
        let updated = store.selectedProject?.blocks.first { $0.id == block.id }
        XCTAssertEqual(updated?.title, "바뀐 제목")
        XCTAssertEqual(updated?.content, "바뀐 내용")
    }

    @MainActor
    func testCreateProjectSelectsIt() {
        let store = TestHelpers.makeStore()
        guard let ws = store.workspaces.first else { return XCTFail("시드 Workspace 없음") }
        let project = store.createProject(title: "테스트", in: ws.id)
        XCTAssertNotNil(project)
        XCTAssertEqual(store.selectedProjectId, project?.id, "생성 직후 자동 선택")
    }

    @MainActor
    func testInsertBlockAppendsAtEnd() {
        let store = TestHelpers.makeStore()
        guard let project = store.selectedProject else { return XCTFail("선택된 Project 없음") }
        let before = project.blocks.count
        store.insertBlock(Block(projectId: project.id, type: .markdown, title: "새 노트", content: "내용"))
        XCTAssertEqual(store.selectedProject?.blocks.count, before + 1)
        let inserted = store.selectedProject?.blocks.first { $0.title == "새 노트" }
        XCTAssertNotNil(inserted)
        XCTAssertEqual(inserted?.sortOrder, before, "맨 끝에 추가되어야 함")
        XCTAssertEqual(inserted?.content, "내용", "입력값이 그대로 들어가야 함")
    }

    @MainActor
    func testToggleBlockCollapsed() {
        let store = TestHelpers.makeStore()
        guard let block = store.selectedProject?.sortedBlocks.first else { return XCTFail("블록 없음") }
        XCTAssertFalse(block.isCollapsed)
        store.toggleBlockCollapsed(block)
        let updated = store.selectedProject?.blocks.first { $0.id == block.id }
        XCTAssertEqual(updated?.isCollapsed, true)
    }

    @MainActor
    func testMoveBlockSwapsSortOrder() {
        let store = TestHelpers.makeStore()
        guard let blocks = store.selectedProject?.sortedBlocks, blocks.count >= 2 else { return XCTFail("블록 부족") }
        let first = blocks[0]
        store.moveBlock(first, offset: 1)
        let order = store.selectedProject?.sortedBlocks.map(\.id) ?? []
        XCTAssertEqual(order.first, blocks[1].id, "아래로 이동했으므로 다음 블록이 첫 자리가 됨")
    }

    @MainActor
    func testDeleteBlock() {
        let store = TestHelpers.makeStore()
        guard let block = store.selectedProject?.sortedBlocks.first else { return XCTFail("블록 없음") }
        let before = store.selectedProject?.blocks.count ?? 0
        store.deleteBlock(block)
        XCTAssertEqual(store.selectedProject?.blocks.count, before - 1)
    }

    @MainActor
    func testToggleFavorite() {
        let store = TestHelpers.makeStore()
        guard let project = store.selectedProject else { return XCTFail("Project 없음") }
        let before = project.isFavorite
        store.toggleFavorite(project)
        let updated = store.selectedProject
        XCTAssertNotEqual(updated?.isFavorite, before)
        if updated?.isFavorite == true {
            XCTAssertTrue(store.favoriteProjects.contains { $0.project.id == updated?.id })
        }
    }

    @MainActor
    func testSelectPushesRecentAndExpandsParents() {
        let store = TestHelpers.makeStore()
        guard let target = store.allProjects.last?.project,
              let located = store.locate(target) else { return XCTFail("대상 없음") }
        store.select(target)
        XCTAssertEqual(store.selectedProjectId, target.id)
        XCTAssertEqual(store.recents.first?.id, target.id, "최근 사용 맨 앞")
        XCTAssertTrue(store.expandedWorkspaces.contains(located.workspace.id))
    }

    @MainActor
    func testRecentsDeduplicate() {
        let store = TestHelpers.makeStore()
        guard let target = store.allProjects.first?.project else { return XCTFail("대상 없음") }
        store.select(target)
        store.select(target)
        XCTAssertEqual(store.recents.filter { $0.id == target.id }.count, 1)
    }

    @MainActor
    func testDeleteProjectClearsSelection() {
        let store = TestHelpers.makeStore()
        guard let project = store.selectedProject else { return XCTFail("Project 없음") }
        store.deleteProject(project)
        XCTAssertNotEqual(store.selectedProjectId, project.id)
        XCTAssertTrue(store.recents.allSatisfy { $0.id != project.id })
    }

    @MainActor
    func testStatsCountsMatchTree() {
        let store = TestHelpers.makeStore()
        let stats = Dictionary(uniqueKeysWithValues: store.stats.map { ($0.0, $0.1) })
        XCTAssertEqual(stats["Workspace"], "\(store.workspaces.count)")
        XCTAssertEqual(stats["Project"], "\(store.allProjects.count)")
        let blocks = store.allProjects.reduce(0) { $0 + $1.project.blocks.count }
        XCTAssertEqual(stats["Block"], "\(blocks)")
    }

    @MainActor
    func testPersistableSnapshotStripsCredentials() {
        let store = TestHelpers.makeStore()
        let snapshot = DataStore.persistableSnapshot(from: store.workspaces)
        let credentialBlocks = snapshot.flatMap(\.projects).flatMap(\.blocks).filter { $0.type == .credential }
        XCTAssertFalse(credentialBlocks.isEmpty, "시드에 credential 블록이 있는지 확인")
        for block in credentialBlocks {
            XCTAssertEqual(block.credential?.password, "", "[HARD] 저장 스냅샷에 시크릿이 있으면 안 됨")
            XCTAssertEqual(block.credential?.secondSecret, "", "[HARD] 저장 스냅샷에 두 번째 시크릿이 있으면 안 됨")
            XCTAssertNotNil(block.credential, "홈페이지·아이디(비밀값 아님)는 보관되어야 함")
        }
    }

    // MARK: - 모두 접기·순서 이동 (T-27)

    @MainActor
    func testSetAllBlocksCollapsed() throws {
        let dir = try TestHelpers.makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let (store, project) = try TestHelpers.makeStoreWithProject(dir: dir)
        store.insertBlock(Block(projectId: project.id, type: .text, title: "A", content: "a"))
        store.insertBlock(Block(projectId: project.id, type: .text, title: "B", content: "b"))
        store.setAllBlocksCollapsed(true, in: project.id)
        XCTAssertTrue(store.selectedProject?.blocks.allSatisfy(\.isCollapsed) == true)
        store.setAllBlocksCollapsed(false, in: project.id)
        XCTAssertTrue(store.selectedProject?.blocks.allSatisfy { !$0.isCollapsed } == true)
    }

    @MainActor
    func testMoveBlockTo() throws {
        let dir = try TestHelpers.makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let (store, project) = try TestHelpers.makeStoreWithProject(dir: dir)
        for title in ["A", "B", "C"] {
            store.insertBlock(Block(projectId: project.id, type: .text, title: title, content: title))
        }
        let ids = store.selectedProject?.sortedBlocks.map(\.id) ?? []
        XCTAssertEqual(ids.count, 3)
        XCTAssertTrue(store.moveBlockTo(ids[2], before: ids[0], in: project.id))
        XCTAssertEqual(store.selectedProject?.sortedBlocks.map(\.title), ["C", "A", "B"])
        XCTAssertFalse(store.moveBlockTo(ids[0], before: ids[0], in: project.id), "자기 자신은 무시")
        XCTAssertFalse(store.moveBlockTo(UUID(), before: ids[0], in: project.id), "없는 블록 무시")
        XCTAssertFalse(store.moveBlockTo(ids[0], before: ids[1], in: UUID()), "없는 문서 무시")
    }

    // MARK: - 문서 순서 이동 (T-35)

    @MainActor
    func testMoveProjectTo() {
        let store = TestHelpers.makeStore()
        guard store.workspaces.count >= 1,
              store.workspaces[0].projects.count >= 3 else {
            XCTFail("시드에 Workspace·Project 3개 필요")
            return
        }
        let wsId = store.workspaces[0].id
        let ids = store.workspaces[0].projects.map(\.id)
        let names = store.workspaces[0].projects.map(\.name)
        XCTAssertGreaterThanOrEqual(ids.count, 3)
        XCTAssertTrue(store.moveProjectTo(ids[2], before: ids[0], in: wsId))
        let expectedIDs = [ids[2], ids[0], ids[1]] + Array(ids.dropFirst(3))
        XCTAssertEqual(store.workspaces[0].projects.map(\.id), expectedIDs, "맨 앞으로 이동")
        let expectedNames = [names[2], names[0], names[1]] + Array(names.dropFirst(3))
        XCTAssertEqual(store.workspaces[0].projects.map(\.name), expectedNames)
        XCTAssertFalse(store.moveProjectTo(ids[0], before: ids[0], in: wsId), "자기 자신은 무시")
        XCTAssertFalse(store.moveProjectTo(UUID(), before: ids[0], in: wsId), "없는 문서 무시")
        XCTAssertFalse(store.moveProjectTo(ids[0], before: ids[1], in: UUID()), "없는 공간 무시")
        if store.workspaces.count >= 2 {
            let other = store.workspaces[1].id
            XCTAssertFalse(store.moveProjectTo(ids[0], before: ids[1], in: other),
                           "다른 공간으로는 Workspace 드롭 사용")
        }
    }

    @MainActor
    func testDeleteBlockClearsAttachments() throws {
        KeychainStore.inMemory = [:]
        defer { KeychainStore.inMemory = nil }
        let dir = try TestHelpers.makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let imgDir = dir.appendingPathComponent(AttachmentStore.imagesKind, isDirectory: true)
        try FileManager.default.createDirectory(at: imgDir, withIntermediateDirectories: true)
        try "x".write(to: imgDir.appendingPathComponent("gone.png"), atomically: true, encoding: .utf8)

        let store = DataStore(samples: false, loadSeeds: false, persist: false, attachmentBase: dir)
        store.createWorkspace(name: "W")
        guard let ws = store.workspaces.first,
              let project = store.createProject(title: "P", in: ws.id) else {
            return XCTFail("Workspace·Project 필요")
        }
        let block = Block(projectId: project.id, type: .image, title: "I", imageNames: ["gone.png"])
        store.insertBlock(block)
        store.deleteBlock(block)
        XCTAssertFalse(FileManager.default.fileExists(atPath: imgDir.appendingPathComponent("gone.png").path),
                       "삭제된 블록의 첨부는 함께 지워야 함")
    }

    @MainActor
    func testVaultToggle() {
        let store = TestHelpers.makeStore()
        XCTAssertFalse(store.isVaultUnlocked)
        store.unlockVault()
        XCTAssertTrue(store.isVaultUnlocked)
        store.lockVault()
        XCTAssertFalse(store.isVaultUnlocked)
    }

    @MainActor
    func testLockVaultOnQuitIfNeeded() {
        UserDefaults.standard.removeObject(forKey: "vaultLockOnQuit")
        defer { UserDefaults.standard.removeObject(forKey: "vaultLockOnQuit") }
        let store = TestHelpers.makeStore()
        store.unlockVault()
        // 기본 켜짐 → 잠금 (클립보드는 건드리지 않음: 지문 없음)
        store.lockVaultOnQuitIfNeeded()
        XCTAssertFalse(store.isVaultUnlocked)
        // 꺼져 있으면 유지
        UserDefaults.standard.set(false, forKey: "vaultLockOnQuit")
        store.unlockVault()
        store.lockVaultOnQuitIfNeeded()
        XCTAssertTrue(store.isVaultUnlocked, "옵션 OFF면 종료 시에도 잠그지 않음")
        store.lockVault()
    }

    func testDockIconHiddenByDefault() {
        UserDefaults.standard.removeObject(forKey: "showDockIcon")
        let show = UserDefaults.standard.object(forKey: "showDockIcon") as? Bool ?? false
        XCTAssertFalse(show, "Dock 아이콘 기본값은 숨김(아니오)")
    }

    // MARK: - v1 → v2 마이그레이션

    func testLegacyMigrationLiftsCollections() {
        let wsId = UUID()
        let groupId = UUID()
        let docId = UUID()
        let blockId = UUID()
        let now = Date()
        let legacy = [
            LegacyV1Workspace(id: wsId, name: "개발", projects: [
                LegacyV1Project(id: groupId, workspaceId: wsId, name: "macOS 앱", colorHex: "#FF5C00", collections: [
                    LegacyV1Collection(
                        id: docId, projectId: groupId, title: "WKWebView", note: "메모",
                        tags: ["webkit"], isFavorite: true,
                        createdAt: now, updatedAt: now,
                        blocks: [LegacyV1Block(
                            id: blockId, collectionId: docId, type: .code, title: "아카이브 생성",
                            content: "let a = 1", language: "swift", url: nil, siteName: nil,
                            savedAt: nil, imageNames: [], credential: nil,
                            isCollapsed: false, sortOrder: 0, createdAt: now, updatedAt: now
                        )]
                    ),
                ]),
            ]),
        ]

        let migrated = DataStore.migrate(legacy)
        XCTAssertEqual(migrated.count, 1)
        XCTAssertEqual(migrated[0].id, wsId)
        let docs = migrated[0].projects
        XCTAssertEqual(docs.count, 1)
        XCTAssertEqual(docs[0].id, docId, "문서 id는 Collection id 승계 (최근사용·선택 호환)")
        XCTAssertEqual(docs[0].workspaceId, wsId)
        XCTAssertEqual(docs[0].name, "WKWebView")
        XCTAssertEqual(docs[0].colorHex, "#FF5C00", "묶음 색 승계")
        XCTAssertEqual(docs[0].note, "메모")
        XCTAssertTrue(docs[0].isFavorite)
        XCTAssertTrue(docs[0].tags.contains("webkit"))
        XCTAssertTrue(docs[0].tags.contains("macOS 앱"), "旧 묶음명은 태그로 보존")
        XCTAssertEqual(docs[0].blocks.count, 1)
        XCTAssertEqual(docs[0].blocks[0].id, blockId)
        XCTAssertEqual(docs[0].blocks[0].projectId, docId)
        XCTAssertEqual(docs[0].blocks[0].language, "swift")
    }

    func testLegacyMigrationPreservesEmptyGroups() {
        let wsId = UUID()
        let groupId = UUID()
        let legacy = [
            LegacyV1Workspace(id: wsId, name: "업무", projects: [
                LegacyV1Project(id: groupId, workspaceId: wsId, name: "회의", colorHex: "#2D5BD7", collections: []),
            ]),
        ]
        let migrated = DataStore.migrate(legacy)
        XCTAssertEqual(migrated[0].projects.count, 1, "비어 있던 묶음은 빈 문서로 보존")
        XCTAssertEqual(migrated[0].projects[0].name, "회의")
        XCTAssertTrue(migrated[0].projects[0].blocks.isEmpty)
    }

    // MARK: - Persistable 스냅샷 (내부 노출)

    /// 저장 스냅샷은 DataStore.persistableSnapshot(from:) 로 직접 확인한다.
    @MainActor
    func testSnapshotStructurePreserved() {
        let store = TestHelpers.makeStore()
        let snapshot = DataStore.persistableSnapshot(from: store.workspaces)
        XCTAssertEqual(snapshot.count, store.workspaces.count)
        XCTAssertEqual(snapshot.map(\.name), store.workspaces.map(\.name))
    }
}
