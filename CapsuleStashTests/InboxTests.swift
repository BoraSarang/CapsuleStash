import XCTest
@testable import CapsuleStash

/// T-48 수신함 검증 (페이로드 규격·Inbox 문서·파일 소비).
/// 실제 저장소를 건드리지 않게 수신함 폴더를 임시 폴더로 바꾼다.
final class InboxTests: XCTestCase {
    private var tempDir: URL?

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: tempDir!, withIntermediateDirectories: true)
        SharedContainer.inboxOverride = tempDir
    }

    override func tearDown() {
        SharedContainer.inboxOverride = nil
        if let dir = tempDir { try? FileManager.default.removeItem(at: dir) }
        super.tearDown()
    }

    // MARK: - 페이로드

    func testPayloadHasContent() {
        XCTAssertTrue(InboxPayload(text: "메모").hasContent)
        XCTAssertTrue(InboxPayload(text: "  ", url: "https://example.com").hasContent)
        XCTAssertFalse(InboxPayload(text: "   ", url: nil).hasContent)
        XCTAssertFalse(InboxPayload(text: "", url: "   ").hasContent)
    }

    func testPayloadWriteReadRoundTrip() throws {
        let url = try InboxPayload(text: "공유 메모", url: "https://example.com", source: "테스트").write()
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
        let read = try InboxPayload.read(from: url)
        XCTAssertEqual(read.text, "공유 메모")
        XCTAssertEqual(read.url, "https://example.com")
    }

    func testFilenameUnique() {
        XCTAssertNotEqual(InboxPayload.filename(), InboxPayload.filename(), "동시 저장 충돌 방지")
    }

    /// Raycast 확장이 쓰는 규격 그대로 읽히는지 (url 키 없음·source 다름).
    func testRaycastPayloadShape() throws {
        let raw = #"{"version":1,"text":"클립 메모","source":"Raycast"}"#
        let file = tempDir!.appendingPathComponent("inbox-raycast.json")
        try Data(raw.utf8).write(to: file)
        let payload = try InboxPayload.read(from: file)
        XCTAssertEqual(payload.text, "클립 메모")
        XCTAssertNil(payload.url)
        XCTAssertTrue(payload.hasContent)
    }

    // MARK: - Inbox 문서·소비

    @MainActor
    func testEnsureInboxProject() {
        let store = TestHelpers.makeStore()
        let inbox = store.ensureInboxProject()
        XCTAssertEqual(inbox.name, DataStore.inboxProjectName)
        // 두 번 불러도 같은 문서 (중복 생성 금지)
        XCTAssertEqual(store.ensureInboxProject().id, inbox.id)
    }

    @MainActor
    func testSaveInboxText() {
        let store = TestHelpers.makeStore()
        XCTAssertTrue(store.saveInboxText("장볼 목록\n- 우유"))
        XCTAssertFalse(store.saveInboxText("   "), "빈 내용은 무시")
        let inbox = store.ensureInboxProject()
        XCTAssertEqual(inbox.blocks.count, 1)
        XCTAssertEqual(inbox.blocks[0].type, .text)
    }

    @MainActor
    func testSaveInboxURLBecomesWebBlock() {
        let store = TestHelpers.makeStore()
        XCTAssertTrue(store.saveInboxText("나중에 읽기", url: "https://example.com/article"))
        let block = store.ensureInboxProject().blocks.first
        XCTAssertEqual(block?.type, .webArchive)
        XCTAssertEqual(block?.url, "https://example.com/article")
        XCTAssertEqual(block?.content, "나중에 읽기")
    }

    @MainActor
    func testConsumeInboxFiles() throws {
        let store = TestHelpers.makeStore()
        try InboxPayload(text: "첫 메모", source: "테스트").write()
        try InboxPayload(text: "", url: "https://example.com", source: "테스트").write()
        // 깨진 파일 1개 — 건너뛰고 지운다
        try Data("깨짐".utf8).write(to: tempDir!.appendingPathComponent("inbox-broken.json"))
        let created = store.consumeInboxFiles()
        XCTAssertEqual(created, 2)
        XCTAssertEqual(store.ensureInboxProject().blocks.count, 2)
        let remaining = try FileManager.default.contentsOfDirectory(at: tempDir!, includingPropertiesForKeys: nil)
        XCTAssertTrue(remaining.isEmpty, "처리한 파일은 지운다 (깨진 것도)")
        XCTAssertEqual(store.consumeInboxFiles(), 0, "두 번째 소비는 0건")
    }
}
