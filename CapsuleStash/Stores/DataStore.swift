import Foundation
import LocalAuthentication

/// T-02/T-06 인메모리 저장소 + 선택 상태 + 검색 (2단: Workspace → Project 문서).
/// 영구 저장은 `SwiftDataBackend` 가 담당하고, 여기서는 문서 상태와 탐색만 다룬다.
/// library.json은 최초 1회 마이그레이션 원본으로만 읽는다.
@MainActor
final class DataStore: ObservableObject {
    @Published private(set) var workspaces: [Workspace] = []
    @Published var selectedProjectId: UUID?
    @Published var searchQuery: String = ""
    @Published var isVaultUnlocked: Bool = false
    @Published private(set) var recents: [RecentEntry] = []

    /// 사이드바 펼침 상태
    @Published var expandedWorkspaces: Set<UUID> = []

    private var saveTask: Task<Void, Never>?
    private let persistEnabled: Bool

    // MARK: - 초기화

    /// - Parameters:
    ///   - samples: 저장소(DB 우선, 없으면 library.json 마이그레이션)를 먼저 읽는다 (기본 true)
    ///   - loadSeeds: 저장소가 없거나 비어 있으면 시드 데이터를 채운다
    ///   - persist: 변경 시 디스크에 기록한다. 테스트는 `false` 로 지정해 사용자 데이터를 오염시키지 않는다.
    init(samples: Bool = true, loadSeeds: Bool = true, persist: Bool = true) {
        let start = CFAbsoluteTimeGetCurrent()
        self.persistEnabled = persist

        let loaded: [Workspace]? = samples ? SwiftDataBackend.loadOrMigrate() : nil
        if let loaded, !loaded.isEmpty {
            workspaces = loaded
            DebugLogger.cache("캐시 히트 — 저장소에서 복원")
        } else if loadSeeds {
            workspaces = Self.seed()
            DebugLogger.feature("시드 데이터로 시작")
        } else {
            workspaces = []
            DebugLogger.info("빈 저장소로 시작")
        }
        restoreSecretsFromKeychain()
        expandDefaults()
        selectFirstProject()
        DebugLogger.perf(String(format: "저장소 준비 %.0fms", (CFAbsoluteTimeGetCurrent() - start) * 1000))
    }

    // MARK: - 탐색 헬퍼

    var allProjects: [(workspace: Workspace, project: Project)] {
        workspaces.flatMap { ws in ws.projects.map { (ws, $0) } }
    }

    var favoriteProjects: [(workspace: Workspace, project: Project)] {
        allProjects.filter { $0.project.isFavorite }
    }

    var credentialCount: Int {
        allProjects.reduce(0) { $0 + $1.project.blocks.filter { $0.type == .credential }.count }
    }

    var selectedProject: Project? {
        if let id = selectedProjectId,
           let found = allProjects.first(where: { $0.project.id == id }) {
            return found.project
        }
        return allProjects.first?.project
    }

    func locate(_ project: Project) -> (workspace: Workspace, project: Project)? {
        allProjects.first { $0.project.id == project.id }
    }

    // MARK: - 선택 / 최근 사용

    func select(_ project: Project) {
        selectedProjectId = project.id
        recents.removeAll { $0.id == project.id }
        recents.insert(RecentEntry(id: project.id, title: project.name), at: 0)
        if recents.count > 8 { recents.removeLast(recents.count - 8) }
        if let entry = locate(project) {
            expandedWorkspaces.insert(entry.workspace.id)
        }
    }

    private func selectFirstProject() {
        if let first = allProjects.first {
            selectedProjectId = first.project.id
        }
    }

    private func expandDefaults() {
        if let ws = workspaces.first {
            expandedWorkspaces.insert(ws.id)
        }
    }

    // MARK: - 검색

    var parsedQuery: SearchQuery { SearchQuery.parse(searchQuery) }

    var searchHits: [SearchHit] {
        let query = parsedQuery
        guard !query.isEmpty else { return [] }

        var hits: [SearchHit] = []

        for entry in allProjects {
            if let projectName = query.projectName,
               entry.project.name.lowercased() != projectName.lowercased() {
                continue
            }

            // 문서 자체
            if query.types.isEmpty, matches(query.freeText, [entry.project.name, entry.project.note, entry.project.tags.joined(separator: " ")]) {
                hits.append(SearchHit(
                    id: "project-\(entry.project.id)",
                    kind: .project,
                    project: entry.project,
                    workspaceName: entry.workspace.name,
                    block: nil,
                    snippet: "\(entry.project.blocks.count)개 블록"
                ))
            }

            for block in entry.project.sortedBlocks {
                if !query.types.isEmpty, !query.types.contains(block.type) { continue }
                guard matches(query.freeText, [block.searchIndexText]) else { continue }

                let kind: SearchHit.Kind = block.type == .credential ? .credential : .block
                hits.append(SearchHit(
                    id: "block-\(block.id)",
                    kind: kind,
                    project: entry.project,
                    workspaceName: entry.workspace.name,
                    block: block,
                    snippet: snippet(for: block, term: query.freeText)
                ))
            }
        }

        // 문서 히트 우선, 그 다음 블록 내용 일치 순
        return hits.sorted { lhs, rhs in
            if lhs.kind != rhs.kind {
                return kindRank(lhs.kind) < kindRank(rhs.kind)
            }
            return score(rhs) > score(lhs)
        }
    }

    private func kindRank(_ kind: SearchHit.Kind) -> Int {
        switch kind {
        case .project: return 0
        case .block: return 1
        case .credential: return 2
        }
    }

    private func score(_ hit: SearchHit) -> Int {
        let term = parsedQuery.freeText
        guard !term.isEmpty else { return 0 }
        if hit.title.lowercased().hasPrefix(term) { return 30 }
        if hit.title.lowercased().contains(term) { return 20 }
        if hit.block?.searchIndexText.lowercased().contains(term) == true { return 10 }
        return 1
    }

    private func matches(_ term: String, _ candidates: [String]) -> Bool {
        if term.isEmpty { return true }
        return candidates.contains { $0.lowercased().contains(term) }
    }

    private func snippet(for block: Block, term: String) -> String {
        if block.type.isCode {
            let firstLine = block.content.split(separator: "\n").first.map(String.init) ?? block.content
            return "\(block.language?.uppercased() ?? "CODE") · \(firstLine)"
        }
        guard !term.isEmpty else {
            return block.displaySubtitle
        }
        let text = block.content.replacingOccurrences(of: "\n", with: " ")
        guard let range = text.lowercased().range(of: term) else { return block.displaySubtitle }
        let start = text.index(range.lowerBound, offsetBy: -20, limitedBy: text.startIndex) ?? text.startIndex
        let end = text.index(range.upperBound, offsetBy: 40, limitedBy: text.endIndex) ?? text.endIndex
        return (start == text.startIndex ? "" : "…") + text[start..<end] + (end == text.endIndex ? "" : "…")
    }

    // MARK: - 변이 (CRUD)

    func createWorkspace(name: String) {
        let ws = Workspace(name: name)
        workspaces.append(ws)
        expandedWorkspaces.insert(ws.id)
        commit()
        DebugLogger.feature("Workspace 생성: \(name)")
    }

    func renameWorkspace(_ id: UUID, to name: String) {
        guard let index = workspaces.firstIndex(where: { $0.id == id }) else { return }
        workspaces[index].name = name
        commit()
    }

    func deleteWorkspace(_ id: UUID) {
        if let ws = workspaces.first(where: { $0.id == id }) {
            for project in ws.projects {
                for block in project.blocks {
                    if block.credential != nil {
                        KeychainStore.delete(blockId: block.id)
                    }
                    if let name = block.archiveFile {
                        WebArchiveStore.remove(kind: WebArchiveStore.archiveKind, name: name)
                    }
                    if let name = block.pdfFile {
                        WebArchiveStore.remove(kind: WebArchiveStore.pdfKind, name: name)
                    }
                }
            }
        }
        workspaces.removeAll { $0.id == id }
        commit()
        DebugLogger.feature("Workspace 삭제")
    }

    /// 문서(Project) 생성 후 자동 선택. 색은 워크스페이스 내 순서대로 순환.
    @discardableResult
    func createProject(title: String, in workspaceId: UUID) -> Project? {
        guard let wsIndex = workspaces.firstIndex(where: { $0.id == workspaceId }) else { return nil }
        let palette = ["#FF5C00", "#2D5BD7", "#5F6F52", "#C99A2E", "#7A2EE0"]
        let project = Project(
            workspaceId: workspaceId,
            name: title,
            colorHex: palette[workspaces[wsIndex].projects.count % palette.count]
        )
        workspaces[wsIndex].projects.append(project)
        expandedWorkspaces.insert(workspaceId)
        select(project)
        commit()
        DebugLogger.feature("Project 생성: \(title)")
        return project
    }

    func renameProject(_ project: Project, to name: String) {
        mutateProject(project.id) { $0.name = name }
    }

    func deleteProject(_ project: Project) {
        for block in project.blocks {
            if block.credential != nil {
                KeychainStore.delete(blockId: block.id)
            }
            if let name = block.archiveFile {
                WebArchiveStore.remove(kind: WebArchiveStore.archiveKind, name: name)
            }
            if let name = block.pdfFile {
                WebArchiveStore.remove(kind: WebArchiveStore.pdfKind, name: name)
            }
        }
        for wsIndex in workspaces.indices {
            workspaces[wsIndex].projects.removeAll { $0.id == project.id }
        }
        if selectedProjectId == project.id { selectedProjectId = nil }
        recents.removeAll { $0.id == project.id }
        commit()
        DebugLogger.feature("Project 삭제")
    }

    /// Project를 다른 Workspace로 이동 (사이드바 드래그앤드롭).
    /// - Returns: 실제 이동이 일어났는지. 같은 Workspace·없는 id면 false.
    @discardableResult
    func moveProject(_ projectId: UUID, to workspaceId: UUID) -> Bool {
        guard let fromIndex = workspaces.firstIndex(where: { $0.projects.contains(where: { $0.id == projectId }) }),
              let toIndex = workspaces.firstIndex(where: { $0.id == workspaceId }),
              fromIndex != toIndex,
              let projectIndex = workspaces[fromIndex].projects.firstIndex(where: { $0.id == projectId })
        else { return false }
        var project = workspaces[fromIndex].projects[projectIndex]
        workspaces[fromIndex].projects.remove(at: projectIndex)
        project.workspaceId = workspaceId
        workspaces[toIndex].projects.append(project)
        expandedWorkspaces.insert(workspaceId)
        select(project)
        commit()
        DebugLogger.feature("Project 이동: \(project.name)")
        return true
    }

    func toggleFavorite(_ project: Project) {
        mutateProject(project.id) { $0.isFavorite.toggle() }
    }

    /// 태그 추가. 앞뒤 공백과 `#` 접두어를 제거하고 중복을 막는다.
    func addTag(_ tag: String, to project: Project) {
        var cleaned = tag.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.hasPrefix("#") { cleaned.removeFirst() }
        cleaned = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return }
        mutateProject(project.id) { project in
            guard !project.tags.contains(cleaned) else { return }
            project.tags.append(cleaned)
        }
        DebugLogger.feature("태그 추가: \(cleaned)")
    }

    func removeTag(_ tag: String, from project: Project) {
        mutateProject(project.id) { project in
            project.tags.removeAll { $0 == tag }
        }
        DebugLogger.feature("태그 제거: \(tag)")
    }

    /// 새 블록 삽입. sortOrder는 맨 끝으로 지정한다.
    /// 추가 플로우는 생성 우선: 입력 시트에서 완성된 값을 받아 한 번에 삽입한다.
    func insertBlock(_ block: Block) {
        mutateProject(block.projectId) { project in
            var inserted = block
            inserted.sortOrder = project.blocks.count
            project.blocks.append(inserted)
        }
        DebugLogger.feature("블록 추가: \(block.type.displayName)")
    }

    func updateBlock(_ block: Block) {
        mutateProject(block.projectId) { project in
            guard let index = project.blocks.firstIndex(where: { $0.id == block.id }) else { return }
            project.blocks[index] = block
        }
    }

    func toggleBlockCollapsed(_ block: Block) {
        mutateBlock(block.id) { $0.isCollapsed.toggle() }
    }

    func deleteBlock(_ block: Block) {
        if block.credential != nil {
            KeychainStore.delete(blockId: block.id)
        }
        // T-09 아카이브 실파일 정리 (이미지·파일 첨부 정리는 T-12)
        if let name = block.archiveFile {
            WebArchiveStore.remove(kind: WebArchiveStore.archiveKind, name: name)
        }
        if let name = block.pdfFile {
            WebArchiveStore.remove(kind: WebArchiveStore.pdfKind, name: name)
        }
        mutateProject(block.projectId) { project in
            project.blocks.removeAll { $0.id == block.id }
        }
        DebugLogger.feature("블록 삭제")
    }

    func moveBlock(_ block: Block, offset: Int) {
        mutateProject(block.projectId) { project in
            let order = project.blocks.sorted { $0.sortOrder < $1.sortOrder }
            guard let index = order.firstIndex(where: { $0.id == block.id }) else { return }
            let target = index + offset
            guard order.indices.contains(target) else { return }
            let a = order[index], b = order[target]
            for i in project.blocks.indices {
                if project.blocks[i].id == a.id { project.blocks[i].sortOrder = b.sortOrder }
                if project.blocks[i].id == b.id { project.blocks[i].sortOrder = a.sortOrder }
            }
        }
    }

    // MARK: - Vault

    /// 설정(⌘,)의 생체 인증 스위치. 기본 켜짐.
    var vaultBiometricEnabled: Bool {
        UserDefaults.standard.object(forKey: "vaultBiometric") as? Bool ?? true
    }

    /// Vault 해제 요청. 생체 인증 가능하면 Touch ID·Face ID를 먼저 거친다.
    /// 미지원 기기·스위치 OFF면 기존처럼 바로 해제한다.
    func requestVaultUnlock(reason: String = "Vault 잠금을 해제합니다", completion: @escaping (Bool) -> Void) {
        guard vaultBiometricEnabled else {
            unlockVault()
            completion(true)
            return
        }
        let context = LAContext()
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) else {
            unlockVault()
            completion(true)
            return
        }
        context.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, localizedReason: reason) { [weak self] success, _ in
            Task { @MainActor in
                guard let self else {
                    completion(false)
                    return
                }
                if success {
                    self.unlockVault()
                } else {
                    DebugLogger.error(code: ErrorCode.vaultLocked, "생체 인증 실패 — Vault 잠금 유지")
                }
                completion(success)
            }
        }
    }

    func unlockVault() {
        isVaultUnlocked = true
        DebugLogger.feature("Vault 잠금 해제")
    }

    func lockVault() {
        isVaultUnlocked = false
        // [HARD] 비밀값 로그 금지 — 잠금 시 시드/잔여 비밀값을 메모리에서 비운다.
        DebugLogger.info("Vault 잠금")
    }

    /// Keychain에서 시크릿을 복원해 메모리에 채운다 (디스크 JSON에는 시크릿이 없음).
    /// 테스트에서 직접 호출해 복원 경로를 검증한다.
    func restoreSecretsFromKeychain() {
        for wsIndex in workspaces.indices {
            for index in workspaces[wsIndex].projects.indices {
                for blockIndex in workspaces[wsIndex].projects[index].blocks.indices {
                    guard workspaces[wsIndex].projects[index].blocks[blockIndex].credential != nil else { continue }
                    let blockId = workspaces[wsIndex].projects[index].blocks[blockIndex].id
                    if let secrets = KeychainStore.load(blockId: blockId) {
                        workspaces[wsIndex].projects[index].blocks[blockIndex].credential?.password = secrets.password
                        workspaces[wsIndex].projects[index].blocks[blockIndex].credential?.secondSecret = secrets.secondSecret
                    }
                }
            }
        }
    }

    // MARK: - 내부 변이 유틸

    private func mutateProject(_ projectId: UUID, _ transform: (inout Project) -> Void) {
        for wsIndex in workspaces.indices {
            guard let index = workspaces[wsIndex].projects.firstIndex(where: { $0.id == projectId }) else { continue }
            transform(&workspaces[wsIndex].projects[index])
            workspaces[wsIndex].projects[index].updatedAt = Date()
            commit()
            return
        }
    }

    private func mutateBlock(_ blockId: UUID, _ transform: (inout Block) -> Void) {
        for wsIndex in workspaces.indices {
            for index in workspaces[wsIndex].projects.indices {
                guard let blockIndex = workspaces[wsIndex].projects[index].blocks.firstIndex(where: { $0.id == blockId }) else { continue }
                transform(&workspaces[wsIndex].projects[index].blocks[blockIndex])
                workspaces[wsIndex].projects[index].updatedAt = Date()
                commit()
                return
            }
        }
    }

    // MARK: - 저장

    /// [HARD] 시크릿(password/secondSecret)은 디스크에 내려가지 않는다.
    /// 홈페이지·아이디(비밀값 아님)는 보관하고 시크릿만 비운다. 시크릿은 Keychain에 별도 보관.
    static func persistableSnapshot(from workspaces: [Workspace]) -> [Workspace] {
        workspaces.map { ws in
            Workspace(id: ws.id, name: ws.name, projects: ws.projects.map { project in
                var copy = project
                copy.blocks = project.blocks.map { block in
                    var b = block
                    b.credential?.password = ""
                    b.credential?.secondSecret = ""
                    return b
                }
                return copy
            })
        }
    }

    private var persistableSnapshot: [Workspace] {
        Self.persistableSnapshot(from: workspaces)
    }

    /// 커밋 시점의 시크릿 모음 (Keychain 동기화용).
    private var credentialSecrets: [(UUID, KeychainStore.Secrets)] {
        workspaces.flatMap(\.projects).flatMap(\.blocks).compactMap { block in
            guard let credential = block.credential else { return nil }
            return (block.id, KeychainStore.Secrets(password: credential.password, secondSecret: credential.secondSecret))
        }
    }

    /// 디바운스 저장 (0.6s). 테스트처럼 `persist: false` 로 만든 인스턴스는 아무것도 쓰지 않는다.
    func commit() {
        guard persistEnabled else { return }
        saveTask?.cancel()
        let snapshot = persistableSnapshot
        let secrets = credentialSecrets
        saveTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 600_000_000)
            guard !Task.isCancelled else { return }
            do {
                try SwiftDataBackend.save(snapshot)
                KeychainStore.sync(secrets)
                await MainActor.run { self?.saveTask = nil }
            } catch {
                DebugLogger.error(code: ErrorCode.storeSave, "저장 실패")
            }
        }
    }

    // MARK: - 통계 (DebugPanel)

    var stats: [(String, String)] {
        [
            ("Workspace", "\(workspaces.count)"),
            ("Project", "\(allProjects.count)"),
            ("Block", "\(allProjects.reduce(0) { $0 + $1.project.blocks.count })"),
            ("Credential", "\(credentialCount)"),
            ("Keychain", "\(KeychainStore.count())"),
        ]
    }

    // MARK: - v1 → v2 마이그레이션

    /// v1(Workspace→Project→Collection)을 2단(Workspace→Project 문서)으로 변환한다.
    /// - 문서 id는 Collection id를 그대로 승계 (최근사용·선택 호환)
    /// - 旧 묶음(Project)명은 태그로 보존, 색은 묶음 색을 승계
    /// - 비어 있던 묶음은 빈 문서로 보존 (데이터 손실 없음)
    nonisolated static func migrate(_ legacy: [LegacyV1Workspace]) -> [Workspace] {
        legacy.map { ws in
            var projects: [Project] = []
            for pj in ws.projects {
                if pj.collections.isEmpty {
                    projects.append(Project(id: pj.id, workspaceId: ws.id, name: pj.name, colorHex: pj.colorHex))
                    continue
                }
                for col in pj.collections {
                    var tags = col.tags
                    if !tags.contains(pj.name) { tags.append(pj.name) }
                    let blocks = col.blocks.map { b in
                        Block(id: b.id, projectId: col.id, type: b.type, title: b.title,
                              content: b.content.trimmingCharacters(in: .newlines),
                              language: b.language, url: b.url, siteName: b.siteName,
                              savedAt: b.savedAt, imageNames: b.imageNames,
                              credential: b.credential, isCollapsed: b.isCollapsed,
                              sortOrder: b.sortOrder, createdAt: b.createdAt, updatedAt: b.updatedAt)
                    }
                    projects.append(Project(id: col.id, workspaceId: ws.id, name: col.title,
                                            colorHex: pj.colorHex, note: col.note, tags: tags,
                                            isFavorite: col.isFavorite, createdAt: col.createdAt,
                                            updatedAt: col.updatedAt, blocks: blocks))
                }
            }
            return Workspace(id: ws.id, name: ws.name, projects: projects)
        }
    }

    // MARK: - 시드 데이터 (목업 mockup-v0.1.html 대응, 2단)

    nonisolated static func seed() -> [Workspace] {
        // MARK: 개발
        let dev = Workspace(name: "개발")
        var webDoc = Project(workspaceId: dev.id, name: "WKWebView로 웹 페이지 저장하기",
                             colorHex: "#FF5C00",
                             note: "WebArchive + PDF + 본문 텍스트 조합으로 저장",
                             tags: ["webkit", "archive"])
        webDoc.blocks = seedBlocks(projectId: webDoc.id)

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

    nonisolated private static func seedBlocks(projectId: UUID) -> [Block] {
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

// MARK: - Block 보조

extension Block {
    var displaySubtitle: String {
        switch type {
        case .code, .shell:
            let first = content.split(separator: "\n").first.map(String.init) ?? ""
            return "\(language?.uppercased() ?? type.label) · \(first)"
        case .webLink, .webArchive:
            return [siteName, url].compactMap { $0 }.joined(separator: " · ")
        case .image:
            return imageNames.joined(separator: ", ")
        case .credential:
            return credential?.homepage ?? "홈페이지 없음"
        default:
            return content.split(separator: "\n").first.map(String.init) ?? ""
        }
    }

    var badgeLabel: String {
        if type == .code, let language, !language.isEmpty {
            return "CODE • \(language.uppercased())"
        }
        if type == .image, imageNames.count > 1 {
            return "IMAGE ×\(imageNames.count)"
        }
        return type.label
    }

    /// URL의 호스트 (표시용). 없으면 nil.
    var webHost: String? {
        guard let urlString = url, let url = URL(string: urlString) else { return nil }
        return url.host
    }
}
