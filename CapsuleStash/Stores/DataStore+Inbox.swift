import Foundation

/// T-48 수신함 (Inbox Project + 파일 소비).
/// Share 확장·URL scheme·App Intents가 `Inbox/`에 파일을 떨구면 본체가 Project로 편입한다.
extension DataStore {
    /// 수신함 문서명. URL·확장·검색에서 그대로 쓰므로 고정 (고유명사 취급, 번역 안 함).
    static let inboxProjectName = "Inbox"

    /// 첫 Workspace의 Inbox 문서를 돌려준다. 없으면 만든다.
    /// Workspace 자체가 없으면 Inbox Workspace까지 만든다 (확장에서 첫 저장 상황).
    @discardableResult
    func ensureInboxProject() -> Project {
        if workspaces.isEmpty {
            createWorkspace(name: "Inbox")
        }
        guard let ws = workspaces.first else { fatalError("Inbox Workspace 생성 실패") }
        if let inbox = ws.projects.first(where: { $0.name == Self.inboxProjectName }) {
            return inbox
        }
        guard let created = createProject(title: Self.inboxProjectName, in: ws.id) else {
            fatalError("Inbox Project 생성 실패")
        }
        return created
    }

    /// 텍스트 1건을 수신함에 바로 저장한다 (URL scheme·Intents용).
    /// - Returns: 저장됐으면 true (빈 내용은 false).
    @discardableResult
    func saveInboxText(_ text: String, url: String? = nil) -> Bool {
        let payload = InboxPayload(text: text, url: url)
        guard payload.hasContent else { return false }
        return insertInboxPayload(payload)
    }

    /// 수신함 파일을 읽어 블록으로 편입하고 파일을 지운다.
    /// - Returns: 편입한 블록 수.
    @discardableResult
    func consumeInboxFiles() -> Int {
        let files = (try? FileManager.default.contentsOfDirectory(
            at: SharedContainer.inboxURL, includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]))?.filter { $0.pathExtension == "json" } ?? []
        var created = 0
        for file in files {
            do {
                let payload = try InboxPayload.read(from: file)
                if insertInboxPayload(payload) { created += 1 }
            } catch {
                DebugLogger.error(code: ErrorCode.storeCorrupted, "수신함 파일 읽기 실패")
            }
            // 깨진 파일도 남기면 매번 에러라 지운다.
            try? FileManager.default.removeItem(at: file)
        }
        if created > 0 {
            DebugLogger.feature("수신함 편입: 블록 \(created)개")
        }
        return created
    }

    /// 페이로드 1건을 블록으로 만든다. URL만 있으면 웹 블록, 텍스트가 있으면 텍스트 블록.
    @discardableResult
    private func insertInboxPayload(_ payload: InboxPayload) -> Bool {
        let inbox = ensureInboxProject()
        let text = payload.text.trimmingCharacters(in: .whitespacesAndNewlines)
        if let rawURL = payload.url?.trimmingCharacters(in: .whitespacesAndNewlines),
           !rawURL.isEmpty, let url = URL(string: rawURL), url.scheme?.hasPrefix("http") == true {
            var block = Block(projectId: inbox.id, type: .webArchive,
                              title: url.host ?? rawURL, url: rawURL, siteName: url.host)
            if !text.isEmpty { block.content = text }
            insertBlock(block)
            commit()
            return true
        }
        guard !text.isEmpty else { return false }
        var draft = Block(projectId: inbox.id, type: .text, title: "", content: text)
        draft.title = draft.suggestedTitle()
        insertBlock(draft)
        commit()
        return true
    }
}
