import XCTest
@testable import CapsuleStash

/// 검색 쿼리·결과·팔레트 이동 검증.
final class SearchTests: XCTestCase {

    @MainActor
    func testSearchHelpersArePure() {
        XCTAssertTrue(DataStore.matches("vercel", ["Vercel API Key"]))
        XCTAssertFalse(DataStore.matches("vercel", ["GitHub"]))
        XCTAssertTrue(DataStore.matches("", ["아무거나"]))
        XCTAssertEqual(DataStore.kindRank(.project), 0)
        XCTAssertLessThan(DataStore.kindRank(.block), DataStore.kindRank(.credential))
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
        let store = TestHelpers.makeStore()
        store.searchQuery = "docker compose"
        let hits = store.searchHits
        XCTAssertFalse(hits.isEmpty)
        XCTAssertTrue(hits.contains { $0.block?.title == "docker compose 실행" })
    }

    @MainActor
    func testSearchTypeFilterRestrictsResults() {
        let store = TestHelpers.makeStore()
        store.searchQuery = "type:credential"
        let hits = store.searchHits
        XCTAssertFalse(hits.isEmpty)
        XCTAssertTrue(hits.allSatisfy { $0.block?.type == .credential })
        XCTAssertTrue(hits.allSatisfy { $0.kind == .credential })
    }

    @MainActor
    func testSearchNeverMatchesPassword() {
        let store = TestHelpers.makeStore()
        store.searchQuery = "sample-only-not-a-real-secret"
        XCTAssertTrue(store.searchHits.isEmpty, "비밀값으로 검색되면 안 됨")
    }

    @MainActor
    func testSearchMatchesUsernameAndHomepage() {
        let store = TestHelpers.makeStore()
        store.searchQuery = "github.com"
        XCTAssertFalse(store.searchHits.isEmpty, "홈페이지로 검색 가능해야 함")
    }

    @MainActor
    func testSearchProjectFilter() {
        let store = TestHelpers.makeStore()
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
        let store = TestHelpers.makeStore()
        store.searchQuery = "tag:swiftui"
        let hits = store.searchHits
        XCTAssertFalse(hits.isEmpty)
        XCTAssertTrue(hits.allSatisfy { $0.project.tags.contains("swiftui") })
    }

    @MainActor
    func testSearchFullWidthQueryFindsHalfWidth() {
        let store = TestHelpers.makeStore()
        store.searchQuery = "ＤＯＣＫＥＲ"
        XCTAssertFalse(store.searchHits.isEmpty, "전각 쿼리로 반각 내용이 검색돼야 함")
    }

    @MainActor
    func testEmptyQueryProducesNoHits() {
        let store = TestHelpers.makeStore()
        store.searchQuery = ""
        XCTAssertTrue(store.searchHits.isEmpty)
    }

    @MainActor
    func testSearchHitPathsAreFullyQualified() {
        let store = TestHelpers.makeStore()
        store.searchQuery = "swift"
        for hit in store.searchHits {
            XCTAssertTrue(hit.path.hasPrefix("개발 /"), "경로는 Workspace / Project 형식")
        }
    }

    // MARK: - 검색 이동 (T-43)

    @MainActor
    func testExpandBlockUnfoldsForPaletteJump() throws {
        let dir = try TestHelpers.makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let (store, project) = try TestHelpers.makeStoreWithProject(dir: dir)
        XCTAssertTrue(store.importTextDrop("점프 대상", to: project.id))
        guard var block = store.selectedProject?.blocks.first(where: { $0.type == .text }) else {
            return XCTFail("텍스트 블록 필요")
        }
        block.isCollapsed = true
        store.updateBlock(block)
        XCTAssertTrue(store.selectedProject?.blocks.first(where: { $0.id == block.id })?.isCollapsed == true)
        store.expandBlock(block.id)
        XCTAssertFalse(store.selectedProject?.blocks.first(where: { $0.id == block.id })?.isCollapsed ?? true,
                       "팔레트 이동 전 펼침")
        store.expandBlock(UUID()) // 없는 id는 무시 (크래시 없이)
    }

}
