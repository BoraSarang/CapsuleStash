import AppKit
import SwiftUI
import XCTest
@testable import CapsuleStash

/// T-02/T-06 데이터 모델 · 검색 · 비밀값 격리 검증.
/// budgets.json test_budget: unit ≤60s
final class CapsuleStashTests: XCTestCase {

    // MARK: - 모델

    func testWorkspaceProjectHierarchy() {
        let seed = DataStore.seed()
        XCTAssertEqual(seed.count, 3, "개발/개인/업무 3개 Workspace")

        let dev = seed.first { $0.name == "개발" }
        XCTAssertNotNil(dev)
        XCTAssertEqual(dev?.projects.count, 4, "개발 아래 문서 4개")

        // 모든 Project.workspaceId 가 실제 Workspace 를 가리켜야 한다
        for ws in seed {
            for project in ws.projects {
                XCTAssertEqual(project.workspaceId, ws.id, "Project 의 workspaceId 불일치: \(project.name)")
                for block in project.blocks {
                    XCTAssertEqual(block.projectId, project.id, "Block 의 projectId 불일치: \(block.title)")
                }
            }
        }
    }

    func testSeedMatchesMockupStructure() {
        let seed = DataStore.seed()
        let webDoc = seed
            .flatMap(\.projects)
            .first { $0.name.contains("WKWebView") }
        XCTAssertNotNil(webDoc, "목업의 WKWebView 문서가 있어야 함")
        XCTAssertEqual(webDoc?.tags.filter { $0 == "webkit" || $0 == "archive" }, ["webkit", "archive"])
        XCTAssertEqual(webDoc?.sortedBlocks.count, 5, "목업 기준 블록 5개")
        XCTAssertEqual(webDoc?.sortedBlocks.map(\.type), [.text, .code, .webArchive, .image, .credential])
        XCTAssertEqual(webDoc?.sortedBlocks.map(\.sortOrder), [0, 1, 2, 3, 4])
        for block in webDoc?.sortedBlocks ?? [] {
            XCTAssertFalse(block.content.hasPrefix("\n"), "시드 본문 앞 빈 줄 금지: \(block.title)")
            XCTAssertFalse(block.content.hasSuffix("\n"), "시드 본문 뒤 빈 줄 금지: \(block.title)")
        }
    }

    func testSortedBlocksFollowSortOrder() {
        var project = Project(workspaceId: UUID(), name: "정렬")
        let id = project.id
        project.blocks = [
            Block(projectId: id, type: .text, title: "셋", content: "c", sortOrder: 2),
            Block(projectId: id, type: .text, title: "하나", content: "a", sortOrder: 0),
            Block(projectId: id, type: .text, title: "둘", content: "b", sortOrder: 1),
        ]
        XCTAssertEqual(project.sortedBlocks.map(\.title), ["하나", "둘", "셋"])
    }

    // MARK: - 블록 타입 표시

    func testBlockTypeLabels() {
        XCTAssertEqual(BlockType.text.label, "TEXT")
        XCTAssertEqual(BlockType.code.label, "CODE")
        XCTAssertEqual(BlockType.webArchive.label, "WEB · ARCHIVE")
        XCTAssertEqual(BlockType.credential.label, "CREDENTIAL")
        XCTAssertTrue(BlockType.code.isCode)
        XCTAssertTrue(BlockType.shell.isCode)
        XCTAssertFalse(BlockType.text.isCode)
    }

    func testCodeBadgeIncludesLanguage() {
        let block = Block(projectId: UUID(), type: .code, title: "x", content: "let a = 1", language: "swift")
        XCTAssertEqual(block.badgeLabel, "CODE • SWIFT")
    }

    func testImageBadgeShowsCount() {
        let block = Block(projectId: UUID(), type: .image, title: "x", imageNames: ["a.png", "b.png"])
        XCTAssertEqual(block.badgeLabel, "IMAGE ×2")
    }

    // MARK: - [HARD] 비밀값 격리

    func testSearchIndexExcludesPassword() {
        let secret = "SUPER-SECRET-PASSWORD"
        let block = Block(
            projectId: UUID(),
            type: .credential,
            title: "GitHub",
            credential: Credential(homepage: "https://github.com", username: "example", password: secret)
        )
        XCTAssertFalse(
            block.searchIndexText.contains(secret),
            "검색 인덱스에 비밀값이 들어가면 [HARD] 위반"
        )
        XCTAssertTrue(block.searchIndexText.contains("example"), "아이디는 색인 대상")
        XCTAssertTrue(block.searchIndexText.contains("github.com"), "홈페이지는 색인 대상")
    }

    func testCopyPayloadExcludesPasswordByDefault() {
        let block = Block(
            projectId: UUID(),
            type: .credential,
            title: "GitHub",
            credential: Credential(homepage: "https://github.com", username: "example", password: "pw-1234")
        )
        let payload = block.copyPayload()
        XCTAssertFalse(payload.contains("pw-1234"), "[HARD] 기본 복사는 비밀값을 포함하면 안 됨")
        XCTAssertTrue(payload.contains("example"))
        XCTAssertTrue(payload.contains("https://github.com"))
    }

    func testCopyPayloadIncludesPasswordOnlyWhenUnlocked() {
        let block = Block(
            projectId: UUID(),
            type: .credential,
            title: "GitHub",
            credential: Credential(homepage: "https://github.com", username: "example", password: "pw-1234")
        )
        let payload = block.copyPayload(includeSecrets: true)
        XCTAssertTrue(payload.contains("pw-1234"))
        XCTAssertTrue(payload.contains("example"))
    }

    func testSecondSecretExcludedFromIndexAndDefaultCopy() {
        let block = Block(
            projectId: UUID(),
            type: .credential,
            title: "Naver API",
            credential: Credential(
                homepage: "https://developers.naver.com/main/",
                username: "토리",
                password: "CLIENT-ID-xxx",
                secondSecret: "CLIENT-SECRET-yyy"
            )
        )
        XCTAssertFalse(block.searchIndexText.contains("CLIENT-SECRET-yyy"), "[HARD] 두 번째 시크릿도 색인 금지")
        XCTAssertFalse(block.copyPayload().contains("CLIENT-SECRET-yyy"), "[HARD] 기본 복사에 두 번째 시크릿 금지")
        XCTAssertFalse(block.copyPayload().contains("CLIENT-ID-xxx"))
        let unlocked = block.copyPayload(includeSecrets: true)
        XCTAssertTrue(unlocked.contains("CLIENT-ID-xxx"), "해제 시 Secret 1 포함")
        XCTAssertTrue(unlocked.contains("CLIENT-SECRET-yyy"), "해제 시 Secret 2 포함")
    }

    func testLegacyCredentialDecodesWithoutSecondSecret() throws {
        let legacy = #"{"homepage":"https://x.test","username":"u","password":"p"}"#.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(Credential.self, from: legacy)
        XCTAssertEqual(decoded.secondSecret, "", "구버전 데이터는 빈 Secret 2로 호환")
    }

    func testMaskNeverLeaksShortSecrets() {
        XCTAssertEqual(DebugLogger.mask("abc"), "••••", "4자 이하는 전부 마스킹")
        XCTAssertFalse(DebugLogger.mask("sk-abc12345").contains("12345"), "중간 값이 남으면 안 됨")
        XCTAssertTrue(DebugLogger.mask("sk-abc12345").hasPrefix("sk"))
    }

    func testErrorMessageTableLoaded() {
        XCTAssertNil(ErrorMessages.shared.message(for: "E-MAC-NOT-EXIST-0000"))
        let message = ErrorMessages.shared.message(for: ErrorCode.storeSave)
        XCTAssertNotNil(message, "error_message_ko.json 이 로드돼야 함")
        XCTAssertFalse(message!.contains("E-MAC"), "메시지는 한국어 본문이어야 함")
    }

    // MARK: - 검색 쿼리 파싱

    func testSearchQueryPlainText() {
        let query = SearchQuery.parse("WKWebView 아카이브")
        XCTAssertTrue(query.types.isEmpty)
        XCTAssertNil(query.projectName)
        XCTAssertEqual(query.freeText, "wkwebview 아카이브", "자유 텍스트는 소문자 정규화")
        XCTAssertFalse(query.isEmpty)
    }

    func testSearchQueryTypeFilter() {
        let query = SearchQuery.parse("type:code docker")
        XCTAssertEqual(query.types, [.code])
        XCTAssertEqual(query.freeText, "docker")
    }

    func testSearchQueryProjectFilter() {
        let query = SearchQuery.parse("project:macOS type:shell swift")
        XCTAssertEqual(query.projectName, "macOS")
        XCTAssertEqual(query.types, [.shell])
        XCTAssertEqual(query.freeText, "swift")
    }

    func testSearchQueryUnknownTypeIsIgnored() {
        let query = SearchQuery.parse("type:unknown swift")
        XCTAssertTrue(query.types.isEmpty)
        XCTAssertEqual(query.freeText, "swift")
    }

    func testSearchQueryEmpty() {
        XCTAssertTrue(SearchQuery.parse("").isEmpty)
        XCTAssertTrue(SearchQuery.parse("   ").isEmpty)
    }

    // MARK: - 검색 결과 (DataStore)

    @MainActor
    private func makeStore() -> DataStore {
        DataStore(samples: false, loadSeeds: true, persist: false)
    }

    @MainActor
    func testSearchFindsCodeBlockByContent() {
        let store = makeStore()
        store.searchQuery = "docker compose"
        let hits = store.searchHits
        XCTAssertFalse(hits.isEmpty)
        XCTAssertTrue(hits.contains { $0.block?.title == "docker compose 실행" })
    }

    @MainActor
    func testSearchTypeFilterRestrictsResults() {
        let store = makeStore()
        store.searchQuery = "type:credential"
        let hits = store.searchHits
        XCTAssertFalse(hits.isEmpty)
        XCTAssertTrue(hits.allSatisfy { $0.block?.type == .credential })
        XCTAssertTrue(hits.allSatisfy { $0.kind == .credential })
    }

    @MainActor
    func testSearchNeverMatchesPassword() {
        let store = makeStore()
        store.searchQuery = "sample-only-not-a-real-secret"
        XCTAssertTrue(store.searchHits.isEmpty, "비밀값으로 검색되면 안 됨")
    }

    @MainActor
    func testSearchMatchesUsernameAndHomepage() {
        let store = makeStore()
        store.searchQuery = "github.com"
        XCTAssertFalse(store.searchHits.isEmpty, "홈페이지로 검색 가능해야 함")
    }

    @MainActor
    func testSearchProjectFilter() {
        let store = makeStore()
        store.searchQuery = "project:\"Docker 배포\""
        let hits = store.searchHits
        XCTAssertFalse(hits.isEmpty, "문서명으로 필터되어야 함")
        XCTAssertTrue(hits.allSatisfy { $0.project.name == "Docker 배포" })
    }

    func testSearchQuotedTokenizer() {
        let tokens = SearchQuery.tokenize("project:\"서버 관리\" type:shell docker")
        XCTAssertEqual(tokens, ["project:서버 관리", "type:shell", "docker"])
    }

    func testSearchProjectFilterWithoutQuotesKeepsRemainderAsText() {
        let query = SearchQuery.parse("project:서버 관리")
        XCTAssertEqual(query.projectName, "서버")
        XCTAssertEqual(query.freeText, "관리", "따옴표가 없으면 나머지는 자유 텍스트")
    }

    @MainActor
    func testEmptyQueryProducesNoHits() {
        let store = makeStore()
        store.searchQuery = ""
        XCTAssertTrue(store.searchHits.isEmpty)
    }

    @MainActor
    func testSearchHitPathsAreFullyQualified() {
        let store = makeStore()
        store.searchQuery = "swift"
        for hit in store.searchHits {
            XCTAssertTrue(hit.path.hasPrefix("개발 /"), "경로는 Workspace / Project 형식")
        }
    }

    // MARK: - 디자인 시스템 고정 (라이트 전용)

    func testPurposeHintExistsForAllTypes() {
        for type in BlockType.allCases {
            XCTAssertFalse(type.purposeHint.isEmpty, "\(type.rawValue)의 용도 설명이 있어야 함")
        }
        XCTAssertTrue(BlockType.webLink.purposeHint.contains("브라우저"))
        XCTAssertTrue(BlockType.webArchive.purposeHint.contains("T-09"))
    }

    func testWebHost() {
        let withURL = Block(projectId: UUID(), type: .webLink, title: "x", url: "https://docs.docker.com/reference")
        XCTAssertEqual(withURL.webHost, "docs.docker.com")
        let withoutURL = Block(projectId: UUID(), type: .webLink, title: "x")
        XCTAssertNil(withoutURL.webHost)
        let invalid = Block(projectId: UUID(), type: .webLink, title: "x", url: "not a url %%")
        XCTAssertNil(invalid.webHost)
    }

    // MARK: - 디자인 시스템 고정 (라이트 전용)

    func testThemeBadgeColorsMatchMockup() {
        XCTAssertEqual(Self.tokenHex(Theme.badgeColor(for: .text)), "#16150F")
        XCTAssertEqual(Self.tokenHex(Theme.badgeColor(for: .markdown)), "#16150F")
        XCTAssertEqual(Self.tokenHex(Theme.badgeColor(for: .code)), "#FF5C00")
        XCTAssertEqual(Self.tokenHex(Theme.badgeColor(for: .shell)), "#FF5C00")
        XCTAssertEqual(Self.tokenHex(Theme.badgeColor(for: .webLink)), "#2D5BD7")
        XCTAssertEqual(Self.tokenHex(Theme.badgeColor(for: .webArchive)), "#2D5BD7")
        XCTAssertEqual(Self.tokenHex(Theme.badgeColor(for: .image)), "#5F6F52")
        XCTAssertEqual(Self.tokenHex(Theme.badgeColor(for: .file)), "#5F6F52")
        XCTAssertEqual(Self.tokenHex(Theme.badgeColor(for: .credential)), "#7A2EE0")
    }

    func testThemeCoreTokensMatchMockup() {
        XCTAssertEqual(Self.tokenHex(Theme.ink), "#16150F")
        XCTAssertEqual(Self.tokenHex(Theme.sidebar), "#1B1A15")
        XCTAssertEqual(Self.tokenHex(Theme.paper), "#FAF7F0")
        XCTAssertEqual(Self.tokenHex(Theme.accent), "#FF5C00")
        XCTAssertEqual(Self.tokenHex(Theme.line), "#E8E0D1")
        XCTAssertEqual(Self.tokenHex(Theme.codeBackground), "#14130F")
    }

    /// SwiftUI Color → sRGB 16진수. 토큰 테이블이 바뀌면 테스트가 깨진다.
    private static func tokenHex(_ color: Color) -> String {
        let ns = NSColor(color).usingColorSpace(.sRGB) ?? .black
        return String(
            format: "#%02X%02X%02X",
            Int((ns.redComponent * 255).rounded()),
            Int((ns.greenComponent * 255).rounded()),
            Int((ns.blueComponent * 255).rounded())
        )
    }

    // MARK: - 태그 / 블록 편집

    @MainActor
    func testAddTagTrimsHashAndDedupes() {
        let store = makeStore()
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
        let store = makeStore()
        guard let project = store.selectedProject else { return XCTFail("Project 없음") }
        store.addTag("todelete", to: project)
        XCTAssertTrue(store.selectedProject?.tags.contains("todelete") == true)
        store.removeTag("todelete", from: project)
        XCTAssertFalse(store.selectedProject?.tags.contains("todelete") == true)
    }

    @MainActor
    func testUpdateBlockPersistsChanges() {
        let store = makeStore()
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
        let store = makeStore()
        guard let ws = store.workspaces.first else { return XCTFail("시드 Workspace 없음") }
        let project = store.createProject(title: "테스트", in: ws.id)
        XCTAssertNotNil(project)
        XCTAssertEqual(store.selectedProjectId, project?.id, "생성 직후 자동 선택")
    }

    @MainActor
    func testInsertBlockAppendsAtEnd() {
        let store = makeStore()
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
        let store = makeStore()
        guard let block = store.selectedProject?.sortedBlocks.first else { return XCTFail("블록 없음") }
        XCTAssertFalse(block.isCollapsed)
        store.toggleBlockCollapsed(block)
        let updated = store.selectedProject?.blocks.first { $0.id == block.id }
        XCTAssertEqual(updated?.isCollapsed, true)
    }

    @MainActor
    func testMoveBlockSwapsSortOrder() {
        let store = makeStore()
        guard let blocks = store.selectedProject?.sortedBlocks, blocks.count >= 2 else { return XCTFail("블록 부족") }
        let first = blocks[0]
        store.moveBlock(first, offset: 1)
        let order = store.selectedProject?.sortedBlocks.map(\.id) ?? []
        XCTAssertEqual(order.first, blocks[1].id, "아래로 이동했으므로 다음 블록이 첫 자리가 됨")
    }

    @MainActor
    func testDeleteBlock() {
        let store = makeStore()
        guard let block = store.selectedProject?.sortedBlocks.first else { return XCTFail("블록 없음") }
        let before = store.selectedProject?.blocks.count ?? 0
        store.deleteBlock(block)
        XCTAssertEqual(store.selectedProject?.blocks.count, before - 1)
    }

    @MainActor
    func testToggleFavorite() {
        let store = makeStore()
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
        let store = makeStore()
        guard let target = store.allProjects.last?.project,
              let located = store.locate(target) else { return XCTFail("대상 없음") }
        store.select(target)
        XCTAssertEqual(store.selectedProjectId, target.id)
        XCTAssertEqual(store.recents.first?.id, target.id, "최근 사용 맨 앞")
        XCTAssertTrue(store.expandedWorkspaces.contains(located.workspace.id))
    }

    @MainActor
    func testRecentsDeduplicate() {
        let store = makeStore()
        guard let target = store.allProjects.first?.project else { return XCTFail("대상 없음") }
        store.select(target)
        store.select(target)
        XCTAssertEqual(store.recents.filter { $0.id == target.id }.count, 1)
    }

    @MainActor
    func testDeleteProjectClearsSelection() {
        let store = makeStore()
        guard let project = store.selectedProject else { return XCTFail("Project 없음") }
        store.deleteProject(project)
        XCTAssertNotEqual(store.selectedProjectId, project.id)
        XCTAssertTrue(store.recents.allSatisfy { $0.id != project.id })
    }

    @MainActor
    func testStatsCountsMatchTree() {
        let store = makeStore()
        let stats = Dictionary(uniqueKeysWithValues: store.stats.map { ($0.0, $0.1) })
        XCTAssertEqual(stats["Workspace"], "\(store.workspaces.count)")
        XCTAssertEqual(stats["Project"], "\(store.allProjects.count)")
        let blocks = store.allProjects.reduce(0) { $0 + $1.project.blocks.count }
        XCTAssertEqual(stats["Block"], "\(blocks)")
    }

    @MainActor
    func testPersistableSnapshotStripsCredentials() {
        let store = makeStore()
        let snapshot = DataStore.persistableSnapshot(from: store.workspaces)
        let credentialBlocks = snapshot.flatMap(\.projects).flatMap(\.blocks).filter { $0.type == .credential }
        XCTAssertFalse(credentialBlocks.isEmpty, "시드에 credential 블록이 있는지 확인")
        for block in credentialBlocks {
            XCTAssertEqual(block.credential?.password, "", "[HARD] 저장 스냅샷에 시크릿이 있으면 안 됨")
            XCTAssertEqual(block.credential?.secondSecret, "", "[HARD] 저장 스냅샷에 두 번째 시크릿이 있으면 안 됨")
            XCTAssertNotNil(block.credential, "홈페이지·아이디(비밀값 아님)는 보관되어야 함")
        }
    }

    // MARK: - Keychain (T-10, 메모리 격리)

    func testKeychainRoundTrip() throws {
        KeychainStore.inMemory = [:]
        defer { KeychainStore.inMemory = nil }
        let id = UUID()
        try KeychainStore.save(blockId: id, secrets: .init(password: "pw-1", secondSecret: "secret-2"))
        let loaded = KeychainStore.load(blockId: id)
        XCTAssertEqual(loaded?.password, "pw-1")
        XCTAssertEqual(loaded?.secondSecret, "secret-2")
        XCTAssertEqual(KeychainStore.count(), 1)
        KeychainStore.delete(blockId: id)
        XCTAssertNil(KeychainStore.load(blockId: id))
        XCTAssertEqual(KeychainStore.count(), 0)
    }

    func testKeychainSyncClearsEmptySecrets() throws {
        KeychainStore.inMemory = [:]
        defer { KeychainStore.inMemory = nil }
        let filled = UUID()
        let emptied = UUID()
        try KeychainStore.save(blockId: emptied, secrets: .init(password: "old", secondSecret: ""))
        KeychainStore.sync([
            (filled, .init(password: "pw", secondSecret: "")),
            (emptied, .init(password: "", secondSecret: "")),
        ])
        XCTAssertNotNil(KeychainStore.load(blockId: filled))
        XCTAssertNil(KeychainStore.load(blockId: emptied), "빈 시크릿은 낡은 항목을 지워야 함")
    }

    @MainActor
    func testRestoreSecretsFromKeychain() throws {
        KeychainStore.inMemory = [:]
        defer { KeychainStore.inMemory = nil }
        let store = makeStore()
        guard let block = store.allProjects.flatMap(\.project.blocks).first(where: { $0.type == .credential }) else {
            return XCTFail("시드에 credential 블록 필요")
        }
        // 디스크에서 읽은 것처럼 시크릿을 비운 뒤 복원한다
        try KeychainStore.save(blockId: block.id, secrets: .init(password: "restored-1", secondSecret: "restored-2"))
        var blanked = block
        blanked.credential?.password = ""
        blanked.credential?.secondSecret = ""
        store.updateBlock(blanked)
        store.restoreSecretsFromKeychain()
        let restored = store.allProjects.flatMap(\.project.blocks).first(where: { $0.id == block.id })
        XCTAssertEqual(restored?.credential?.password, "restored-1")
        XCTAssertEqual(restored?.credential?.secondSecret, "restored-2")
    }

    @MainActor
    func testDeleteBlockClearsKeychain() throws {
        KeychainStore.inMemory = [:]
        defer { KeychainStore.inMemory = nil }
        let store = makeStore()
        guard let block = store.allProjects.flatMap(\.project.blocks).first(where: { $0.type == .credential }) else {
            return XCTFail("시드에 credential 블록 필요")
        }
        try KeychainStore.save(blockId: block.id, secrets: .init(password: "pw", secondSecret: ""))
        store.deleteBlock(block)
        XCTAssertNil(KeychainStore.load(blockId: block.id), "삭제된 블록의 시크릿은 Keychain에서도 지워야 함")
    }

    // MARK: - SwiftData 백엔드 (T-11, 임시 폴더 격리)

    private func makeTempDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    @MainActor
    func testSwiftDataRoundTrip() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let snapshot = DataStore.persistableSnapshot(from: DataStore.seed())
        try SwiftDataBackend.save(snapshot, directory: dir)
        let loaded = SwiftDataBackend.loadOrMigrate(directory: dir)
        XCTAssertNotNil(loaded)
        XCTAssertEqual(loaded?.count, snapshot.count, "Workspace 수 보존")
        XCTAssertEqual(
            loaded?.flatMap(\.projects).count,
            snapshot.flatMap(\.projects).count,
            "Project 수 보존"
        )
        let origBlocks = snapshot.flatMap(\.projects).flatMap(\.blocks)
        let backBlocks = loaded?.flatMap(\.projects).flatMap(\.blocks) ?? []
        XCTAssertEqual(backBlocks.map(\.id), origBlocks.map(\.id), "블록 ID 승계 (Keychain 연결 [HARD])")
        XCTAssertEqual(backBlocks.map(\.title), origBlocks.map(\.title), "순서 보존")
        for block in backBlocks where block.type == .credential {
            XCTAssertEqual(block.credential?.password, "", "[HARD] DB에 시크릿 금지")
            XCTAssertEqual(block.credential?.secondSecret, "", "[HARD] DB에 두 번째 시크릿 금지")
            XCTAssertNotNil(block.credential, "홈페이지·아이디는 보관")
        }
    }

    @MainActor
    func testSwiftDataMigrationPreservesIDs() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let projectId = UUID()
        let wsId = UUID()
        var project = Project(id: projectId, workspaceId: wsId, name: "AI API",
                              colorHex: "#7A2EE0", tags: ["key"])
        project.blocks = [Block(projectId: projectId, type: .credential, title: "Naver API",
                                credential: Credential(homepage: "https://developers.naver.com/main/",
                                                       username: "토리", password: "ID-xxx",
                                                       secondSecret: "SECRET-yyy"))]
        let fixtureBlockId = project.blocks.first!.id
        let fixture = [Workspace(id: wsId, name: "내 계정", projects: [project])]
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(fixture)
        try data.write(to: dir.appendingPathComponent("library.json"), options: .atomic)

        let migrated = SwiftDataBackend.loadOrMigrate(directory: dir)
        XCTAssertEqual(migrated?.count, 1)
        XCTAssertEqual(migrated?.first?.name, "내 계정", "Workspace 순서·이름 보존")
        let back = migrated?.first?.projects.first?.blocks.first
        XCTAssertEqual(back?.id, fixtureBlockId, "블록 ID 승계 (Keychain 연결 [HARD])")
        XCTAssertNotNil(back?.credential)
        XCTAssertEqual(back?.credential?.homepage, "https://developers.naver.com/main/")
        XCTAssertEqual(back?.credential?.username, "토리")
        XCTAssertEqual(back?.credential?.password, "", "마이그레이션 시 시크릿은 DB에 안 남김")
        // 같은 디렉터리 재로드 → DB 우선 (JSON 재읽기 아님)
        let reloaded = SwiftDataBackend.loadOrMigrate(directory: dir)
        XCTAssertEqual(reloaded?.first?.projects.first?.blocks.first?.credential?.username, "토리")
    }

    @MainActor
    func testSwiftDataEmptyWhenNothingStored() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        XCTAssertNil(SwiftDataBackend.loadOrMigrate(directory: dir), "DB·JSON 둘 다 없으면 nil (시드 경로)")
    }

    @MainActor
    func testVaultToggle() {
        let store = makeStore()
        XCTAssertFalse(store.isVaultUnlocked)
        store.unlockVault()
        XCTAssertTrue(store.isVaultUnlocked)
        store.lockVault()
        XCTAssertFalse(store.isVaultUnlocked)
    }

    // MARK: - 첨부 (이미지/파일)

    @MainActor
    func testSidebarVisibilityToggle() {
        let appState = AppState()
        let initial = appState.isSidebarVisible
        appState.isSidebarVisible.toggle()
        XCTAssertNotEqual(appState.isSidebarVisible, initial)
        XCTAssertEqual(
            UserDefaults.standard.object(forKey: "sidebarVisible") as? Bool,
            appState.isSidebarVisible,
            "사이드바 상태는 재기동 후에도 유지되어야 함"
        )
        appState.isSidebarVisible = initial // 복원
    }

    @MainActor
    func testSidebarWidthClamped() {
        // 실제 UserDefaults를 오염시키지 않게 저장·복원 (안 하면 테스트 돌릴 때마다 사이드바가 300으로 돌아감)
        let savedWidth = UserDefaults.standard.object(forKey: "sidebarWidth")
        defer {
            if let savedWidth {
                UserDefaults.standard.set(savedWidth, forKey: "sidebarWidth")
            } else {
                UserDefaults.standard.removeObject(forKey: "sidebarWidth")
            }
        }
        let appState = AppState()
        appState.setSidebarWidth(999)
        XCTAssertEqual(appState.sidebarWidth, AppState.sidebarMaxWidth)
        appState.setSidebarWidth(0)
        XCTAssertEqual(appState.sidebarWidth, AppState.sidebarMinWidth)
        appState.setSidebarWidth(300)
        XCTAssertEqual(appState.sidebarWidth, 300)
    }

    @MainActor
    func testMoveProjectAcrossWorkspaces() {
        let store = makeStore()
        guard store.workspaces.count >= 2,
              let moving = store.workspaces[0].projects.first else {
            XCTFail("시드에 Workspace 2개·Project 1개 이상 필요")
            return
        }
        let target = store.workspaces[1]
        let blockCount = moving.blocks.count
        XCTAssertTrue(store.moveProject(moving.id, to: target.id))
        XCTAssertFalse(store.workspaces[0].projects.contains(where: { $0.id == moving.id }))
        let relocated = store.workspaces[1].projects.first(where: { $0.id == moving.id })
        XCTAssertNotNil(relocated)
        XCTAssertEqual(relocated?.workspaceId, target.id)
        XCTAssertEqual(relocated?.blocks.count, blockCount, "블록은 함께 이동")
    }

    @MainActor
    func testMoveProjectSameWorkspaceIsNoOp() {
        let store = makeStore()
        guard let ws = store.workspaces.first,
              let project = ws.projects.first else {
            XCTFail("시드에 Workspace·Project 필요")
            return
        }
        XCTAssertFalse(store.moveProject(project.id, to: ws.id))
        XCTAssertEqual(store.workspaces.first?.projects.count, ws.projects.count)
        XCTAssertFalse(store.moveProject(UUID(), to: ws.id), "없는 Project는 이동 불가")
    }
    func testImportFilesCopiesIntoDirectory() throws {
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmp) }

        let src = tmp.appendingPathComponent("shot.png")
        try Data([0x89, 0x50, 0x4E, 0x47]).write(to: src)

        let store = tmp.appendingPathComponent("store")
        let names = AttachmentStore.importFiles(from: [src], kind: "images", baseDirectory: store)
        XCTAssertEqual(names.count, 1)
        XCTAssertTrue(names[0].hasSuffix(".png"))
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: store.appendingPathComponent("images/\(names[0])").path),
            "보관 폴더에 실파일이 있어야 함"
        )
    }

    func testFileURLRejectsPathTraversal() {
        XCTAssertNil(AttachmentStore.fileURL(kind: "images", name: "../evil.png"))
        XCTAssertNil(AttachmentStore.fileURL(kind: "images", name: "a/b.png"))
        XCTAssertNil(AttachmentStore.fileURL(kind: "images", name: ""))
        XCTAssertNotNil(AttachmentStore.fileURL(kind: "images", name: "shot-ab12cd34.png"))
    }

    func testIsImageFile() {
        XCTAssertTrue(AttachmentStore.isImageFile(URL(fileURLWithPath: "/tmp/a.png")))
        XCTAssertTrue(AttachmentStore.isImageFile(URL(fileURLWithPath: "/tmp/a.JPG")))
        XCTAssertFalse(AttachmentStore.isImageFile(URL(fileURLWithPath: "/tmp/a.pdf")))
        XCTAssertFalse(AttachmentStore.isImageFile(URL(fileURLWithPath: "/tmp/a")))
    }

    func testBlockCreationRequest() {
        let id = UUID()
        let req = BlockCreationRequest(projectId: id, type: .code)
        XCTAssertEqual(req.projectId, id)
        XCTAssertEqual(req.type, .code)
    }

    func testClipboardClearDelayDisabled() {
        UserDefaults.standard.set(0.0, forKey: "clipboardClearDelay")
        XCTAssertEqual(ClipboardService.clearDelayDescription, "자동 삭제 안 함")
        UserDefaults.standard.removeObject(forKey: "clipboardClearDelay")
    }

    func testClipboardClearDelayDefault() {
        UserDefaults.standard.removeObject(forKey: "clipboardClearDelay")
        XCTAssertEqual(ClipboardService.secretClearDelay, 30, accuracy: 0.001)
        XCTAssertTrue(ClipboardService.clearDelayDescription.contains("30"))
    }

    func testPersistenceUsesTestDirectoryWhenEnvSet() {
        setenv("CAPSULESTASH_TEST_DIR", "/tmp/CapsuleStashTests-selfcheck", 1)
        XCTAssertTrue(
            PersistenceStore.directoryURL.path.contains("CapsuleStashTests-selfcheck"),
            "테스트 격리: 환경변수가 지정되면 실제 저장소를 쓰면 안 됨"
        )
        XCTAssertFalse(
            PersistenceStore.directoryURL.path.contains("Application Support"),
            "실제 Application Support 경로가 섞이면 안 됨"
        )
        unsetenv("CAPSULESTASH_TEST_DIR")
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
        let store = makeStore()
        let snapshot = DataStore.persistableSnapshot(from: store.workspaces)
        XCTAssertEqual(snapshot.count, store.workspaces.count)
        XCTAssertEqual(snapshot.map(\.name), store.workspaces.map(\.name))
    }
}