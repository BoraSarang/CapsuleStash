import XCTest
@testable import CapsuleStash

/// T-55 스마트 그룹 + T-56 중첩 태그 검증.
/// UserDefaults 오염 금지: `smartGroups` 키 저장·복원.
final class SmartOrganizeTests: XCTestCase {
    private var savedGroups: Any?

    override func setUp() {
        super.setUp()
        savedGroups = UserDefaults.standard.object(forKey: "smartGroups")
    }

    override func tearDown() {
        if let savedGroups {
            UserDefaults.standard.set(savedGroups, forKey: "smartGroups")
        } else {
            UserDefaults.standard.removeObject(forKey: "smartGroups")
        }
        super.tearDown()
    }

    // MARK: - T-56 중첩 태그 접두 매칭 (순수 함수)

    func testTagMatchesPrefix() {
        XCTAssertTrue(DataStore.tagMatches(queryTag: "업무", tag: "업무"))
        XCTAssertTrue(DataStore.tagMatches(queryTag: "업무", tag: "업무/진행중"))
        XCTAssertTrue(DataStore.tagMatches(queryTag: "업무", tag: "업무/진행중/긴급"))
        XCTAssertFalse(DataStore.tagMatches(queryTag: "업무", tag: "업무용"))
        XCTAssertFalse(DataStore.tagMatches(queryTag: "업무", tag: "집안일"))
        XCTAssertFalse(DataStore.tagMatches(queryTag: "", tag: "업무"))
    }

    func testTagMatchesNormalized() {
        // 전각·대소문자 정규화는 양쪽에 적용
        XCTAssertTrue(DataStore.tagMatches(queryTag: "SWIFT", tag: "swift/ui"))
        XCTAssertTrue(DataStore.tagMatches(queryTag: "ｓｗｉｆｔ", tag: "swift"))
    }

    @MainActor
    func testNestedTagSearchFindsChildren() {
        let store = TestHelpers.makeStore()
        guard let project = store.selectedProject else { return XCTFail("Project 없음") }
        store.addTag("업무/진행중", to: project)
        store.searchQuery = "tag:업무"
        XCTAssertTrue(store.searchHits.contains { $0.project.id == project.id }, "부모 태그로 자식 문서를 찾아야 함")
        store.searchQuery = "tag:업무/진행중"
        XCTAssertTrue(store.searchHits.contains { $0.project.id == project.id }, "전체 경로도 그대로 동작")
        store.searchQuery = "tag:업무용"
        XCTAssertFalse(store.searchHits.contains { $0.project.id == project.id }, "부분 문자열은 매칭 금지")
    }

    @MainActor
    func testAddTagFoldsSlashes() {
        let store = TestHelpers.makeStore()
        guard let project = store.selectedProject else { return XCTFail("Project 없음") }
        store.addTag("  업무 / 진행중  ", to: project)
        XCTAssertTrue(store.selectedProject?.tags.contains("업무/진행중") == true)
        store.addTag("///", to: project)
        XCTAssertFalse(store.selectedProject?.tags.contains("") == true, "슬래시만으로는 태그 안 생김")
    }

    // MARK: - T-55 스마트 그룹

    @MainActor
    func testAddRenameDeleteSmartGroup() {
        let store = TestHelpers.makeStore()
        XCTAssertNil(store.addSmartGroup(name: "  ", query: "type:code"), "빈 이름 거부")
        XCTAssertNil(store.addSmartGroup(name: "코드", query: "   "), "빈 조건 거부")
        XCTAssertNil(store.addSmartGroup(name: "전부", query: "tag:"), "조건 없는 쿼리 거부")
        guard let group = store.addSmartGroup(name: "코드", query: "type:code") else {
            return XCTFail("그룹 생성 실패")
        }
        XCTAssertEqual(store.smartGroups.count, 1)
        // 같은 조건이면 이름만 바꾼다 (중복 그룹 금지)
        let renamed = store.addSmartGroup(name: "코드 조각", query: "type:code")
        XCTAssertEqual(renamed?.id, group.id)
        XCTAssertEqual(store.smartGroups.count, 1)
        store.renameSmartGroup(group.id, to: "  ")
        XCTAssertEqual(store.smartGroups.first?.name, "코드 조각", "빈 이름으로 변경 금지")
        store.renameSmartGroup(group.id, to: "스위프트")
        XCTAssertEqual(store.smartGroups.first?.name, "스위프트")
        store.deleteSmartGroup(group.id)
        XCTAssertTrue(store.smartGroups.isEmpty)
    }

    @MainActor
    func testSmartGroupHitsReuseSearch() {
        let store = TestHelpers.makeStore()
        guard let group = store.addSmartGroup(name: "코드", query: "type:code") else {
            return XCTFail("그룹 생성 실패")
        }
        store.searchQuery = "type:code"
        XCTAssertEqual(store.hitCount(for: group), store.searchHits.count, "같은 파이프라 수가 같아야 함")
        XCTAssertGreaterThan(store.hitCount(for: group), 0, "시드에 코드 블록이 있어야 함")
    }

    @MainActor
    func testSmartGroupsPersistAcrossInstances() {
        UserDefaults.standard.removeObject(forKey: "smartGroups")
        let first = DataStore(samples: false, loadSeeds: false, persist: true)
        XCTAssertNotNil(first.addSmartGroup(name: "코드", query: "type:code"))
        let second = DataStore(samples: false, loadSeeds: false, persist: false)
        XCTAssertEqual(second.smartGroups.count, 1, "재기동 후에도 조건이 살아야 함")
        XCTAssertEqual(second.smartGroups.first?.query, "type:code")
    }
}
