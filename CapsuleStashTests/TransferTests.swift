import XCTest
@testable import CapsuleStash

/// T-50 일괄 내보내기·가져오기 검증 (JSON 왕복·시크릿 제외·ID 재발급·Markdown).
final class TransferTests: XCTestCase {
    private func makeFixture() -> [Workspace] {
        let wsId = UUID()
        let projectId = UUID()
        let code = Block(projectId: projectId, type: .code, title: "스니펫",
                         content: "print(1)", language: "swift", sortOrder: 0)
        let cred = Block(projectId: projectId, type: .credential, title: "API",
                         content: "메모", credential: Credential(
                             homepage: "https://example.com", username: "user1",
                             password: "s3cr3t-pw", secondSecret: "s3cr3t-2"), sortOrder: 1)
        let image = Block(projectId: projectId, type: .image, title: "그림",
                          imageNames: ["a.png"], archiveFile: "a.webarchive",
                          pdfFile: "a.pdf", thumbnailFile: "t.jpg", sortOrder: 2)
        let project = Project(id: projectId, workspaceId: wsId, name: "P",
                              note: "노트", tags: ["swift"], blocks: [code, cred, image])
        return [Workspace(id: wsId, name: "W", projects: [project])]
    }

    // MARK: - JSON 왕복

    func testExportDecodeRoundTrip() throws {
        let fixture = makeFixture()
        let data = try LibraryTransfer.exportJSON(workspaces: fixture)
        let decoded = try LibraryTransfer.decodeJSON(data)
        XCTAssertEqual(decoded.count, 1)
        XCTAssertEqual(decoded[0].name, "W")
        XCTAssertEqual(decoded[0].projects.count, 1)
        XCTAssertEqual(decoded[0].projects[0].blocks.count, 3)
        XCTAssertEqual(decoded[0].projects[0].blocks[0].content, "print(1)")
        // 홈페이지·아이디는 살고 시크릿은 비어서 온다
        let cred = decoded[0].projects[0].blocks[1].credential
        XCTAssertEqual(cred?.homepage, "https://example.com")
        XCTAssertEqual(cred?.username, "user1")
        XCTAssertEqual(cred?.password, "")
        XCTAssertEqual(cred?.secondSecret, "")
    }

    func testExportDataContainsNoSecrets() throws {
        let data = try LibraryTransfer.exportJSON(workspaces: makeFixture())
        let raw = String(data: data, encoding: .utf8) ?? ""
        XCTAssertFalse(raw.contains("s3cr3t-pw"), "내보낸 JSON에 시크릿이 있으면 안 됨")
        XCTAssertFalse(raw.contains("s3cr3t-2"), "두 번째 시크릿도 마찬가지")
        XCTAssertTrue(raw.contains("user1"), "아이디는 보관 대상")
    }

    func testDecodeInvalidThrows() {
        XCTAssertThrowsError(try LibraryTransfer.decodeJSON(Data("깨진거".utf8))) { error in
            XCTAssertEqual(error as? LibraryTransfer.TransferError, .decodeFailed)
        }
    }

    func testDecodeUnsupportedVersionThrows() throws {
        struct OldEnvelope: Codable { let capsuleStashExport: Int; let exportedAt: Date; let workspaces: [Workspace] }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(OldEnvelope(capsuleStashExport: 999, exportedAt: Date(), workspaces: []))
        XCTAssertThrowsError(try LibraryTransfer.decodeJSON(data)) { error in
            XCTAssertEqual(error as? LibraryTransfer.TransferError, .unsupportedVersion)
        }
    }

    // MARK: - 가져오기 재매핑

    func testRemapForImport() {
        let fixture = makeFixture()
        let oldWsId = fixture[0].id
        let oldProjectId = fixture[0].projects[0].id
        let oldBlockIds = Set(fixture[0].projects[0].blocks.map(\.id))
        let mapped = LibraryTransfer.remapForImport(fixture)
        XCTAssertEqual(mapped.count, 1)
        let ws = mapped[0]
        XCTAssertNotEqual(ws.id, oldWsId, "Workspace ID 재발급")
        XCTAssertEqual(ws.name, "W", "이름은 유지")
        let project = ws.projects[0]
        XCTAssertNotEqual(project.id, oldProjectId, "Project ID 재발급")
        XCTAssertEqual(project.workspaceId, ws.id, "소속 연결")
        XCTAssertTrue(Set(project.blocks.map(\.id)).isDisjoint(with: oldBlockIds), "Block ID 전부 재발급")
        XCTAssertTrue(project.blocks.allSatisfy { $0.projectId == project.id }, "블록 소속 연결")
        // [HARD] 시크릿·바이너리 참조 정리
        for block in project.blocks {
            XCTAssertEqual(block.credential?.password ?? "", "")
            XCTAssertEqual(block.credential?.secondSecret ?? "", "")
            XCTAssertTrue(block.imageNames.isEmpty)
            XCTAssertNil(block.archiveFile)
            XCTAssertNil(block.pdfFile)
            XCTAssertNil(block.thumbnailFile)
        }
        XCTAssertEqual(project.blocks.first { $0.type == .credential }?.credential?.username, "user1")
    }

    @MainActor
    func testImportWorkspacesAppends() throws {
        let store = TestHelpers.makeStore()
        let before = store.workspaces.count
        let data = try LibraryTransfer.exportJSON(workspaces: makeFixture())
        let decoded = try LibraryTransfer.decodeJSON(data)
        let count = store.importWorkspaces(decoded)
        XCTAssertEqual(count, 1)
        XCTAssertEqual(store.workspaces.count, before + 1)
    }

    // MARK: - Markdown·파일명

    func testSafeFilename() {
        XCTAssertEqual(LibraryTransfer.safeFilename("일기/2024:1", ext: "md"), "일기_2024_1.md")
        XCTAssertEqual(LibraryTransfer.safeFilename("   ", ext: "json"), "untitled.json")
        XCTAssertEqual(LibraryTransfer.safeFilename("보고서", ext: "md"), "보고서.md")
    }

    func testMarkdownCodeFenceAndCredentialStrip() {
        let md = LibraryTransfer.markdown(for: makeFixture()[0].projects[0])
        XCTAssertTrue(md.contains("# P"), "Project 제목")
        XCTAssertTrue(md.contains("```swift"), "코드 펜스+언어")
        XCTAssertTrue(md.contains("print(1)"))
        XCTAssertTrue(md.contains("user1"), "아이디는 포함")
        XCTAssertFalse(md.contains("s3cr3t-pw"), "Markdown에도 시크릿 금지")
        XCTAssertFalse(md.contains("s3cr3t-2"))
    }
}
