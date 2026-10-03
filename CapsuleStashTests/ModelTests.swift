import XCTest
@testable import CapsuleStash

/// 모델·타입·비밀격리·제목·웹타입 검증.
final class ModelTests: XCTestCase {
    // MARK: - 모델

    func testWorkspaceProjectHierarchy() {
        let seed = SeedData.workspaces()
        XCTAssertEqual(seed.count, 3, "개발/개인/업무 3개 Workspace")

        let dev = seed.first { $0.name == "개발" }
        XCTAssertNotNil(dev)
        XCTAssertEqual(dev?.projects.count, 4, "개발 아래 문서 4개")

        // 모든 Project.workspaceId 가 실제 Workspace 를 가리켜야 한다
        for ws in seed {
            for project in ws.projects {
                XCTAssertEqual(project.workspaceId, ws.id, "Project 의 workspaceId 불일치: \(project.name)")
                for block in project.blocks {
                    XCTAssertEqual(block.projectId, project.id, "Block 의 projectId 불일치: \(block.title)")
                }
            }
        }
    }

    func testSeedMatchesMockupStructure() {
        let seed = SeedData.workspaces()
        let webDoc = seed
            .flatMap(\.projects)
            .first { $0.name.contains("WKWebView") }
        XCTAssertNotNil(webDoc, "목업의 WKWebView 문서가 있어야 함")
        XCTAssertEqual(webDoc?.tags.filter { $0 == "webkit" || $0 == "archive" }, ["webkit", "archive"])
        XCTAssertEqual(webDoc?.sortedBlocks.count, 5, "목업 기준 블록 5개")
        XCTAssertEqual(webDoc?.sortedBlocks.map(\.type), [.text, .code, .webArchive, .image, .credential])
        XCTAssertEqual(webDoc?.sortedBlocks.map(\.sortOrder), [0, 1, 2, 3, 4])
        for block in webDoc?.sortedBlocks ?? [] {
            XCTAssertFalse(block.content.hasPrefix("\n"), "시드 본문 앞 빈 줄 금지: \(block.title)")
            XCTAssertFalse(block.content.hasSuffix("\n"), "시드 본문 뒤 빈 줄 금지: \(block.title)")
        }
    }

    func testSortedBlocksFollowSortOrder() {
        var project = Project(workspaceId: UUID(), name: "정렬")
        let id = project.id
        project.blocks = [
            Block(projectId: id, type: .text, title: "셋", content: "c", sortOrder: 2),
            Block(projectId: id, type: .text, title: "하나", content: "a", sortOrder: 0),
            Block(projectId: id, type: .text, title: "둘", content: "b", sortOrder: 1),
        ]
        XCTAssertEqual(project.sortedBlocks.map(\.title), ["하나", "둘", "셋"])
    }

    // MARK: - 블록 타입 표시

    func testBlockTypeLabels() {
        XCTAssertEqual(BlockType.text.label, "TEXT")
        XCTAssertEqual(BlockType.code.label, "CODE")
        XCTAssertEqual(BlockType.webArchive.label, "WEB · ARCHIVE")
        XCTAssertEqual(BlockType.credential.label, "CREDENTIAL")
        XCTAssertTrue(BlockType.code.isCode)
        XCTAssertTrue(BlockType.shell.isCode)
        XCTAssertFalse(BlockType.text.isCode)
    }

    func testCodeBadgeIncludesLanguage() {
        let block = Block(projectId: UUID(), type: .code, title: "x", content: "let a = 1", language: "swift")
        XCTAssertEqual(block.badgeLabel, "CODE • SWIFT")
    }

    func testImageBadgeShowsCount() {
        let block = Block(projectId: UUID(), type: .image, title: "x", imageNames: ["a.png", "b.png"])
        XCTAssertEqual(block.badgeLabel, "IMAGE ×2")
    }

    // MARK: - [HARD] 비밀값 격리

    func testSearchIndexExcludesPassword() {
        let secret = "SUPER-SECRET-PASSWORD"
        let block = Block(
            projectId: UUID(),
            type: .credential,
            title: "GitHub",
            credential: Credential(homepage: "https://github.com", username: "example", password: secret)
        )
        XCTAssertFalse(
            block.searchIndexText.contains(secret),
            "검색 인덱스에 비밀값이 들어가면 [HARD] 위반"
        )
        XCTAssertTrue(block.searchIndexText.contains("example"), "아이디는 색인 대상")
        XCTAssertTrue(block.searchIndexText.contains("github.com"), "홈페이지는 색인 대상")
    }

    func testCopyPayloadExcludesPasswordByDefault() {
        let block = Block(
            projectId: UUID(),
            type: .credential,
            title: "GitHub",
            credential: Credential(homepage: "https://github.com", username: "example", password: "pw-1234")
        )
        let payload = block.copyPayload()
        XCTAssertFalse(payload.contains("pw-1234"), "[HARD] 기본 복사는 비밀값을 포함하면 안 됨")
        XCTAssertTrue(payload.contains("example"))
        XCTAssertTrue(payload.contains("https://github.com"))
    }

    func testCopyPayloadIncludesPasswordOnlyWhenUnlocked() {
        let block = Block(
            projectId: UUID(),
            type: .credential,
            title: "GitHub",
            credential: Credential(homepage: "https://github.com", username: "example", password: "pw-1234")
        )
        let payload = block.copyPayload(includeSecrets: true)
        XCTAssertTrue(payload.contains("pw-1234"))
        XCTAssertTrue(payload.contains("example"))
    }

    func testSecondSecretExcludedFromIndexAndDefaultCopy() {
        let block = Block(
            projectId: UUID(),
            type: .credential,
            title: "Naver API",
            credential: Credential(
                homepage: "https://developers.naver.com/main/",
                username: "토리",
                password: "CLIENT-ID-xxx",
                secondSecret: "CLIENT-SECRET-yyy"
            )
        )
        XCTAssertFalse(block.searchIndexText.contains("CLIENT-SECRET-yyy"), "[HARD] 두 번째 시크릿도 색인 금지")
        XCTAssertFalse(block.copyPayload().contains("CLIENT-SECRET-yyy"), "[HARD] 기본 복사에 두 번째 시크릿 금지")
        XCTAssertFalse(block.copyPayload().contains("CLIENT-ID-xxx"))
        let unlocked = block.copyPayload(includeSecrets: true)
        XCTAssertTrue(unlocked.contains("CLIENT-ID-xxx"), "해제 시 Secret 1 포함")
        XCTAssertTrue(unlocked.contains("CLIENT-SECRET-yyy"), "해제 시 Secret 2 포함")
    }

    func testLegacyCredentialDecodesWithoutSecondSecret() throws {
        let legacy = #"{"homepage":"https://x.test","username":"u","password":"p"}"#.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(Credential.self, from: legacy)
        XCTAssertEqual(decoded.secondSecret, "", "구버전 데이터는 빈 Secret 2로 호환")
    }

    func testMaskNeverLeaksShortSecrets() {
        XCTAssertEqual(DebugLogger.mask("abc"), "••••", "4자 이하는 전부 마스킹")
        XCTAssertFalse(DebugLogger.mask("sk-abc12345").contains("12345"), "중간 값이 남으면 안 됨")
        XCTAssertTrue(DebugLogger.mask("sk-abc12345").hasPrefix("sk"))
    }

    func testErrorMessageTableLoaded() {
        XCTAssertNil(ErrorMessages.shared.message(for: "E-MAC-NOT-EXIST-0000"))
        let message = ErrorMessages.shared.message(for: ErrorCode.storeSave)
        XCTAssertNotNil(message, "error_message_ko.json 이 로드돼야 함")
        XCTAssertFalse(message!.contains("E-MAC"), "메시지는 한국어 본문이어야 함")
    }

    // MARK: - 제목 자동완성 (T-30)

    func testSuggestedTitle() {
        var web = Block(projectId: UUID(), type: .webArchive, title: "",
                        url: "https://m.clien.net/service/board/cm_mac", siteName: "")
        XCTAssertEqual(web.suggestedTitle(), "m.clien.net")
        web.siteName = "클리앙"
        XCTAssertEqual(web.suggestedTitle(), "클리앙", "사이트명 우선")

        var md = Block(projectId: UUID(), type: .markdown, title: "",
                       content: "\n#  최종 제품 정의\n본문")
        XCTAssertEqual(md.suggestedTitle(), "최종 제품 정의", "마크다운 # 제거")

        let text = Block(projectId: UUID(), type: .text, title: "",
                         content: "  \n첫 줄입니다\n둘째 줄")
        XCTAssertEqual(text.suggestedTitle(), "첫 줄입니다", "빈 줄 건너뜀")

        let cred = Block(projectId: UUID(), type: .credential, title: "",
                         credential: Credential(homepage: "https://x.test", username: "토리"))
        XCTAssertEqual(cred.suggestedTitle(), "토리")

        let empty = Block(projectId: UUID(), type: .code, title: "", content: "   \n  ")
        XCTAssertEqual(empty.suggestedTitle(), "코드", "없으면 타입 표시명")
        let image = Block(projectId: UUID(), type: .image, title: "")
        XCTAssertEqual(image.suggestedTitle(), "이미지")
    }

    // MARK: - 웹 단일 타입 (T-28)

    func testWebPickableHidesLegacyLink() {
        XCTAssertFalse(BlockType.pickable.contains(.webLink))
        XCTAssertEqual(BlockType.pickable.count, BlockType.allCases.count - 1)
        XCTAssertTrue(BlockType.pickable.contains(.webArchive))
        XCTAssertEqual(SearchQuery.parse("type:weblink").types, [.webArchive], "구 필터 별칭")
    }

    @MainActor
    func testNormalizeWebBlocks() throws {
        let dir = try TestHelpers.makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let (store, project) = try TestHelpers.makeStoreWithProject(dir: dir)
        let legacy = Block(projectId: project.id, type: .webLink, title: "옛 링크",
                           url: "https://example.com/a")
        store.insertBlock(legacy)
        store.normalizeWebBlocks()
        let back = store.selectedProject?.blocks.first(where: { $0.id == legacy.id })
        XCTAssertEqual(back?.type, .webArchive)
        XCTAssertEqual(back?.url, "https://example.com/a", "필드 승계")
    }

}
