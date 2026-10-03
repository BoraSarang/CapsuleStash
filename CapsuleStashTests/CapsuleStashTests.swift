import AppKit
import ImageIO
import SwiftUI
import UniformTypeIdentifiers
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

    // MARK: - 검색 확장 (T-16: 전각 정규화·tag 필터)

    func testSearchNormalizesFullWidth() {
        XCTAssertEqual("Ｄｏｃｋｅｒ　１２３".normalizedForSearch, "docker 123")
        XCTAssertEqual("Ｓｋ-ＡＢＣ".normalizedForSearch, "sk-abc")
        let query = SearchQuery.parse("ＤＯＣＫＥＲ")
        XCTAssertEqual(query.freeText, "docker")
    }

    func testSearchTagFilterParses() {
        let query = SearchQuery.parse("tag:swift docker")
        XCTAssertEqual(query.tags, ["swift"])
        XCTAssertEqual(query.freeText, "docker")
        let hashed = SearchQuery.parse("tag:#AI-Dev")
        XCTAssertEqual(hashed.tags, ["ai-dev"], "# 접두어 제거 + 소문자 정규화")
        let quoted = SearchQuery.parse("tag:\"서버 관리\"")
        XCTAssertEqual(quoted.tags, ["서버 관리"])
        XCTAssertTrue(SearchQuery.parse("tag:").isEmpty, "빈 tag는 무시")
    }

    @MainActor
    func testSearchTagFilterRestrictsResults() {
        let store = makeStore()
        store.searchQuery = "tag:swiftui"
        let hits = store.searchHits
        XCTAssertFalse(hits.isEmpty)
        XCTAssertTrue(hits.allSatisfy { $0.project.tags.contains("swiftui") })
    }

    @MainActor
    func testSearchFullWidthQueryFindsHalfWidth() {
        let store = makeStore()
        store.searchQuery = "ＤＯＣＫＥＲ"
        XCTAssertFalse(store.searchHits.isEmpty, "전각 쿼리로 반각 내용이 검색돼야 함")
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

    // MARK: - 디자인 시스템 (라이트·다크 적응형)

    func testPurposeHintExistsForAllTypes() {
        for type in BlockType.allCases {
            XCTAssertFalse(type.purposeHint.isEmpty, "\(type.rawValue)의 용도 설명이 있어야 함")
        }
        XCTAssertTrue(BlockType.webLink.purposeHint.contains("브라우저"))
        XCTAssertTrue(BlockType.webArchive.purposeHint.contains("오프라인"))
    }

    func testWebHost() {
        let withURL = Block(projectId: UUID(), type: .webLink, title: "x", url: "https://docs.docker.com/reference")
        XCTAssertEqual(withURL.webHost, "docs.docker.com")
        let withoutURL = Block(projectId: UUID(), type: .webLink, title: "x")
        XCTAssertNil(withoutURL.webHost)
        let invalid = Block(projectId: UUID(), type: .webLink, title: "x", url: "not a url %%")
        XCTAssertNil(invalid.webHost)
    }

    // MARK: - 디자인 시스템 (라이트·다크 적응형, T-18)

    func testThemeTokenTableIsComplete() {
        let names = ThemeToken.all.map(\.name)
        XCTAssertEqual(Set(names).count, names.count, "토큰 이름 중복 금지")
        for expected in ["ink", "sidebar", "sidebarElevated", "sidebarHover", "sidebarLine",
                         "sidebarText", "sidebarMuted", "paper", "titlebar", "card", "line",
                         "codeBackground", "codeForeground", "tagBackground", "muted",
                         "accent", "accentSoft", "sage", "gold",
                         "webBlue", "webBlueSoft", "tileTop", "tileBottom", "tileText"] {
            XCTAssertTrue(names.contains(expected), "\(expected) 토큰 누락")
        }
        for token in ThemeToken.all {
            XCTAssertLessThanOrEqual(token.light, 0xFFFFFF, "\(token.name) 라이트값 범위")
            XCTAssertLessThanOrEqual(token.dark, 0xFFFFFF, "\(token.name) 다크값 범위")
        }
    }

    func testThemeDarkValues() {
        func dark(_ name: String) -> String {
            let token = ThemeToken.all.first(where: { $0.name == name })!
            return String(format: "#%06X", token.dark)
        }
        XCTAssertEqual(dark("paper"), "#171613")
        XCTAssertEqual(dark("card"), "#22211C")
        XCTAssertEqual(dark("ink"), "#EDE8DB")
        XCTAssertEqual(dark("webBlue"), "#6B93F5")
        XCTAssertEqual(dark("accentSoft"), "#3A2415")
    }

    func testThemeDarkTokensResolve() {
        XCTAssertEqual(Self.tokenHex(Theme.paper, dark: true), "#171613", "다크 외관에서 페이퍼는 다크값")
        XCTAssertEqual(Self.tokenHex(Theme.card, dark: true), "#22211C")
        XCTAssertEqual(Self.tokenHex(Theme.ink, dark: true), "#EDE8DB")
        XCTAssertEqual(Self.tokenHex(Theme.badgeColor(for: .credential), dark: true), "#A67FF0")
        XCTAssertEqual(Self.tokenHex(Theme.badgeColor(for: .webLink), dark: true), "#6B93F5")
    }

    func testButtonPairsContrastInBothModes() {
        // primary = ink 채움 + paper 글자 — 양 모드에서 구분돼야 함 (하얀 뭉개짐 방지)
        for dark in [false, true] {
            XCTAssertNotEqual(Self.tokenHex(Theme.ink, dark: dark),
                              Self.tokenHex(Theme.paper, dark: dark),
                              "primary 버튼은 글자·채움이 구분돼야 함")
        }
    }

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

    /// SwiftUI Color → sRGB 16진수. 외관을 지정해 라이트·다크를 결정적으로 풀이한다.
    /// (테스트 Mac의 시스템 외관과 무관하게 항상 같은 결과.)
    /// 토큰 테이블이 바뀌면 테스트가 깨진다.
    private static func tokenHex(_ color: Color, dark: Bool = false) -> String {
        let appearance = NSAppearance(named: dark ? .darkAqua : .aqua)!
        var resolved: NSColor = .black
        appearance.performAsCurrentDrawingAppearance {
            resolved = NSColor(color).usingColorSpace(.sRGB) ?? .black
        }
        return String(
            format: "#%02X%02X%02X",
            Int((resolved.redComponent * 255).rounded()),
            Int((resolved.greenComponent * 255).rounded()),
            Int((resolved.blueComponent * 255).rounded())
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

    // MARK: - 웹 아카이브 실파일 (T-09, 임시 폴더 격리)

    func testWebArchiveStoreRoundTrip() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let data = "fake-webarchive".data(using: .utf8)!
        let name = WebArchiveStore.save(data, ext: "webarchive", baseDirectory: dir)
        XCTAssertNotNil(name)
        let url = WebArchiveStore.fileURL(kind: WebArchiveStore.archiveKind, name: name!, baseDirectory: dir)
        XCTAssertNotNil(url)
        XCTAssertEqual(try Data(contentsOf: url!), data)
        // 경로 탈출 방지
        XCTAssertNil(WebArchiveStore.fileURL(kind: WebArchiveStore.archiveKind, name: "../x", baseDirectory: dir))
        XCTAssertNil(WebArchiveStore.fileURL(kind: WebArchiveStore.archiveKind, name: "a/b", baseDirectory: dir))
    }

    @MainActor
    func testArchiveFileNamesSurviveRoundTrip() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        var project = Project(id: UUID(), workspaceId: UUID(), name: "웹")
        project.blocks = [Block(projectId: project.id, type: .webArchive, title: "문서",
                                url: "https://example.com",
                                archiveFile: "archive-abc.webarchive", pdfFile: "archive-abc.pdf")]
        let fixture = [Workspace(name: "W", projects: [project])]
        try SwiftDataBackend.save(fixture, directory: dir)
        let back = SwiftDataBackend.loadOrMigrate(directory: dir)?.first?.projects.first?.blocks.first
        XCTAssertEqual(back?.archiveFile, "archive-abc.webarchive")
        XCTAssertEqual(back?.pdfFile, "archive-abc.pdf")
        XCTAssertEqual(back?.url, "https://example.com")
    }

    func testWebArchiveErrorMessageLoaded() {
        XCTAssertEqual(ErrorMessages.shared.message(for: ErrorCode.webArchive), "웹 페이지를 오프라인으로 저장하지 못했습니다.")
    }

    // MARK: - Credential 필드 단축키 (T-15)

    func testCredentialCopyText() {
        let cred = Block(projectId: UUID(), type: .credential, title: "Naver",
                         credential: Credential(homepage: "", username: "토리",
                                                password: "pw", secondSecret: "s2"))
        XCTAssertEqual(cred.credentialCopyText(secret: false, vaultUnlocked: false), "토리", "⌘1 아이디는 잠금과 무관")
        XCTAssertNil(cred.credentialCopyText(secret: true, vaultUnlocked: false), "[HARD] 잠금 시 시크릿 금지")
        XCTAssertEqual(cred.credentialCopyText(secret: true, vaultUnlocked: true), "pw", "⌘2 Secret 1은 해제 시만")

        let empty = Block(projectId: UUID(), type: .credential, title: "E",
                          credential: Credential())
        XCTAssertNil(empty.credentialCopyText(secret: false, vaultUnlocked: true), "빈 아이디는 nil")
        XCTAssertNil(empty.credentialCopyText(secret: true, vaultUnlocked: true), "빈 시크릿은 nil")

        let text = Block(projectId: UUID(), type: .text, title: "T", content: "hi")
        XCTAssertNil(text.credentialCopyText(secret: false, vaultUnlocked: true), "일반 블록은 nil")
        let noCred = Block(projectId: UUID(), type: .credential, title: "N")
        XCTAssertNil(noCred.credentialCopyText(secret: false, vaultUnlocked: true))
    }

    // MARK: - 첨부 정리·리사이즈 (T-12, 임시 폴더 격리)

    private func makeTestPNG(width: Int, height: Int) throws -> URL {
        let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                                bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(CGColor(red: 0.2, green: 0.4, blue: 0.8, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let image = context.makeImage()!
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).png")
        let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(dest, image, nil)
        XCTAssertTrue(CGImageDestinationFinalize(dest))
        return url
    }

    private func imageSize(at url: URL) -> (Int, Int)? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return nil }
        return (image.width, image.height)
    }

    func testImportDownscalesLargeImages() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let big = try makeTestPNG(width: 4000, height: 3000)
        defer { try? FileManager.default.removeItem(at: big) }
        let stored = AttachmentStore.importFiles(from: [big], kind: AttachmentStore.imagesKind, baseDirectory: dir)
        XCTAssertEqual(stored.count, 1)
        let url = dir.appendingPathComponent(AttachmentStore.imagesKind, isDirectory: true)
            .appendingPathComponent(stored[0])
        let size = imageSize(at: url)
        XCTAssertEqual(max(size?.0 ?? 0, size?.1 ?? 0), Int(AttachmentStore.maxImageDimension), "긴 변은 제한까지만")
    }

    func testImportKeepsSmallImagesIntact() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let small = try makeTestPNG(width: 800, height: 600)
        defer { try? FileManager.default.removeItem(at: small) }
        let original = try Data(contentsOf: small)
        let stored = AttachmentStore.importFiles(from: [small], kind: AttachmentStore.imagesKind, baseDirectory: dir)
        XCTAssertEqual(stored.count, 1)
        let url = dir.appendingPathComponent(AttachmentStore.imagesKind, isDirectory: true)
            .appendingPathComponent(stored[0])
        XCTAssertEqual(try Data(contentsOf: url), original, "제한 이하는 바이트 그대로")
    }

    // MARK: - 외부 드롭 가져오기 (T-14, 임시 폴더 격리)
    @MainActor
    private func makeStoreWithProject(dir: URL) throws -> (DataStore, Project) {
        let store = DataStore(samples: false, loadSeeds: false, persist: false, attachmentBase: dir)
        store.createWorkspace(name: "W")
        guard let ws = store.workspaces.first,
              let project = store.createProject(title: "P", in: ws.id) else {
            throw XCTSkip("Workspace·Project 필요")
        }
        return (store, project)
    }

    @MainActor
    func testImportFileDropsCreatesBlocks() throws {
        KeychainStore.inMemory = [:]
        defer { KeychainStore.inMemory = nil }
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let (store, project) = try makeStoreWithProject(dir: dir)

        let png = try makeTestPNG(width: 100, height: 100)
        defer { try? FileManager.default.removeItem(at: png) }
        let txt = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).txt")
        try "hello".write(to: txt, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: txt) }

        let created = store.importFileDrops([png, txt, URL(string: "https://example.com/a")!], to: project.id)
        XCTAssertEqual(created, 3, "이미지+파일+웹링크 각 1블록")
        let types = store.selectedProject?.blocks.map(\.type) ?? []
        XCTAssertTrue(types.contains(.image))
        XCTAssertTrue(types.contains(.file))
        let web = store.selectedProject?.blocks.first(where: { $0.type == .webArchive })
        XCTAssertEqual(web?.siteName, "example.com")
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: dir.appendingPathComponent("images", isDirectory: true).path),
            "images 폴더에 보관")
    }

    @MainActor
    func testImportFileDropsIgnoresUnknownProject() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = DataStore(samples: false, loadSeeds: false, persist: false, attachmentBase: dir)
        XCTAssertEqual(store.importFileDrops([URL(fileURLWithPath: "/tmp/x.png")], to: UUID()), 0)
        XCTAssertFalse(store.importTextDrop("hi", to: UUID()))
    }

    @MainActor
    func testImportTextDrop() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let (store, project) = try makeStoreWithProject(dir: dir)
        XCTAssertTrue(store.importTextDrop("첫 줄\n둘째 줄", to: project.id))
        let block = store.selectedProject?.blocks.first(where: { $0.type == .text })
        XCTAssertEqual(block?.title, "첫 줄")
        XCTAssertEqual(block?.content, "첫 줄\n둘째 줄")
        XCTAssertFalse(store.importTextDrop("   \n  ", to: project.id), "빈 텍스트 무시")
    }

    // MARK: - 제목 자동완성 (T-30)

    func testSuggestedTitle() {
        var web = Block(projectId: UUID(), type: .webArchive, title: "",
                        url: "https://m.clien.net/service/board/cm_mac", siteName: "")
        XCTAssertEqual(web.suggestedTitle(), "m.clien.net")
        web.siteName = "클리앙"
        XCTAssertEqual(web.suggestedTitle(), "클리앙", "사이트명 우선")

        var md = Block(projectId: UUID(), type: .markdown, title: "",
                       content: "\n#  최종 제품 정의\n본문")
        XCTAssertEqual(md.suggestedTitle(), "최종 제품 정의", "마크다운 # 제거")

        let text = Block(projectId: UUID(), type: .text, title: "",
                         content: "  \n첫 줄입니다\n둘째 줄")
        XCTAssertEqual(text.suggestedTitle(), "첫 줄입니다", "빈 줄 건너뜀")

        let cred = Block(projectId: UUID(), type: .credential, title: "",
                         credential: Credential(homepage: "https://x.test", username: "토리"))
        XCTAssertEqual(cred.suggestedTitle(), "토리")

        let empty = Block(projectId: UUID(), type: .code, title: "", content: "   \n  ")
        XCTAssertEqual(empty.suggestedTitle(), "코드", "없으면 타입 표시명")
        let image = Block(projectId: UUID(), type: .image, title: "")
        XCTAssertEqual(image.suggestedTitle(), "이미지")
    }

    // MARK: - 마크다운 파서 (T-26)
    func testMarkdownParse() {
        let segments = MarkdownSegment.parse("# 제목\n## 부제\n### 소제\n본문\n> 인용\n- 하나\n- 둘\n```swift\nlet a = 1\n```\n")
        XCTAssertEqual(segments[0], .heading(level: 1, text: "제목"))
        XCTAssertEqual(segments[1], .heading(level: 2, text: "부제"))
        XCTAssertEqual(segments[2], .heading(level: 3, text: "소제"))
        XCTAssertEqual(segments[3], .paragraph(lines: ["본문"]))
        XCTAssertEqual(segments[4], .quote(lines: ["인용"]))
        XCTAssertEqual(segments[5], .bullet(items: ["하나", "둘"]))
        XCTAssertEqual(segments[6], .code(language: "swift", lines: ["let a = 1"]))
        // # 뒤 공백 없으면 제목 아님, 닫히지 않은 펜스는 코드로
        XCTAssertEqual(MarkdownSegment.parse("#태그"), [.paragraph(lines: ["#태그"])])
        XCTAssertEqual(MarkdownSegment.parse("```\nabc"), [.code(language: "", lines: ["abc"])])
        XCTAssertEqual(MarkdownSegment.parse(""), [])
    }

    func testMarkdownTableParse() {
        let text = "| 이름 | 값 |\n|---|---|\n| A | 1 |\n| B | 2 | extra |\n본문"
        let segments = MarkdownSegment.parse(text)
        XCTAssertEqual(segments[0], .table(header: ["이름", "값"],
                                           rows: [["A", "1"], ["B", "2", "extra"]]))
        XCTAssertEqual(segments[1], .paragraph(lines: ["본문"]))
        // 구분행 없으면 표 아님
        XCTAssertEqual(MarkdownSegment.parse("| a | b |"),
                       [.paragraph(lines: ["| a | b |"])])
    }

    // MARK: - 웹 단일 타입 (T-28)

    func testWebPickableHidesLegacyLink() {
        XCTAssertFalse(BlockType.pickable.contains(.webLink))
        XCTAssertEqual(BlockType.pickable.count, BlockType.allCases.count - 1)
        XCTAssertTrue(BlockType.pickable.contains(.webArchive))
        XCTAssertEqual(SearchQuery.parse("type:weblink").types, [.webArchive], "구 필터 별칭")
    }

    @MainActor
    func testNormalizeWebBlocks() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let (store, project) = try makeStoreWithProject(dir: dir)
        let legacy = Block(projectId: project.id, type: .webLink, title: "옛 링크",
                           url: "https://example.com/a")
        store.insertBlock(legacy)
        store.normalizeWebBlocks()
        let back = store.selectedProject?.blocks.first(where: { $0.id == legacy.id })
        XCTAssertEqual(back?.type, .webArchive)
        XCTAssertEqual(back?.url, "https://example.com/a", "필드 승계")
    }

    // MARK: - 모두 접기·순서 이동 (T-27)

    @MainActor
    func testSetAllBlocksCollapsed() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let (store, project) = try makeStoreWithProject(dir: dir)
        store.insertBlock(Block(projectId: project.id, type: .text, title: "A", content: "a"))
        store.insertBlock(Block(projectId: project.id, type: .text, title: "B", content: "b"))
        store.setAllBlocksCollapsed(true, in: project.id)
        XCTAssertTrue(store.selectedProject?.blocks.allSatisfy(\.isCollapsed) == true)
        store.setAllBlocksCollapsed(false, in: project.id)
        XCTAssertTrue(store.selectedProject?.blocks.allSatisfy { !$0.isCollapsed } == true)
    }

    @MainActor
    func testMoveBlockTo() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let (store, project) = try makeStoreWithProject(dir: dir)
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
        let store = makeStore()
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
        let dir = try makeTempDir()
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
        let store = makeStore()
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
        let store = makeStore()
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

    // MARK: - 표시 언어 (T-25 한·영)

    func testAppLanguageResolve() {
        XCTAssertEqual(AppLanguage.resolve(saved: nil, systemCode: "ko"), "ko", "기본은 시스템 언어")
        XCTAssertEqual(AppLanguage.resolve(saved: nil, systemCode: "en"), "en")
        XCTAssertEqual(AppLanguage.resolve(saved: nil, systemCode: "ja"), "en", "미지원 시스템 언어는 영어")
        XCTAssertEqual(AppLanguage.resolve(saved: nil, systemCode: nil), "en")
        XCTAssertEqual(AppLanguage.resolve(saved: "ko", systemCode: "en"), "ko", "명시 선택 우선")
        XCTAssertEqual(AppLanguage.resolve(saved: "en", systemCode: "ko"), "en")
        XCTAssertEqual(AppLanguage.resolve(saved: "system", systemCode: "ko"), "ko")
        XCTAssertEqual(AppLanguage.resolve(saved: "system", systemCode: "fr"), "en")
    }

    /// 카탈로그 키 정합성. `String(localized:locale:)` 의 locale은 서식용이라
    /// 테이블 선택 검증에는 못 쓴다 — 컴파일된 .strings를 직접 읽는다.
    private func stringsTable(_ locale: String) -> [String: String] {
        guard let url = Bundle.main.url(forResource: "Localizable", withExtension: "strings",
                                        subdirectory: "\(locale).lproj"),
              let dict = NSDictionary(contentsOf: url) as? [String: String] else { return [:] }
        return dict
    }

    func testCatalogStaticStrings() {
        let en = stringsTable("en")
        let ko = stringsTable("ko")
        XCTAssertGreaterThan(en.count, 200, "출하 테이블이 비면 안 됨")
        XCTAssertEqual(Set(en.keys), Set(ko.keys), "한·영 키 대칭 (한쪽만 있으면 반대 언어에서 떨어짐)")
        XCTAssertEqual(en["검색"], "Search")
        XCTAssertEqual(en["취소"], "Cancel")
        XCTAssertEqual(en["계정 정보"], "Account Info")
        XCTAssertEqual(en["언어"], "Language")
        XCTAssertEqual(en["검색: docker, github, swift…"], "Search: docker, github, swift…")
        XCTAssertEqual(en["⌘1 ID ⌘2 PW"], "⌘1 ID ⌘2 Secret")
        XCTAssertEqual(ko["검색"], "검색")
        XCTAssertEqual(ko["취소"], "취소")
    }

    func testCatalogFormatKeys() {
        let en = stringsTable("en")
        XCTAssertEqual(en["블록 %lld개"], "%lld blocks")
        XCTAssertEqual(en["코드 %lld개"], "%lld code blocks")
        XCTAssertEqual(en["이미지 %lld개"], "%lld images")
        XCTAssertEqual(en["수정 %@"], "Modified %@")
        XCTAssertEqual(en["저장 %@"], "Saved %@")
        XCTAssertEqual(en["포함된 블록 %lld개가 모두 사라집니다."], "All %lld blocks will be deleted.")
        XCTAssertEqual(en["포함된 Project %lld개가 모두 사라집니다."], "All %lld projects will be deleted.")
        XCTAssertEqual(en["'%@' 삭제"], "Delete '%@'")
        XCTAssertEqual(en["%@에 새 Project"], "New Project in %@")
        XCTAssertEqual(en["%@ 복사"], "Copy %@")
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