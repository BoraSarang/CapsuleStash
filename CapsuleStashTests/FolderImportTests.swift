import XCTest
@testable import CapsuleStash

/// 폴더 가져오기 검증 (구조 매핑·타입 판별·건너뜀).
/// 임시 트리 격리. attachmentBase=임시 폴더라 실 저장소 오염 없음.
final class FolderImportTests: XCTestCase {
    @MainActor
    private func makeTree() throws -> URL {
        let root = try TestHelpers.makeTempDir()
            .appendingPathComponent("가져오기", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let sub = root.appendingPathComponent("하위", isDirectory: true)
        try FileManager.default.createDirectory(at: sub, withIntermediateDirectories: true)
        try "# 문서\n본문".write(to: sub.appendingPathComponent("doc.md"),
                                 atomically: true, encoding: .utf8)
        try "메모".write(to: sub.appendingPathComponent("note.txt"),
                         atomically: true, encoding: .utf8)
        try Data([0x00, 0x01, 0x02]).write(to: sub.appendingPathComponent("data.zip"))
        try "루트".write(to: root.appendingPathComponent("root.md"),
                         atomically: true, encoding: .utf8)
        // 숨김·빈 폴더·큰 파일 (건너뜀 대상)
        try "숨김".write(to: sub.appendingPathComponent(".hidden.md"),
                         atomically: true, encoding: .utf8)
        try FileManager.default.createDirectory(at: root.appendingPathComponent("빈폴더", isDirectory: true),
                                                withIntermediateDirectories: true)
        try String(repeating: "x", count: 200).write(to: sub.appendingPathComponent("big.txt"),
                                                    atomically: true, encoding: .utf8)
        // 중첩: 최상위 그룹(하위)으로 묶임
        let deep = sub.appendingPathComponent("깊은", isDirectory: true)
        try FileManager.default.createDirectory(at: deep, withIntermediateDirectories: true)
        try "깊은내용".write(to: deep.appendingPathComponent("deep.md"),
                             atomically: true, encoding: .utf8)
        return root
    }

    @MainActor
    func testImportFolderStructure() throws {
        let dir = try TestHelpers.makeTempDir()
        let store = DataStore(samples: false, loadSeeds: false, persist: false, attachmentBase: dir)
        let report = store.importFolder(try makeTree(), maxFileBytes: 100)
        XCTAssertEqual(report.projects, 2, "하위 + 기타")
        XCTAssertEqual(report.blocks, 5, "doc·note·data·root·deep (숨김·빈폴더·big 제외)")
        XCTAssertEqual(report.skipped.count, 1, "big.txt만 (숨김·빈폴더는 후보 아님)")
        let ws = store.workspaces.first
        XCTAssertEqual(ws?.name, "가져오기")
        XCTAssertEqual(Set(ws?.projects.map(\.name) ?? []), ["하위", "기타"])
        let sub = ws?.projects.first(where: { $0.name == "하위" })
        let types = Dictionary(grouping: sub?.blocks ?? [], by: \.type)
        XCTAssertEqual(types[.markdown]?.count, 2, "doc.md + deep.md")
        XCTAssertEqual(types[.text]?.count, 1)
        XCTAssertEqual(types[.file]?.count, 1, "data.zip")
        let etc = ws?.projects.first(where: { $0.name == "기타" })
        XCTAssertEqual(etc?.blocks.first?.type, .markdown)
        XCTAssertEqual(etc?.blocks.first?.title, "root")
    }

    @MainActor
    func testScanFolder() throws {
        let scanned = DataStore.scanFolder(try makeTree(), maxFileBytes: 100)
        XCTAssertEqual(scanned.projects, 2)
        XCTAssertEqual(scanned.files, 5)
        XCTAssertEqual(DataStore.scanFolder(URL(fileURLWithPath: "/없음")).files, 0)
    }

    @MainActor
    func testImportFolderRejects() throws {
        let dir = try TestHelpers.makeTempDir()
        let store = DataStore(samples: false, loadSeeds: false, persist: false, attachmentBase: dir)
        let empty = store.importFolder(dir.appendingPathComponent("없음"))
        XCTAssertEqual(empty.blocks, 0)
        let file = dir.appendingPathComponent("f.txt")
        try "x".write(to: file, atomically: true, encoding: .utf8)
        XCTAssertEqual(store.importFolder(file).blocks, 0, "파일 경로는 거부")
    }

    @MainActor
    func testFileDropsSkipDirectories() throws {
        let dir = try TestHelpers.makeTempDir()
        let (store, project) = try TestHelpers.makeStoreWithProject(dir: dir)
        XCTAssertEqual(store.importFileDrops([dir], to: project.id), 0, "폴더는 파일 가져오기에서 제외")
        XCTAssertTrue(store.locate(project)?.project.blocks.isEmpty == true)
    }
}
