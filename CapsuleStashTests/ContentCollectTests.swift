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

    // MARK: - 내용물 md 드롭 (파일 URL 없이 UTI만 오는 경우)

    func testIsMarkdownDropTypeIdentifiers() {
        XCTAssertTrue(DataStore.isMarkdownDropTypeIdentifiers(["net.daringfireball.markdown"]),
                      "Finder 실측 UTI")
        XCTAssertTrue(DataStore.isMarkdownDropTypeIdentifiers(["public.file-url", "net.daringfireball.markdown"]))
        XCTAssertFalse(DataStore.isMarkdownDropTypeIdentifiers(["public.plain-text"]))
        XCTAssertFalse(DataStore.isMarkdownDropTypeIdentifiers(["public.png"]))
        XCTAssertFalse(DataStore.isMarkdownDropTypeIdentifiers([]))
        XCTAssertFalse(DataStore.isMarkdownDropTypeIdentifiers(["not-a-type"]))
    }

    @MainActor
    func testMarkdownContentDropBecomesMarkdownBlock() throws {
        let dir = try TestHelpers.makeTempDir()
        let (store, project) = try TestHelpers.makeStoreWithProject(dir: dir)
        XCTAssertTrue(store.importMarkdownDrop("# 제목\n본문", to: project.id))
        let block = store.locate(project)?.project.blocks.first
        XCTAssertEqual(block?.type, .markdown)
        XCTAssertEqual(block?.title, "# 제목")
        XCTAssertFalse(store.importMarkdownDrop("   ", to: project.id), "빈 내용은 무시")
    }

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

    // MARK: - 끼워넣기 (`![[제목]]`)

    func testEmbedParsesOwnLineOnly() {
        let segs = MarkdownSegment.parse("앞줄\n![[이미지]]\n뒷줄")
        XCTAssertEqual(segs.count, 3)
        guard case .embed(let title) = segs[1] else { return XCTFail("embed 아님: \(segs)") }
        XCTAssertEqual(title, "이미지")
        // 문장 중간은 리터럴
        let inline = MarkdownSegment.parse("그림 ![[이미지]] 참고")
        XCTAssertFalse(inline.contains { if case .embed = $0 { return true }; return false })
        // 빈 제목·닫힘 없음은 리터럴
        XCTAssertFalse(MarkdownSegment.parse("![[]]").contains { if case .embed = $0 { return true }; return false })
        XCTAssertFalse(MarkdownSegment.parse("![[열림").contains { if case .embed = $0 { return true }; return false })
        // 앞뒤 공백 허용
        guard case .embed(let trimmed) = MarkdownSegment.parse("  ![[ 띄움 ]]  ")[0] else {
            return XCTFail("공백 허용 안 됨")
        }
        XCTAssertEqual(trimmed, "띄움")
    }

    func testResolveEmbed() {
        let pid = UUID()
        let blocks = [
            Block(projectId: pid, type: .image, title: "도식", content: ""),
            Block(projectId: pid, type: .text, title: "도식", content: "둘째"),
            Block(projectId: pid, type: .text, title: "메모", content: "a"),
        ]
        // 첫 일치 (정렬 순서대로, 입력 순서 유지)
        XCTAssertEqual(DataStore.resolveEmbed(title: "도식", in: blocks)?.content, "")
        XCTAssertNil(DataStore.resolveEmbed(title: "없음", in: blocks))
        XCTAssertNil(DataStore.resolveEmbed(title: "  ", in: blocks))
        XCTAssertNil(DataStore.resolveEmbed(title: "도", in: blocks), "부분 일치는 안 함")
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
