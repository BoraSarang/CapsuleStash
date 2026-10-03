import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// T-03 왼쪽 트리 (2단: Workspace → Project 문서).
/// 행 메트릭은 Workspace 행과 SMART 행이 텍스트 시작점을 공유한다:
/// 섹션 14 + 컨테이너 0/4 + 행패딩 8 + 아이콘(셰브론≈7/11) + 간격 6 → 텍스트 ≈ 39.
struct SidebarView: View {
    @EnvironmentObject private var store: DataStore
    @EnvironmentObject private var appState: AppState

    @State private var namePrompt: NamePrompt?
    @State private var deleteTarget: DeleteTarget?
    /// 드래그 중인 Project를 받을 Workspace 하이라이트
    @State private var dropWorkspaceId: UUID?
    /// 드래그 중인 Project를 받을 Project 행 하이라이트 (T-35 같은 문서 순서 변경)
    @State private var dropProjectId: UUID?

    /// 행 하이라이트용 isTargeted 바인딩
    private func dropBinding(for id: UUID) -> Binding<Bool> {
        Binding(
            get: { dropProjectId == id },
            set: { hovering in
                if hovering { dropProjectId = id }
                else if dropProjectId == id { dropProjectId = nil }
            }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ScrollView {
                VStack(alignment: .leading, spacing: 6) {
                    SidebarSectionLabel(text: "WORKSPACE")
                    ForEach(store.workspaces) { ws in
                        workspaceSection(ws)
                    }
                    Button {
                        namePrompt = NamePrompt(
                            title: "새 Workspace",
                            subtitle: nil,
                            placeholder: "Workspace 이름",
                            initial: L10n.format("새 Workspace %lld", store.workspaces.count + 1),
                            confirmTitle: "추가",
                            onConfirm: { store.createWorkspace(name: $0) }
                        )
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "plus").imageScale(.small)
                            Text("Workspace 추가").font(.system(size: 12))
                        }
                        .foregroundStyle(Theme.sidebarMuted)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 6)
                    }
                    .buttonStyle(.plain)
                    .help("새 Workspace 추가")

                    SidebarSectionLabel(text: "SMART")
                    smartRow("즐겨찾기", systemImage: "star", count: store.favoriteProjects.count)
                    smartRow("최근 사용", systemImage: "clock", count: store.recents.count)
                    smartRow("계정 / Credential", systemImage: "lock", count: store.credentialCount)
                }
                .padding(.horizontal, 14)
                .padding(.top, 12)
            }

            sidebarFooter
        }
        .background(Theme.sidebar)
        .sheet(item: $namePrompt) { prompt in
            NameInputSheet(prompt: prompt)
        }
        .alert(item: $deleteTarget) { target in
            switch target {
            case .workspace(let ws):
                return Alert(
                    title: Text(L10n.format("'%@' 삭제", ws.name)),
                    message: Text(L10n.format("포함된 Project %lld개가 모두 사라집니다.", ws.projects.count)),
                    primaryButton: .destructive(Text("삭제")) {
                        store.deleteWorkspace(ws.id)
                        appState.notify("삭제됨")
                    },
                    secondaryButton: .cancel(Text("취소"))
                )
            case .project(let project):
                return Alert(
                    title: Text(L10n.format("'%@' 삭제", project.name)),
                    message: Text(L10n.format("포함된 블록 %lld개가 모두 사라집니다.", project.blocks.count)),
                    primaryButton: .destructive(Text("삭제")) {
                        store.deleteProject(project)
                        appState.notify("삭제됨")
                    },
                    secondaryButton: .cancel(Text("취소"))
                )
            }
        }
    }

    /// 삭제 확인 대상
    private enum DeleteTarget: Identifiable {
        case workspace(Workspace)
        case project(Project)

        var id: String {
            switch self {
            case .workspace(let ws): return "ws-\(ws.id.uuidString)"
            case .project(let project): return "doc-\(project.id.uuidString)"
            }
        }
    }

    // MARK: - Workspace / Project (문서)

    @ViewBuilder
    private func workspaceSection(_ ws: Workspace) -> some View {
        let expanded = store.expandedWorkspaces.contains(ws.id)
        VStack(alignment: .leading, spacing: 0) {
            Button {
                toggleWorkspace(ws.id)
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: expanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(Theme.sidebarMuted)
                    Text(ws.name)
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(Theme.sidebarText)
                    Spacer(minLength: 4)
                    Text("\(ws.projects.count)")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(Theme.sidebarMuted)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .contextMenu {
                Button("Project 추가…") { newProject(in: ws) }
                Button("Workspace 이름 바꾸기…", action: { rename(workspace: ws) })
                Divider()
                Button("JSON으로 내보내기") { exportWorkspace(ws, ext: "json") }
                Button("Markdown으로 내보내기") { exportWorkspace(ws, ext: "md") }
                Divider()
                Button("Workspace 삭제", role: .destructive) { deleteTarget = .workspace(ws) }
            }

            if expanded {
                // 문서는 워크스페이스명보다 1단(16pt) 들여쓰기
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(ws.projects) { project in
                        projectRow(project, in: ws.id)
                    }
                }
                .padding(.leading, 16)
                .padding(.top, 2)
            }
        }
        .padding(4)
        .background(dropWorkspaceId == ws.id ? Theme.sidebarHover : .clear, in: RoundedRectangle(cornerRadius: Theme.controlRadius))
        .onDrop(of: [.plainText], isTargeted: Binding(
            get: { dropWorkspaceId == ws.id },
            set: { hovering in
                if hovering { dropWorkspaceId = ws.id }
                else if dropWorkspaceId == ws.id { dropWorkspaceId = nil }
            }
        )) { providers in
            dropProject(providers, to: ws)
            return true
        }
    }

    private func projectRow(_ project: Project, in workspaceId: UUID) -> some View {
        let isActive = store.selectedProjectId == project.id
        return Button {
            store.select(project)
        } label: {
            HStack(spacing: 8) {
                Circle()
                    .fill(Theme.color(hexString: project.colorHex))
                    .frame(width: 7, height: 7)
                Text(project.name)
                    .font(.system(size: 13, weight: isActive ? .bold : .regular))
                    .lineLimit(1)
                Spacer(minLength: 2)
                if project.isFavorite {
                    Image(systemName: "star.fill")
                        .font(.system(size: 9))
                        .foregroundStyle(Theme.gold)
                }
            }
            .foregroundStyle(isActive ? Theme.ink : Theme.sidebarMuted)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 8)
            .padding(.vertical, 7)
            .background(
                dropProjectId == project.id ? Theme.sidebarHover
                    : isActive ? Theme.paper : .clear,
                in: RoundedRectangle(cornerRadius: Theme.controlRadius)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onDrag { NSItemProvider(object: "\(DataStore.projectDragPrefix)\(project.id.uuidString)" as NSString) }
        .onDrop(of: [.plainText], isTargeted: dropBinding(for: project.id)) { providers in
            providers.first?.loadObject(ofClass: NSString.self) { object, _ in
                guard let raw = object as? String else { return }
                let idString = raw.hasPrefix(DataStore.projectDragPrefix)
                    ? String(raw.dropFirst(DataStore.projectDragPrefix.count)) : raw
                guard let draggedId = UUID(uuidString: idString) else { return }
                Task { @MainActor in
                    _ = self.store.moveProjectTo(draggedId, before: project.id, in: workspaceId)
                }
            }
            return true
        }
        .contextMenu {
            Button(project.isFavorite ? "즐겨찾기 해제" : "즐겨찾기") { store.toggleFavorite(project) }
            Button("이름 바꾸기…") { rename(project: project) }
            Button("복사") {
                if ClipboardService.copy(project.plainText(includeTitle: true, includeSecrets: store.isVaultUnlocked), label: project.name) {
                    appState.notifyCopy(project.name)
                }
            }
            Divider()
            Button("JSON으로 내보내기") { exportProject(project, ext: "json") }
            Button("Markdown으로 내보내기") { exportProject(project, ext: "md") }
            Divider()
            Button("삭제", role: .destructive) { deleteTarget = .project(project) }
        }
    }

    /// SMART 행 — Workspace 행과 텍스트 시작점(≈39)을 공유하도록
    /// 행패딩 8 + 아이콘 11 + 간격 6 으로 맞춘다.
    private func smartRow(_ title: String, systemImage: String, count: Int) -> some View {
        HStack(spacing: 6) {
            Image(systemName: systemImage)
                .font(.system(size: 10))
                .frame(width: 11)
                .foregroundStyle(Theme.sidebarMuted)
            LText(key: title)
                .font(.system(size: 13))
                .foregroundStyle(Theme.sidebarMuted)
            Spacer()
            Text("\(count)")
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(Theme.sidebarMuted)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 8)
        .contentShape(Rectangle())
        .onTapGesture { DebugLogger.feature("Smart 필터: \(title)") }
    }

    // MARK: - 푸터 (Vault 잠금 상태)

    private var sidebarFooter: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: store.isVaultUnlocked ? "lock.open" : "lock")
                        .font(.system(size: 11))
                    Text(LocalizedStringKey(store.isVaultUnlocked ? "Vault 열림" : "Vault 잠김"))
                        .font(.system(size: 12))
                }
                .foregroundStyle(Theme.sidebarMuted)

                Spacer()

                CapsuleButton(
                    title: store.isVaultUnlocked ? "잠금" : "해제",
                    style: .primary,
                    action: { appState.toggleVault(store) }
                )
            }
        }
        .padding(12)
        .background(Theme.sidebarElevated, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Theme.sidebarLine, lineWidth: 1))
        .padding(.horizontal, 14)
        .padding(.bottom, 14)
    }

    // MARK: - 동작

    /// 사이드바 드롭: Project 행을 다른 Workspace에 떨어뜨리면 이동한다.
    /// 같은 Workspace 행에 떨어뜨리면 행 드롭(moveProjectTo)이 순서 변경을 담당한다.
    private func dropProject(_ providers: [NSItemProvider], to ws: Workspace) {
        guard let provider = providers.first(where: { $0.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) }) else { return }
        provider.loadObject(ofClass: NSString.self) { object, _ in
            guard let raw = object as? String else { return }
            let idString = raw.hasPrefix(DataStore.projectDragPrefix)
                ? String(raw.dropFirst(DataStore.projectDragPrefix.count)) : raw
            guard let projectId = UUID(uuidString: idString) else { return }
            Task { @MainActor in
                guard let project = store.allProjects.first(where: { $0.project.id == projectId })?.project else { return }
                if store.moveProject(projectId, to: ws.id) {
                    appState.notify(L10n.format("'%@' → '%@'으로 이동", project.name, ws.name))
                }
            }
        }
    }

    private func toggleWorkspace(_ id: UUID) {
        if store.expandedWorkspaces.contains(id) { store.expandedWorkspaces.remove(id) }
        else { store.expandedWorkspaces.insert(id) }
    }

    private func newProject(in ws: Workspace) {
        namePrompt = NamePrompt(
            title: "새 Project",
            subtitle: LocalizedStringKey(L10n.format("'%@' 워크스페이스에 추가됩니다", ws.name)),
            placeholder: "Project 이름",
            initial: L10n.format("새 Project %lld", ws.projects.count + 1),
            confirmTitle: "추가",
            onConfirm: {
                if let project = store.createProject(title: $0, in: ws.id) {
                    appState.notify(L10n.format("“%@” 생성됨", project.name))
                }
            }
        )
    }

    private func rename(workspace ws: Workspace) {
        namePrompt = NamePrompt(
            title: "Workspace 이름 변경",
            subtitle: nil,
            placeholder: "Workspace 이름",
            initial: ws.name,
            confirmTitle: "저장",
            onConfirm: { store.renameWorkspace(ws.id, to: $0) }
        )
    }

    private func rename(project: Project) {
        namePrompt = NamePrompt(
            title: "Project 이름 변경",
            subtitle: nil,
            placeholder: "Project 이름",
            initial: project.name,
            confirmTitle: "저장",
            onConfirm: {
                store.renameProject(project, to: $0)
                appState.notify("이름 변경됨")
            }
        )
    }

    // MARK: - T-50 내보내기 (NSSavePanel, 시크릿 제외는 전송 계층이 보장)

    private func exportWorkspace(_ ws: Workspace, ext: String) {
        if ext == "json" {
            guard let data = try? LibraryTransfer.exportJSON(workspaces: [ws]) else {
                appState.notify("내보내기 실패")
                return
            }
            saveExport(data: data, filename: LibraryTransfer.safeFilename(ws.name, ext: "json"),
                       contentType: .json)
        } else {
            saveExport(text: LibraryTransfer.markdown(for: ws),
                       filename: LibraryTransfer.safeFilename(ws.name, ext: "md"),
                       // UTType.markdown은 구 OS 배포 타깃에서 불가 — 내용은 텍스트라 plainText로 충분
                       contentType: .plainText)
        }
    }

    private func exportProject(_ project: Project, ext: String) {
        if ext == "json" {
            guard let ws = store.workspaces.first(where: { $0.id == project.workspaceId }),
                  let data = try? LibraryTransfer.exportJSON(workspaces: [Workspace(
                    id: ws.id, name: ws.name,
                    projects: ws.projects.filter { $0.id == project.id })]) else {
                appState.notify("내보내기 실패")
                return
            }
            saveExport(data: data, filename: LibraryTransfer.safeFilename(project.name, ext: "json"),
                       contentType: .json)
        } else {
            saveExport(text: LibraryTransfer.markdown(for: project),
                       filename: LibraryTransfer.safeFilename(project.name, ext: "md"),
                       contentType: .plainText)
        }
    }

    private func saveExport(text: String, filename: String, contentType: UTType) {
        guard let data = text.data(using: .utf8) else {
            appState.notify("내보내기 실패")
            return
        }
        saveExport(data: data, filename: filename, contentType: contentType)
    }

    private func saveExport(data: Data, filename: String, contentType: UTType) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = filename
        panel.allowedContentTypes = [contentType]
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let dest = panel.url else { return }
        do {
            try data.write(to: dest, options: .atomic)
            // [HARD] paths are user data — log file name only, never contents.
            DebugLogger.feature("내보내기: \(dest.lastPathComponent)")
            appState.notify("내보냄")
        } catch {
            DebugLogger.error(code: ErrorCode.storeSave, "내보내기 실패")
            appState.notify("내보내기 실패")
        }
    }
}
