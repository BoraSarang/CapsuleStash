import XCTest
@testable import CapsuleStash

/// 성능 가드 회귀 테스트 (거대 문서 멈춤 방지).
/// 접힘 기본값·마이그레이션·검색 상한·버전 스냅샷 제외.
final class PerfTests: XCTestCase {
    @MainActor
    func testImportedBlocksStartCollapsed() throws {
        let dir = try TestHelpers.makeTempDir()
        let (store, project) = try TestHelpers.makeStoreWithProject(dir: dir)
        let md = dir.appendingPathComponent("big.md")
        try String(repeating: "# 제목\n본문\n", count: 500).write(to: md, atomically: true, encoding: .utf8)
        XCTAssertEqual(store.importFileDrops([md], to: project.id), 1)
        XCTAssertTrue(store.locate(project)!.project.blocks.allSatisfy(\.isCollapsed))
    }

    @MainActor
    func testFolderImportCollapsed() throws {
        let dir = try TestHelpers.makeTempDir()
        let root = dir.appendingPathComponent("R", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try "내용".write(to: root.appendingPathComponent("a.md"), atomically: true, encoding: .utf8)
        let store = DataStore(samples: false, loadSeeds: false, persist: false, attachmentBase: dir)
        let report = store.importFolder(root)
        XCTAssertEqual(report.blocks, 1)
        let blocks = store.workspaces.flatMap(\.projects).flatMap(\.blocks)
        XCTAssertTrue(blocks.allSatisfy(\.isCollapsed))
    }

    @MainActor
    func testCollapseHugeBlocksMigration() throws {
        let dir = try TestHelpers.makeTempDir()
        let (store, project) = try TestHelpers.makeStoreWithProject(dir: dir)
        store.insertBlock(Block(projectId: project.id, type: .text, title: "small", content: "짧음"))
        store.insertBlock(Block(projectId: project.id, type: .text, title: "huge",
                                content: String(repeating: "가", count: 9000)))
        store.collapseHugeBlocks(limit: 8000)
        let blocks = store.locate(project)!.project.blocks
        XCTAssertFalse(blocks.first(where: { $0.title == "small" })!.isCollapsed)
        XCTAssertTrue(blocks.first(where: { $0.title == "huge" })!.isCollapsed)
    }

    @MainActor
    func testSearchTextCap() {
        let beyond = String(repeating: "x", count: 40_000) + "needle"
        XCTAssertFalse(DataStore.matches("needle", [beyond]), "상한 밖은 못 찾음 (빠름 대신)")
        XCTAssertTrue(DataStore.matches("needle", ["needle" + String(repeating: "x", count: 40_000)]))
    }

    @MainActor
    func testVersionSkipsHugeContent() throws {
        let dir = try TestHelpers.makeTempDir()
        let (store, project) = try TestHelpers.makeStoreWithProject(dir: dir)
        var block = Block(projectId: project.id, type: .text, title: "t",
                          content: String(repeating: "y", count: 150_000))
        store.insertBlock(block)
        block.content = String(repeating: "z", count: 150_000)
        store.updateBlock(block)
        XCTAssertTrue(store.locate(project)!.project.blocks.first!.versions.isEmpty,
                      "거대 본문은 스냅샷 제외")
    }
}
