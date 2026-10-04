import XCTest
@testable import CapsuleStash

/// 드롭 내용 인식(md/txt→내용 블록) + 타입 필터 + 이어보기(합친 마크다운) 검증.
final class ContentCollectTests: XCTestCase {
    // MARK: - 판별·읽기 (순수 함수)

    func testTextBlockType() {
        XCTAssertEqual(DataStore.textBlockType(for: URL(fileURLWithPath: "/a/노트.md")), .markdown)
        XCTAssertEqual(DataStore.textBlockType(for: URL(fileURLWithPath: "/a/NOTE.MD")), .markdown)
        XCTAssertEqual(DataStore.textBlockType(for: URL(fileURLWithPath: "/a/메모.txt")), .text)
        XCTAssertNil(DataStore.textBlockType(for: URL(fileURLWithPath: "/a/자료.pdf")))
        XCTAssertNil(DataStore.textBlockType(for: URL(fileURLWithPath: "/a/사진.png")))
        XCTAssertNil(DataStore.textBlockType(for: URL(fileURLWithPath: "/a/داشت.zip")))
    }

    func testReadableText() throws {
        let dir = try TestHelpers.makeTempDir()
        let md = dir.appendingPathComponent("n.md")
        try "# 제목\n본문".write(to: md, atomically: true, encoding: .utf8)
        XCTAssertEqual(DataStore.readableText(from: md), "# 제목\n본문")
        // 없는 파일·디코딩 불가(이진)는 nil → 파일 블록 폴백
        XCTAssertNil(DataStore.readableText(from: dir.appendingPathComponent("없음.md")))
        let bin = dir.appendingPathComponent("b.md")
        try Data([0xFF, 0xFE, 0x00, 0x01]).write(to: bin)
        XCTAssertNil(DataStore.readableText(from: bin), "이진은 파일 블록으로")
    }

    func testReadableTextSizeCap() throws {
        let dir = try TestHelpers.makeTempDir()
        let big = dir.appendingPathComponent("big.txt")
        try String(repeating: "a", count: 100).write(to: big, atomically: true, encoding: .utf8)
        XCTAssertNotNil(DataStore.readableText(from: big, maxBytes: 200))
        XCTAssertNil(DataStore.readableText(from: big, maxBytes: 10), "초과분은 파일 블록으로")
    }

    // MARK: - 드롭 가져오기

    @MainActor
    func testMarkdownDropBecomesMarkdownBlock() throws {
        let dir = try TestHelpers.makeTempDir()
        let (store, project) = try TestHelpers.makeStoreWithProject(dir: dir)
        let md = dir.appendingPathComponent("회의.md")
        try "# 안건\n- 결정".write(to: md, atomically: true, encoding: .utf8)
        let created = store.importFileDrops([md], to: project.id)
        XCTAssertEqual(created, 1)
        let block = store.locate(project)?.project.blocks.first
        XCTAssertEqual(block?.type, .markdown)
        XCTAssertEqual(block?.title, "회의")
        XCTAssertEqual(block?.content, "# 안건\n- 결정")
    }

    @MainActor
    func testTxtDropBecomesTextBlock() throws {
        let dir = try TestHelpers.makeTempDir()
        let (store, project) = try TestHelpers.makeStoreWithProject(dir: dir)
        let txt = dir.appendingPathComponent("메모.txt")
        try "장보기\n- 우유".write(to: txt, atomically: true, encoding: .utf8)
        XCTAssertEqual(store.importFileDrops([txt], to: project.id), 1)
        let block = store.locate(project)?.project.blocks.first
        XCTAssertEqual(block?.type, .text)
        XCTAssertEqual(block?.title, "메모")
    }

    @MainActor
    func testUnreadableMdFallsBackToFile() throws {
        let dir = try TestHelpers.makeTempDir()
        let (store, project) = try TestHelpers.makeStoreWithProject(dir: dir)
        let bin = dir.appendingPathComponent("깨짐.md")
        try Data([0xFF, 0xFE, 0x00, 0x01]).write(to: bin)
        XCTAssertEqual(store.importFileDrops([bin], to: project.id), 1)
        XCTAssertEqual(store.locate(project)?.project.blocks.first?.type, .file)
    }

    // MARK: - 타입 필터 (순수 함수)

    @MainActor
    func testFilterBlocks() {
        let pid = UUID()
        let blocks = [
            Block(projectId: pid, type: .text, title: "t", content: "a"),
            Block(projectId: pid, type: .code, title: "c1", content: "b"),
            Block(projectId: pid, type: .code, title: "c2", content: "c"),
        ]
        XCTAssertEqual(DataStore.filterBlocks(blocks, by: nil).count, 3)
        let codes = DataStore.filterBlocks(blocks, by: .code)
        XCTAssertEqual(codes.count, 2)
        XCTAssertTrue(codes.allSatisfy { $0.type == .code })
        XCTAssertTrue(DataStore.filterBlocks(blocks, by: .image).isEmpty)
    }

    // MARK: - 이어보기 (합친 마크다운 재사용)

    @MainActor
    func testContinuousMarkdownCoversAllBlocks() {
        let store = TestHelpers.makeStore()
        guard let project = store.selectedProject else { return XCTFail("Project 없음") }
        let combined = LibraryTransfer.markdown(for: project)
        for block in project.blocks {
            XCTAssertTrue(combined.contains(block.title), "제목 누락: \(block.title)")
        }
    }
}
