import Foundation

/// 시드 데이터 (목업 mockup-v0.1.html 대응, 2단).
enum SeedData {
    nonisolated static func workspaces() -> [Workspace] {
        // MARK: 개발
        let dev = Workspace(name: "개발")
        var webDoc = Project(workspaceId: dev.id, name: "WKWebView로 웹 페이지 저장하기",
                             colorHex: "#FF5C00",
                             note: "WebArchive + PDF + 본문 텍스트 조합으로 저장",
                             tags: ["webkit", "archive"])
        webDoc.blocks = blocks(projectId: webDoc.id)

        var paletteDoc = Project(workspaceId: dev.id, name: "메뉴바 앱 구조",
                                 colorHex: "#2D5BD7", tags: ["swiftui"])
        paletteDoc.blocks = [Block(projectId: paletteDoc.id, type: .markdown, title: "메뉴바 상주 구조", content: """
            1. `MenuBarExtra` 로 메뉴바 아이템 등록
            2. `Window` 씬으로 메인 창 분리
            3. `Carbon.RegisterEventHotKey` 로 글로벌 단축키 수신
            4. 팔레트는 메인 창 위 오버레이로 표시
            """.trimmingCharacters(in: .newlines))]

        var shortcutDoc = Project(workspaceId: dev.id, name: "글로벌 단축키",
                                  colorHex: "#5F6F52", tags: ["input"])
        shortcutDoc.blocks = [Block(projectId: shortcutDoc.id, type: .code, title: "핫키 등록", content: """
            var hotKeyID = EventHotKeyID(signature: Self.signature, id: 1)
            RegisterEventHotKey(kVK_Space,
                               UInt32(cmdKey | shiftKey),
                               hotKeyID,
                               GetApplicationEventTarget(),
                               0,
                               &ref)
            """.trimmingCharacters(in: .newlines), language: "swift")]

        var dockerDoc = Project(workspaceId: dev.id, name: "Docker 배포",
                                colorHex: "#5F6F52", tags: ["infra"])
        dockerDoc.blocks = [
            Block(projectId: dockerDoc.id, type: .shell, title: "docker compose 실행", content: """
                docker compose up -d
                docker compose logs -f --tail=200
                """.trimmingCharacters(in: .newlines), language: "bash"),
            Block(projectId: dockerDoc.id, type: .webArchive, title: "Docker 공식 문서",
                  content: "Compose 파일 레퍼런스",
                  url: "https://docs.docker.com/reference/compose-file/", siteName: "docs.docker.com"),
        ]

        // MARK: 개인
        let personal = Workspace(name: "개인")
        let travelDoc = Project(workspaceId: personal.id, name: "여행", colorHex: "#C99A2E")
        var accountsDoc = Project(workspaceId: personal.id, name: "계정",
                                  colorHex: "#7A2EE0", tags: ["account"])
        accountsDoc.blocks = [Block(
            projectId: accountsDoc.id,
            type: .credential,
            title: "GitHub",
            credential: Credential(homepage: "https://github.com", username: "example", password: "sample-only-not-a-real-secret")
        )]

        // MARK: 업무
        let work = Workspace(name: "업무")
        let meetingDoc = Project(workspaceId: work.id, name: "회의", colorHex: "#2D5BD7")

        return [
            Workspace(id: dev.id, name: dev.name, projects: [webDoc, paletteDoc, shortcutDoc, dockerDoc]),
            Workspace(id: personal.id, name: personal.name, projects: [travelDoc, accountsDoc]),
            Workspace(id: work.id, name: work.name, projects: [meetingDoc]),
        ]
    }

    nonisolated private static func blocks(projectId: UUID) -> [Block] {
        [
            Block(projectId: projectId, type: .text, title: "설명", content: """
            WKWebView의 현재 페이지를 WebArchive + PDF + 본문 텍스트로 함께 저장하면 오프라인 열람과 검색이 모두 안정적이다. 기본값은 URL + 본문 + PDF 조합.
            """.trimmingCharacters(in: .newlines), sortOrder: 0),
            Block(projectId: projectId, type: .code, title: "아카이브 생성", content: """
            webView.createWebArchiveData { result in
              switch result {
              case .success(let data):
                try? data.write(to: archiveURL)
              case .failure(let error):
                logger.error("\\(error)")
              }
            }
            """.trimmingCharacters(in: .newlines), language: "swift", sortOrder: 1),
            Block(projectId: projectId, type: .webArchive, title: "참고 문서", content: "Working with web content offline in SwiftUI apps",
                  url: "https://artemnovichkov.com/blog/swiftui-offline",
                  siteName: "artemnovichkov.com", savedAt: Date().addingTimeInterval(-4 * 86400), sortOrder: 2),
            Block(projectId: projectId, type: .image, title: "메뉴바 구조 스케치",
                  imageNames: ["menubar-sketch-01.png", "palette-flow-02.png"], sortOrder: 3),
            Block(projectId: projectId, type: .credential, title: "GitHub — 개인 계정",
                  credential: Credential(homepage: "https://github.com", username: "example", password: "sample-only-not-a-real-secret"),
                  sortOrder: 4),
        ]
    }
}
