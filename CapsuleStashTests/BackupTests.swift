import XCTest
@testable import CapsuleStash

/// T-51 자동 백업 검증 (주기·파일명·7세대·왕복·토글).
/// 실설정 오염 금지: UserDefaults 키 저장·복원 + 임시 폴더 격리.
final class BackupTests: XCTestCase {
    private var savedLastBackup: Any?
    private var savedAutoBackup: Any?
    private var tempDir: URL?

    override func setUp() {
        super.setUp()
        savedLastBackup = UserDefaults.standard.object(forKey: BackupStore.lastBackupAtKey)
        savedAutoBackup = UserDefaults.standard.object(forKey: BackupStore.autoBackupEnabledKey)
        tempDir = try? FileManager.default.url(for: .itemReplacementDirectory,
                                               in: .userDomainMask, appropriateFor: nil, create: true)
        if tempDir == nil {
            tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            try? FileManager.default.createDirectory(at: tempDir!, withIntermediateDirectories: true)
        }
        BackupStore.baseDirectory = tempDir
    }

    override func tearDown() {
        BackupStore.baseDirectory = nil
        if let dir = tempDir { try? FileManager.default.removeItem(at: dir) }
        if let savedLastBackup {
            UserDefaults.standard.set(savedLastBackup, forKey: BackupStore.lastBackupAtKey)
        } else {
            UserDefaults.standard.removeObject(forKey: BackupStore.lastBackupAtKey)
        }
        if let savedAutoBackup {
            UserDefaults.standard.set(savedAutoBackup, forKey: BackupStore.autoBackupEnabledKey)
        } else {
            UserDefaults.standard.removeObject(forKey: BackupStore.autoBackupEnabledKey)
        }
        super.tearDown()
    }

    private func makeWorkspaces() -> [Workspace] {
        let projectId = UUID()
        let wsId = UUID()
        let block = Block(projectId: projectId, type: .credential, title: "API",
                          credential: Credential(homepage: "https://example.com", username: "u",
                                                 password: "s3cr3t", secondSecret: "s3cr3t-2"))
        let project = Project(id: projectId, workspaceId: wsId, name: "P", blocks: [block])
        return [Workspace(id: wsId, name: "W", projects: [project])]
    }

    // MARK: - 주기·파일명·가지치기 (순수 함수)

    func testShouldBackup() {
        let now = Date()
        XCTAssertTrue(BackupStore.shouldBackup(lastBackup: nil, now: now), "첫 실행은 백업")
        XCTAssertFalse(BackupStore.shouldBackup(lastBackup: now, now: now), "같은 날은 건너뜀")
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: now)!
        XCTAssertTrue(BackupStore.shouldBackup(lastBackup: yesterday, now: now), "다른 날은 백업")
    }

    func testFilenameSortsChronologically() {
        let early = BackupStore.filename(for: Date(timeIntervalSince1970: 1000))
        let late = BackupStore.filename(for: Date(timeIntervalSince1970: 2000))
        XCTAssertTrue(early.hasPrefix("backup-") && early.hasSuffix(".json"))
        XCTAssertLessThan(early, late, "파일명 정렬 = 시간 정렬")
    }

    func testPruneKeepsNewestSeven() {
        let files = (1...10).map { i -> URL in
            let day = String(format: "%02d", i)
            return URL(fileURLWithPath: "/tmp/backup-202610\(day)-000000.json")
        }
        let pruned = BackupStore.pruneCandidates(files: files)
        XCTAssertEqual(pruned.count, 3, "10개 중 3개 정리")
        XCTAssertTrue(pruned.allSatisfy { $0.lastPathComponent < "backup-20261008" }, "오래된 것부터")
        XCTAssertTrue(BackupStore.pruneCandidates(files: Array(files.prefix(7))).isEmpty, "7개면 정리 없음")
    }

    // MARK: - 기록·왕복·토글

    func testPerformBackupRoundTrip() throws {
        let url = try BackupStore.performBackup(workspaces: makeWorkspaces())
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
        let decoded = try LibraryTransfer.decodeJSON(Data(contentsOf: url))
        XCTAssertEqual(decoded[0].name, "W")
        XCTAssertEqual(decoded[0].projects[0].blocks[0].credential?.password, "", "백업에 시크릿 금지")
        XCTAssertNotNil(BackupStore.savedLastBackupAt(), "확인 시각 저장")
        XCTAssertEqual(BackupStore.listBackups().count, 1)
    }

    func testPerformBackupPrunesToSeven() throws {
        for day in 1...8 {
            let date = Calendar.current.date(from: DateComponents(year: 2026, month: 10, day: day))!
            try BackupStore.performBackup(workspaces: makeWorkspaces(), now: date)
        }
        XCTAssertEqual(BackupStore.listBackups().count, 7, "8번째에서 가장 오래된 1개 정리")
    }

    func testMaybeBackupRespectsToggle() throws {
        UserDefaults.standard.set(false, forKey: BackupStore.autoBackupEnabledKey)
        UserDefaults.standard.removeObject(forKey: BackupStore.lastBackupAtKey)
        BackupStore.maybeBackupIfDue(workspaces: makeWorkspaces())
        XCTAssertTrue(BackupStore.listBackups().isEmpty, "꺼져 있으면 기록 안 함")
        UserDefaults.standard.set(true, forKey: BackupStore.autoBackupEnabledKey)
        BackupStore.maybeBackupIfDue(workspaces: makeWorkspaces())
        XCTAssertEqual(BackupStore.listBackups().count, 1, "켜져 있으면 기록")
        let count = BackupStore.listBackups().count
        BackupStore.maybeBackupIfDue(workspaces: makeWorkspaces())
        XCTAssertEqual(BackupStore.listBackups().count, count, "같은 날 2회는 건너뜀")
    }
}
