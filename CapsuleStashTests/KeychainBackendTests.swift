import XCTest
@testable import CapsuleStash

/// Keychain·SwiftData·Credential 단축키 검증.
final class KeychainBackendTests: XCTestCase {
    // MARK: - Keychain (T-10, 메모리 격리)

    func testKeychainRoundTrip() throws {
        KeychainStore.inMemory = [:]
        defer { KeychainStore.inMemory = nil }
        let id = UUID()
        try KeychainStore.save(blockId: id, secrets: .init(password: "pw-1", secondSecret: "secret-2"))
        let loaded = KeychainStore.load(blockId: id)
        XCTAssertEqual(loaded?.password, "pw-1")
        XCTAssertEqual(loaded?.secondSecret, "secret-2")
        XCTAssertEqual(KeychainStore.count(), 1)
        KeychainStore.delete(blockId: id)
        XCTAssertNil(KeychainStore.load(blockId: id))
        XCTAssertEqual(KeychainStore.count(), 0)
    }

    func testKeychainSyncClearsEmptySecrets() throws {
        KeychainStore.inMemory = [:]
        defer { KeychainStore.inMemory = nil }
        let filled = UUID()
        let emptied = UUID()
        try KeychainStore.save(blockId: emptied, secrets: .init(password: "old", secondSecret: ""))
        KeychainStore.sync([
            (filled, .init(password: "pw", secondSecret: "")),
            (emptied, .init(password: "", secondSecret: "")),
        ])
        XCTAssertNotNil(KeychainStore.load(blockId: filled))
        XCTAssertNil(KeychainStore.load(blockId: emptied), "빈 시크릿은 낡은 항목을 지워야 함")
    }

    @MainActor
    func testRestoreSecretsFromKeychain() throws {
        KeychainStore.inMemory = [:]
        defer { KeychainStore.inMemory = nil }
        let store = TestHelpers.makeStore()
        guard let block = store.allProjects.flatMap(\.project.blocks).first(where: { $0.type == .credential }) else {
            return XCTFail("시드에 credential 블록 필요")
        }
        // 디스크에서 읽은 것처럼 시크릿을 비운 뒤 복원한다
        try KeychainStore.save(blockId: block.id, secrets: .init(password: "restored-1", secondSecret: "restored-2"))
        var blanked = block
        blanked.credential?.password = ""
        blanked.credential?.secondSecret = ""
        store.updateBlock(blanked)
        store.restoreSecretsFromKeychain()
        let restored = store.allProjects.flatMap(\.project.blocks).first(where: { $0.id == block.id })
        XCTAssertEqual(restored?.credential?.password, "restored-1")
        XCTAssertEqual(restored?.credential?.secondSecret, "restored-2")
    }

    @MainActor
    func testDeleteBlockKeepsKeychainUntilForever() throws {
        KeychainStore.inMemory = [:]
        defer { KeychainStore.inMemory = nil }
        let store = TestHelpers.makeStore()
        guard let block = store.allProjects.flatMap(\.project.blocks).first(where: { $0.type == .credential }) else {
            return XCTFail("시드에 credential 블록 필요")
        }
        try KeychainStore.save(blockId: block.id, secrets: .init(password: "pw", secondSecret: ""))
        store.deleteBlock(block)
        XCTAssertNotNil(KeychainStore.load(blockId: block.id), "휴지통 보관 중에는 복원을 위해 유지")
        XCTAssertTrue(store.deleteForever(block.id))
        XCTAssertNil(KeychainStore.load(blockId: block.id), "완전 삭제 때 Keychain 정리")
    }

    // MARK: - SwiftData 백엔드 (T-11, 임시 폴더 격리)


    @MainActor
    func testSwiftDataRoundTrip() throws {
        let dir = try TestHelpers.makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let snapshot = DataStore.persistableSnapshot(from: SeedData.workspaces())
        try SwiftDataBackend.save(snapshot, directory: dir)
        let loaded = SwiftDataBackend.loadOrMigrate(directory: dir)
        XCTAssertNotNil(loaded)
        XCTAssertEqual(loaded?.count, snapshot.count, "Workspace 수 보존")
        XCTAssertEqual(
            loaded?.flatMap(\.projects).count,
            snapshot.flatMap(\.projects).count,
            "Project 수 보존"
        )
        let origBlocks = snapshot.flatMap(\.projects).flatMap(\.blocks)
        let backBlocks = loaded?.flatMap(\.projects).flatMap(\.blocks) ?? []
        XCTAssertEqual(backBlocks.map(\.id), origBlocks.map(\.id), "블록 ID 승계 (Keychain 연결 [HARD])")
        XCTAssertEqual(backBlocks.map(\.title), origBlocks.map(\.title), "순서 보존")
        for block in backBlocks where block.type == .credential {
            XCTAssertEqual(block.credential?.password, "", "[HARD] DB에 시크릿 금지")
            XCTAssertEqual(block.credential?.secondSecret, "", "[HARD] DB에 두 번째 시크릿 금지")
            XCTAssertNotNil(block.credential, "홈페이지·아이디는 보관")
        }
    }

    @MainActor
    func testSwiftDataMigrationPreservesIDs() throws {
        let dir = try TestHelpers.makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let projectId = UUID()
        let wsId = UUID()
        var project = Project(id: projectId, workspaceId: wsId, name: "AI API",
                              colorHex: "#7A2EE0", tags: ["key"])
        project.blocks = [Block(projectId: projectId, type: .credential, title: "Naver API",
                                credential: Credential(homepage: "https://developers.naver.com/main/",
                                                       username: "토리", password: "ID-xxx",
                                                       secondSecret: "SECRET-yyy"))]
        let fixtureBlockId = project.blocks.first!.id
        let fixture = [Workspace(id: wsId, name: "내 계정", projects: [project])]
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(fixture)
        try data.write(to: dir.appendingPathComponent("library.json"), options: .atomic)

        let migrated = SwiftDataBackend.loadOrMigrate(directory: dir)
        XCTAssertEqual(migrated?.count, 1)
        XCTAssertEqual(migrated?.first?.name, "내 계정", "Workspace 순서·이름 보존")
        let back = migrated?.first?.projects.first?.blocks.first
        XCTAssertEqual(back?.id, fixtureBlockId, "블록 ID 승계 (Keychain 연결 [HARD])")
        XCTAssertNotNil(back?.credential)
        XCTAssertEqual(back?.credential?.homepage, "https://developers.naver.com/main/")
        XCTAssertEqual(back?.credential?.username, "토리")
        XCTAssertEqual(back?.credential?.password, "", "마이그레이션 시 시크릿은 DB에 안 남김")
        // 같은 디렉터리 재로드 → DB 우선 (JSON 재읽기 아님)
        let reloaded = SwiftDataBackend.loadOrMigrate(directory: dir)
        XCTAssertEqual(reloaded?.first?.projects.first?.blocks.first?.credential?.username, "토리")
    }

    @MainActor
    func testSwiftDataEmptyWhenNothingStored() throws {
        let dir = try TestHelpers.makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        XCTAssertNil(SwiftDataBackend.loadOrMigrate(directory: dir), "DB·JSON 둘 다 없으면 nil (시드 경로)")
    }

    // MARK: - Credential 필드 단축키 (T-15)

    func testCredentialCopyText() {
        let cred = Block(projectId: UUID(), type: .credential, title: "Naver",
                         credential: Credential(homepage: "", username: "토리",
                                                password: "pw", secondSecret: "s2"))
        XCTAssertEqual(cred.credentialCopyText(secret: false, vaultUnlocked: false), "토리", "⌘1 아이디는 잠금과 무관")
        XCTAssertNil(cred.credentialCopyText(secret: true, vaultUnlocked: false), "[HARD] 잠금 시 시크릿 금지")
        XCTAssertEqual(cred.credentialCopyText(secret: true, vaultUnlocked: true), "pw", "⌘2 Secret 1은 해제 시만")

        let empty = Block(projectId: UUID(), type: .credential, title: "E",
                          credential: Credential())
        XCTAssertNil(empty.credentialCopyText(secret: false, vaultUnlocked: true), "빈 아이디는 nil")
        XCTAssertNil(empty.credentialCopyText(secret: true, vaultUnlocked: true), "빈 시크릿은 nil")

        let text = Block(projectId: UUID(), type: .text, title: "T", content: "hi")
        XCTAssertNil(text.credentialCopyText(secret: false, vaultUnlocked: true), "일반 블록은 nil")
        let noCred = Block(projectId: UUID(), type: .credential, title: "N")
        XCTAssertNil(noCred.credentialCopyText(secret: false, vaultUnlocked: true))
    }

}
