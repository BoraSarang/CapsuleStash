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
                            subtitle: "",
                            placeholder: "Workspace 이름",
                            initial: "새 Workspace \(store.workspaces.count + 1)",
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
                    title: Text("'\(ws.name)' 삭제"),
                    message: Text("포함된 Project \(ws.projects.count)개가 모두 사라집니다."),
                    primaryButton: .destructive(Text("삭제")) {
                        store.deleteWorkspace(ws.id)
                        appState.notify("삭제됨")
                    },
                    secondaryButton: .cancel(Text("취소"))
                )
            case .project(let project):
                return Alert(
                    title: Text("'\(project.name)' 삭제"),
                    message: Text("포함된 블록 \(project.blocks.count)개가 모두 사라집니다."),
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
                Button("Workspace 삭제", role: .destructive) { deleteTarget = .workspace(ws) }
            }

            if expanded {
                // 문서는 워크스페이스명보다 1단(16pt) 들여쓰기
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(ws.projects) { project in
                        projectRow(project)
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

    private func projectRow(_ project: Project) -> some View {
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
            .background(isActive ? Theme.paper : .clear, in: RoundedRectangle(cornerRadius: Theme.controlRadius))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onDrag { NSItemProvider(object: project.id.uuidString as NSString) }
        .contextMenu {
            Button(project.isFavorite ? "즐겨찾기 해제" : "즐겨찾기") { store.toggleFavorite(project) }
            Button("이름 바꾸기…") { rename(project: project) }
            Button("복사") {
                if ClipboardService.copy(plainText(of: project), label: project.name) {
                    appState.notifyCopy(project.name)
                }
            }
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
            Text(title)
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
                    Text(store.isVaultUnlocked ? "Vault 열림" : "Vault 잠김")
                        .font(.system(size: 12))
                }
                .foregroundStyle(Theme.sidebarMuted)

                Spacer()

                CapsuleButton(
                    title: store.isVaultUnlocked ? "잠금" : "해제",
                    style: .primary,
                    action: toggleVault
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

    private func toggleVault() {
        if store.isVaultUnlocked {
            store.lockVault()
            appState.notify("Vault 잠금")
        } else {
            store.requestVaultUnlock { _ in
                appState.notify(store.isVaultUnlocked ? "Vault 잠금 해제" : "Vault 잠금 해제 실패")
            }
        }
    }

    /// 사이드바 드롭: Project 행을 다른 Workspace에 떨어뜨리면 이동한다.
    private func dropProject(_ providers: [NSItemProvider], to ws: Workspace) {
        guard let provider = providers.first(where: { $0.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) }) else { return }
        provider.loadObject(ofClass: NSString.self) { object, _ in
            guard let idString = object as? String, let projectId = UUID(uuidString: idString) else { return }
            Task { @MainActor in
                guard let project = store.allProjects.first(where: { $0.project.id == projectId })?.project else { return }
                if store.moveProject(projectId, to: ws.id) {
                    appState.notify("'\(project.name)' → '\(ws.name)'으로 이동")
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
            subtitle: "'\(ws.name)' 워크스페이스에 추가됩니다",
            placeholder: "Project 이름",
            initial: "새 Project \(ws.projects.count + 1)",
            confirmTitle: "추가",
            onConfirm: {
                if let project = store.createProject(title: $0, in: ws.id) {
                    appState.notify("“\(project.name)” 생성됨")
                }
            }
        )
    }

    private func rename(workspace ws: Workspace) {
        namePrompt = NamePrompt(
            title: "Workspace 이름 변경",
            subtitle: "",
            placeholder: "Workspace 이름",
            initial: ws.name,
            confirmTitle: "저장",
            onConfirm: { store.renameWorkspace(ws.id, to: $0) }
        )
    }

    private func rename(project: Project) {
        namePrompt = NamePrompt(
            title: "Project 이름 변경",
            subtitle: "",
            placeholder: "Project 이름",
            initial: project.name,
            confirmTitle: "저장",
            onConfirm: {
                store.renameProject(project, to: $0)
                appState.notify("이름 변경됨")
            }
        )
    }

    private func plainText(of project: Project) -> String {
        ([project.name] + project.sortedBlocks.map { "## \($0.title)\n\($0.copyPayload(includeSecrets: store.isVaultUnlocked))" }).joined(separator: "\n\n")
    }
}
