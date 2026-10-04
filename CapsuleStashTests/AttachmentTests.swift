import XCTest
@testable import CapsuleStash

/// 아카이브·첨부·드롭 검증.
final class AttachmentTests: XCTestCase {
    // MARK: - 웹 아카이브 실파일 (T-09, 임시 폴더 격리)

    func testWebArchiveStoreRoundTrip() throws {
        let dir = try TestHelpers.makeTempDir()
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
        let dir = try TestHelpers.makeTempDir()
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

    // MARK: - 첨부 정리·리사이즈 (T-12, 임시 폴더 격리)


    func testImportDownscalesLargeImages() throws {
        let dir = try TestHelpers.makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let big = try TestHelpers.makeTestPNG(width: 4000, height: 3000)
        defer { try? FileManager.default.removeItem(at: big) }
        let stored = AttachmentStore.importFiles(from: [big], kind: AttachmentStore.imagesKind, baseDirectory: dir)
        XCTAssertEqual(stored.count, 1)
        let url = dir.appendingPathComponent(AttachmentStore.imagesKind, isDirectory: true)
            .appendingPathComponent(stored[0])
        let size = TestHelpers.imageSize(at: url)
        XCTAssertEqual(max(size?.0 ?? 0, size?.1 ?? 0), Int(AttachmentStore.maxImageDimension), "긴 변은 제한까지만")
    }

    func testImportKeepsSmallImagesIntact() throws {
        let dir = try TestHelpers.makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let small = try TestHelpers.makeTestPNG(width: 800, height: 600)
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
    func testImportFileDropsCreatesBlocks() throws {
        KeychainStore.inMemory = [:]
        defer { KeychainStore.inMemory = nil }
        let dir = try TestHelpers.makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let (store, project) = try TestHelpers.makeStoreWithProject(dir: dir)

        let png = try TestHelpers.makeTestPNG(width: 100, height: 100)
        defer { try? FileManager.default.removeItem(at: png) }
        let txt = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).txt")
        try "hello".write(to: txt, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: txt) }

        let created = store.importFileDrops([png, txt, URL(string: "https://example.com/a")!], to: project.id)
        XCTAssertEqual(created, 3, "이미지+텍스트+웹링크 각 1블록")
        let types = store.selectedProject?.blocks.map(\.type) ?? []
        XCTAssertTrue(types.contains(.image))
        XCTAssertTrue(types.contains(.text), ".txt는 내용 블록으로 읽힌다")
        let web = store.selectedProject?.blocks.first(where: { $0.type == .webArchive })
        XCTAssertEqual(web?.siteName, "example.com")
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: dir.appendingPathComponent("images", isDirectory: true).path),
            "images 폴더에 보관")
    }

    @MainActor
    func testImportFileDropsIgnoresUnknownProject() throws {
        let dir = try TestHelpers.makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = DataStore(samples: false, loadSeeds: false, persist: false, attachmentBase: dir)
        XCTAssertEqual(store.importFileDrops([URL(fileURLWithPath: "/tmp/x.png")], to: UUID()), 0)
        XCTAssertFalse(store.importTextDrop("hi", to: UUID()))
    }

    @MainActor
    func testImportTextDrop() throws {
        let dir = try TestHelpers.makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let (store, project) = try TestHelpers.makeStoreWithProject(dir: dir)
        XCTAssertTrue(store.importTextDrop("첫 줄\n둘째 줄", to: project.id))
        let block = store.selectedProject?.blocks.first(where: { $0.type == .text })
        XCTAssertEqual(block?.title, "첫 줄")
        XCTAssertEqual(block?.content, "첫 줄\n둘째 줄")
        XCTAssertFalse(store.importTextDrop("   \n  ", to: project.id), "빈 텍스트 무시")
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
        let store = TestHelpers.makeStore()
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
        let store = TestHelpers.makeStore()
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
        let savedLang = UserDefaults.standard.string(forKey: "appLanguage")
        UserDefaults.standard.set("ko", forKey: "appLanguage")
        UserDefaults.standard.set(0.0, forKey: "clipboardClearDelay")
        XCTAssertEqual(ClipboardService.clearDelayDescription, "자동 삭제 안 함")
        UserDefaults.standard.removeObject(forKey: "clipboardClearDelay")
        if let savedLang { UserDefaults.standard.set(savedLang, forKey: "appLanguage") }
        else { UserDefaults.standard.removeObject(forKey: "appLanguage") }
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

}
