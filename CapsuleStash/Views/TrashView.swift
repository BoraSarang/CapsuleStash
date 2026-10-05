import SwiftUI

/// T-58 휴지통 화면. 삭제된 문서·블록의 복원·완전 삭제 + 모두 비우기.
/// 30일 보관 후 기동 시 자동 완전 삭제. 팝오버 없이 버튼·얼럿만 쓴다.
struct TrashView: View {
    @EnvironmentObject private var store: DataStore
    @EnvironmentObject private var appState: AppState
    @Environment(\.locale) private var locale

    @State private var confirmEmpty = false
    @State private var confirmDeleteId: UUID?

    private var trashedProjects: [TrashedProject] {
        store.trash.compactMap {
            if case .project(let item) = $0 { return item }
            return nil
        }
    }

    private var trashedBlocks: [TrashedBlock] {
        store.trash.compactMap {
            if case .block(let item) = $0 { return item }
            return nil
        }
    }

    private var trashedWorkspaces: [TrashedWorkspace] {
        store.trash.compactMap {
            if case .workspace(let item) = $0 { return item }
            return nil
        }
    }

    private func relative(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = locale
        formatter.unitsStyle = .short
        return formatter.localizedString(for: date, relativeTo: Date())
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                header
                if store.trash.isEmpty {
                    emptyState
                } else {
                    if !trashedWorkspaces.isEmpty {
                        sectionLabel(text: "워크스페이스")
                        ForEach(trashedWorkspaces, id: \.workspace.id) { item in
                            workspaceRow(item)
                        }
                    }
                    if !trashedProjects.isEmpty {
                        sectionLabel(text: "문서")
                        ForEach(trashedProjects, id: \.project.id) { item in
                            projectRow(item)
                        }
                    }
                    if !trashedBlocks.isEmpty {
                        sectionLabel(text: "블록")
                        ForEach(trashedBlocks, id: \.block.id) { item in
                            blockRow(item)
                        }
                    }
                }
            }
            .padding(.horizontal, Theme.contentPadding)
            .padding(.vertical, 26)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Theme.paper)
        .alert(Text(L10n.string("모두 비우기")), isPresented: $confirmEmpty) {
            Button("완전 삭제", role: .destructive) {
                let count = store.emptyTrash()
                appState.notify(L10n.format("%lld개 완전히 삭제됨", count))
            }
            Button("취소", role: .cancel) {}
        } message: {
            Text("휴지통을 비우면 되돌릴 수 없습니다.")
        }
        .alert(Text(L10n.string("완전 삭제")), isPresented: Binding(
            get: { confirmDeleteId != nil },
            set: { if !$0 { confirmDeleteId = nil } }
        )) {
            Button("완전 삭제", role: .destructive) {
                if let id = confirmDeleteId, store.deleteForever(id) {
                    appState.notify(L10n.string("완전히 삭제됨"))
                }
                confirmDeleteId = nil
            }
            Button("취소", role: .cancel) { confirmDeleteId = nil }
        } message: {
            Text("휴지통에서 지우면 되돌릴 수 없습니다.")
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: "trash")
                    .font(.system(size: 20))
                    .foregroundStyle(Theme.muted)
                LText(key: "휴지통")
                    .font(Theme.serif(32))
                    .foregroundStyle(Theme.ink)
            }
            HStack(spacing: 12) {
                Text(L10n.format("항목 %lld개", store.trashCount))
                Text("•")
                LText(key: "30일 후 자동 삭제됩니다")
                Spacer(minLength: 0)
                if !store.trash.isEmpty {
                    CapsuleButton(title: "모두 비우기") { confirmEmpty = true }
                }
            }
            .font(.system(size: 13))
            .foregroundStyle(Theme.muted)
            Divider().overlay(Theme.line).padding(.top, 12)
        }
        .padding(.bottom, 16)
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "trash")
                .font(.system(size: 28, weight: .light))
                .foregroundStyle(Theme.muted)
            LText(key: "휴지통이 비었습니다")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Theme.ink)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 48)
    }

    private func sectionLabel(text: String) -> some View {
        LText(key: text)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(Theme.muted)
            .padding(.top, 12)
            .padding(.bottom, 4)
    }

    private func workspaceRow(_ item: TrashedWorkspace) -> some View {
        trashRow(
            icon: "folder",
            title: item.workspace.name,
            subtitle: "\(L10n.format("문서 %lld개", item.workspace.projects.count)) • \(relative(item.deletedAt))",
            onRestore: {
                if store.restoreFromTrash(item.workspace.id) {
                    appState.notify(L10n.string("복원됨"))
                }
            },
            onDelete: { confirmDeleteId = item.workspace.id }
        )
    }

    private func projectRow(_ item: TrashedProject) -> some View {
        trashRow(
            icon: "doc",
            title: item.project.name,
            subtitle: "\(item.workspaceName) • \(relative(item.deletedAt))",
            onRestore: {
                if store.restoreFromTrash(item.project.id) {
                    appState.notify(L10n.string("복원됨"))
                }
            },
            onDelete: { confirmDeleteId = item.project.id }
        )
    }

    private func blockRow(_ item: TrashedBlock) -> some View {
        trashRow(
            icon: item.block.type.symbolName,
            title: item.block.title,
            subtitle: "\(L10n.string(item.block.type.displayName)) • \(relative(item.deletedAt))",
            onRestore: {
                if store.restoreFromTrash(item.block.id) {
                    appState.notify(L10n.string("복원됨"))
                }
            },
            onDelete: { confirmDeleteId = item.block.id }
        )
    }

    private func trashRow(icon: String, title: String, subtitle: String,
                          onRestore: @escaping () -> Void,
                          onDelete: @escaping () -> Void) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 13))
                .foregroundStyle(Theme.muted)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.ink)
                    .lineLimit(1)
                Text(subtitle)
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.muted)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            CapsuleButton(title: "복원", action: onRestore)
            Button("완전 삭제") { onDelete() }
                .buttonStyle(.plain)
                .font(.system(size: 13))
                .foregroundStyle(.red)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Theme.line, lineWidth: 1))
        .padding(.vertical, 4)
    }
}
