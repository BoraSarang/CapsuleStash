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
    /// T-55 스마트 그룹 (검색 조건 저장, UserDefaults 영속화)
    @Published var smartGroups: [SmartGroup] = []

    private static let smartGroupsKey = "smartGroups"

    private var saveTask: Task<Void, Never>?
    private let persistEnabled: Bool
    /// 첨부·아카이브 정리용 기준 폴더. 테스트 격리용 (기본 nil = 실제 Application Support).
    private let attachmentBaseDirectory: URL?

    // MARK: - 초기화

    /// - Parameters:
    ///   - samples: 저장소(DB 우선, 없으면 library.json 마이그레이션)를 먼저 읽는다 (기본 true)
    ///   - loadSeeds: 저장소가 없거나 비어 있으면 시드 데이터를 채운다
    ///   - persist: 변경 시 디스크에 기록한다. 테스트는 `false` 로 지정해 사용자 데이터를 오염시키지 않는다.
    ///   - attachmentBase: 첨부 정리 기준 폴더. 테스트는 임시 폴더를 지정한다.
    init(samples: Bool = true, loadSeeds: Bool = true, persist: Bool = true, attachmentBase: URL? = nil) {
        let start = CFAbsoluteTimeGetCurrent()
        self.persistEnabled = persist
        self.attachmentBaseDirectory = attachmentBase

        let loaded: [Workspace]? = samples ? SwiftDataBackend.loadOrMigrate() : nil
        if let loaded, !loaded.isEmpty {
            workspaces = loaded
            DebugLogger.cache("캐시 히트 — 저장소에서 복원")
        } else if loadSeeds {
            workspaces = SeedData.workspaces()
            DebugLogger.feature("시드 데이터로 시작")
        } else {
            workspaces = []
            DebugLogger.info("빈 저장소로 시작")
        }
        normalizeWebBlocks()
        restoreSecretsFromKeychain()
        expandDefaults()
        selectFirstProject()
        loadSmartGroups()
        DebugLogger.perf(String(format: "저장소 준비 %.0fms", (CFAbsoluteTimeGetCurrent() - start) * 1000))
    }

    // MARK: - 탐색 헬퍼

    /// 레거시 `webLink` 블록을 `webArchive` 로 통일한다 (T-28, 필드 그대로 승계).
    /// 다음 commit 때 DB에도 반영된다.
    func normalizeWebBlocks() {
        var converted = 0
        for wsIndex in workspaces.indices {
            for index in workspaces[wsIndex].projects.indices {
                for blockIndex in workspaces[wsIndex].projects[index].blocks.indices {
                    if workspaces[wsIndex].projects[index].blocks[blockIndex].type == .webLink {
                        workspaces[wsIndex].projects[index].blocks[blockIndex].type = .webArchive
                        converted += 1
                    }
                }
            }
        }
        if converted > 0 {
            DebugLogger.feature("웹 블록 통합: \(converted)개")
        }
    }

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
                    removeBlockFiles(block)
                }
            }
        }
        workspaces.removeAll { $0.id == id }
        commit()
        DebugLogger.feature("Workspace 삭제")
    }

    /// T-50 가져오기: 외부 JSON의 Workspace들을 새 복사본으로 편입한다.
    /// - Returns: 편입한 Workspace 수.
    @discardableResult
    func importWorkspaces(_ workspaces: [Workspace]) -> Int {
        let mapped = LibraryTransfer.remapForImport(workspaces)
        self.workspaces.append(contentsOf: mapped)
        for ws in mapped { expandedWorkspaces.insert(ws.id) }
        if let first = mapped.first?.projects.first { select(first) }
        commit()
        DebugLogger.feature("Workspace 가져오기: \(mapped.count)개")
        return mapped.count
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
            removeBlockFiles(block)
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

    /// T-35 Project 드래그 페이로드 접두사 (`capsule-project:<uuid>`).
    static let projectDragPrefix = "capsule-project:"

    /// 같은 Workspace 안에서 Project 순서를 바꾼다 (사이드바 드래그).
    /// dragged·target이 같은 문서에 없으면 무시한다 (다른 문서로는 Workspace 드롭 사용).
    /// - Returns: 실제 이동 여부.
    @discardableResult
    func moveProjectTo(_ draggedId: UUID, before targetId: UUID, in workspaceId: UUID) -> Bool {
        guard draggedId != targetId,
              let wsIndex = workspaces.firstIndex(where: { $0.id == workspaceId }) else { return false }
        var order = workspaces[wsIndex].projects
        guard let from = order.firstIndex(where: { $0.id == draggedId }),
              let to = order.firstIndex(where: { $0.id == targetId }) else { return false }
        let dragged = order.remove(at: from)
        order.insert(dragged, at: from < to ? to - 1 : to)
        workspaces[wsIndex].projects = order
        commit()
        DebugLogger.feature("Project 순서 이동")
        return true
    }

    func toggleFavorite(_ project: Project) {
        mutateProject(project.id) { $0.isFavorite.toggle() }
    }

    /// 태그 추가. 앞뒤 공백과 `#` 접두어를 제거하고 중복을 막는다.
    /// T-56 중첩 태그: `부모 / 자식`처럼 띄어 쓴 슬래시는 `부모/자식`으로 접는다.
    func addTag(_ tag: String, to project: Project) {
        var cleaned = tag.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.hasPrefix("#") { cleaned.removeFirst() }
        cleaned = cleaned.split(separator: "/")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "/")
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

    // MARK: - T-55 스마트 그룹

    /// 스마트 그룹 추가. 빈 이름·빈 조건은 무시한다. 같은 조건이 있으면 이름만 바꾼다.
    @discardableResult
    func addSmartGroup(name: String, query: String) -> SmartGroup? {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty, !trimmedQuery.isEmpty,
              !SearchQuery.parse(trimmedQuery).isEmpty else { return nil }
        if let index = smartGroups.firstIndex(where: { $0.query == trimmedQuery }) {
            smartGroups[index].name = trimmedName
            persistSmartGroups()
            return smartGroups[index]
        }
        let group = SmartGroup(name: trimmedName, query: trimmedQuery)
        smartGroups.append(group)
        persistSmartGroups()
        DebugLogger.feature("스마트 그룹 추가: \(trimmedName)")
        return group
    }

    func renameSmartGroup(_ id: UUID, to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let index = smartGroups.firstIndex(where: { $0.id == id }) else { return }
        smartGroups[index].name = trimmed
        persistSmartGroups()
    }

    func deleteSmartGroup(_ id: UUID) {
        smartGroups.removeAll { $0.id == id }
        persistSmartGroups()
        DebugLogger.feature("스마트 그룹 삭제")
    }

    /// 그룹 조건으로 돌린 결과 수 (사이드바 뱃지용).
    func hitCount(for group: SmartGroup) -> Int {
        hits(for: SearchQuery.parse(group.query)).count
    }

    private func loadSmartGroups() {
        guard let data = UserDefaults.standard.data(forKey: Self.smartGroupsKey),
              let groups = try? JSONDecoder().decode([SmartGroup].self, from: data) else { return }
        smartGroups = groups
    }

    private func persistSmartGroups() {
        guard persistEnabled else { return }
        if let data = try? JSONEncoder().encode(smartGroups) {
            UserDefaults.standard.set(data, forKey: Self.smartGroupsKey)
        }
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

    /// T-14 외부 드롭 가져오기. 파일은 이미지/텍스트내용/파일 블록으로, http(s) URL은 웹 링크로 만든다.
    /// `.md`→markdown·`.txt`→text 블록으로 내용을 읽는다 (1MB 초과·디코딩 실패는 파일 블록 폴백).
    /// - Returns: 생성된 블록 수 (없는 Project면 0).
    @discardableResult
    func importFileDrops(_ urls: [URL], to projectId: UUID) -> Int {
        guard allProjects.contains(where: { $0.project.id == projectId }) else { return 0 }
        var created = 0
        let files = urls.filter(\.isFileURL)
        let images = files.filter { AttachmentStore.isImageFile($0) }
        if !images.isEmpty {
            let names = AttachmentStore.importFiles(from: images, kind: AttachmentStore.imagesKind,
                                                    baseDirectory: attachmentBaseDirectory)
            if !names.isEmpty {
                insertBlock(Block(projectId: projectId, type: .image,
                                  title: L10n.format("이미지 %lld개", names.count), imageNames: names))
                created += 1
            }
        }
        let others = files.filter { !AttachmentStore.isImageFile($0) }
        // 텍스트로 읽히는 파일은 내용 블록으로 (md→markdown, txt→text). 나머지만 파일 블록.
        var textItems: [(type: BlockType, title: String, content: String)] = []
        var binaries: [URL] = []
        for url in others {
            if let type = Self.textBlockType(for: url),
               let content = Self.readableText(from: url),
               !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                let stem = url.deletingPathExtension().lastPathComponent
                textItems.append((type, stem.isEmpty ? type.displayName : String(stem.prefix(40)), content))
            } else {
                binaries.append(url)
            }
        }
        for item in textItems {
            insertBlock(Block(projectId: projectId, type: item.type, title: item.title, content: item.content))
            created += 1
        }
        if !binaries.isEmpty {
            let names = AttachmentStore.importFiles(from: binaries, kind: AttachmentStore.filesKind,
                                                    baseDirectory: attachmentBaseDirectory)
            if !names.isEmpty {
                let base = binaries[0].deletingPathExtension().lastPathComponent
                insertBlock(Block(projectId: projectId, type: .file,
                                  title: base.isEmpty ? "파일" : String(base.prefix(40)),
                                  imageNames: names))
                created += 1
            }
        }
        for url in urls where !url.isFileURL {
            insertBlock(Block(projectId: projectId, type: .webArchive,
                              title: url.host ?? url.absoluteString,
                              url: url.absoluteString, siteName: url.host))
            created += 1
        }
        if created > 0 {
            // [HARD] paths are user data — log counts only, never names.
            DebugLogger.feature("드롭 가져오기: 블록 \(created)개")
        }
        return created
    }

    /// 드롭 파일이 내용으로 읽히는 텍스트인지 (.md→markdown, .txt→text). 순수 판별.
    nonisolated static func textBlockType(for url: URL) -> BlockType? {
        switch url.pathExtension.lowercased() {
        case "md", "markdown", "mdown": return .markdown
        case "txt", "text": return .text
        default: return nil
        }
    }

    /// 드롭 파일 본문 읽기. UTF-8만 인정한다 (자동 감지는 이진까지 텍스트로
    /// 둔갑시켜서 제외). 1MB 초과·디코딩 실패 → nil (파일 블록 폴백). 순수 함수.
    nonisolated static func readableText(from url: URL, maxBytes: Int = 1_048_576) -> String? {
        guard let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize,
              size <= maxBytes,
              var text = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        if text.hasPrefix("\u{FEFF}") { text.removeFirst() }
        return text
    }

    /// T-14 텍스트 드롭 → 텍스트 블록. 빈 문자열은 무시한다.
    @discardableResult
    func importTextDrop(_ text: String, to projectId: UUID) -> Bool {
        guard allProjects.contains(where: { $0.project.id == projectId }) else { return false }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        let firstLine = trimmed.split(separator: "\n").first.map(String.init) ?? "텍스트"
        insertBlock(Block(projectId: projectId, type: .text,
                          title: String(firstLine.prefix(40)), content: trimmed))
        return true
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

    /// T-43 팔레트 이동 시 접힌 블록을 미리 펼친다 (스크롤 위치 보장).
    func expandBlock(_ blockId: UUID) {
        mutateBlock(blockId) { $0.isCollapsed = false }
    }

    /// 문서의 모든 블록을 접거나 펼친다 (T-27).
    func setAllBlocksCollapsed(_ collapsed: Bool, in projectId: UUID) {
        mutateProject(projectId) { project in
            for index in project.blocks.indices {
                project.blocks[index].isCollapsed = collapsed
            }
        }
        DebugLogger.feature(collapsed ? "블록 모두 접기" : "블록 모두 펼치기")
    }

    func deleteBlock(_ block: Block) {
        removeBlockFiles(block)
        mutateProject(block.projectId) { project in
            project.blocks.removeAll { $0.id == block.id }
        }
        DebugLogger.feature("블록 삭제")
    }

    /// 블록 삭제 시 동반 정리: Keychain 시크릿 + 아카이브 실파일 + 썸네일 + 이미지·파일 첨부.
    /// [HARD] 값 자체를 로그에 남기지 않는다.
    private func removeBlockFiles(_ block: Block) {
        if block.credential != nil {
            KeychainStore.delete(blockId: block.id)
        }
        if let name = block.archiveFile {
            WebArchiveStore.remove(kind: WebArchiveStore.archiveKind, name: name,
                                   baseDirectory: attachmentBaseDirectory)
        }
        if let name = block.pdfFile {
            WebArchiveStore.remove(kind: WebArchiveStore.pdfKind, name: name,
                                   baseDirectory: attachmentBaseDirectory)
        }
        if let name = block.thumbnailFile {
            WebArchiveStore.remove(kind: WebArchiveStore.thumbnailKind, name: name,
                                   baseDirectory: attachmentBaseDirectory)
        }
        let kind = block.type == .image ? AttachmentStore.imagesKind : AttachmentStore.filesKind
        for name in block.imageNames {
            AttachmentStore.remove(kind: kind, name: name, baseDirectory: attachmentBaseDirectory)
        }
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

    /// T-27 블록 드래그 페이로드 접두사 (`capsule-block:<uuid>`).
    /// 상세 화면의 텍스트 드롭과 구분한다.
    static let blockDragPrefix = "capsule-block:"

    /// 드래그한 블록을 대상 블록 앞으로 이동한다 (T-27, 같은 문서 안에서만).
    /// - Returns: 실제 이동 여부.
    @discardableResult
    func moveBlockTo(_ draggedId: UUID, before targetId: UUID, in projectId: UUID) -> Bool {
        guard draggedId != targetId else { return false }
        var moved = false
        mutateProject(projectId) { project in
            var order = project.blocks.sorted { $0.sortOrder < $1.sortOrder }
            guard let fromIndex = order.firstIndex(where: { $0.id == draggedId }),
                  let toIndex = order.firstIndex(where: { $0.id == targetId }) else { return }
            let dragged = order.remove(at: fromIndex)
            let adjusted = fromIndex < toIndex ? toIndex - 1 : toIndex
            order.insert(dragged, at: adjusted)
            for (index, element) in order.enumerated() {
                if let i = project.blocks.firstIndex(where: { $0.id == element.id }) {
                    project.blocks[i].sortOrder = index
                }
            }
            moved = true
        }
        if moved {
            DebugLogger.feature("블록 순서 이동")
        }
        return moved
    }

    // MARK: - Vault

    /// 설정(⌘,)의 생체 인증 스위치. 기본 켜짐.
    var vaultBiometricEnabled: Bool {
        UserDefaults.standard.object(forKey: "vaultBiometric") as? Bool ?? true
    }

    /// Vault 해제 요청. 생체 인증 가능하면 Touch ID·Face ID를 먼저 거친다.
    /// 미지원 기기·스위치 OFF면 기존처럼 바로 해제한다.
    func requestVaultUnlock(reason: String = L10n.string("Vault 잠금을 해제합니다"), completion: @escaping (Bool) -> Void) {
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

    /// T-17 종료 시 자동잠금. 설정(`vaultLockOnQuit`, 기본 켜짐)이 꺼져 있으면 아무것도 안 한다.
    func lockVaultOnQuitIfNeeded() {
        guard UserDefaults.standard.object(forKey: "vaultLockOnQuit") as? Bool ?? true else { return }
        if isVaultUnlocked {
            lockVault()
        }
        ClipboardService.clearSecretsOnQuit()
        DebugLogger.feature("종료 시 Vault 잠금 + 클립보드 정리")
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
    /// 순수 함수라 내보내기·백업 경로(비격리)에서도 부른다.
    nonisolated static func persistableSnapshot(from workspaces: [Workspace]) -> [Workspace] {
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
            return credential?.homepage ?? L10n.string("홈페이지 없음")
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
