import SwiftUI

/// T-04 Project 문서 상세 (제목 + 메타 + 블록 목록 + 블록 추가).
struct ProjectDetailView: View {
    @EnvironmentObject private var store: DataStore
    @EnvironmentObject private var appState: AppState

    let project: Project
    let workspaceName: String

    @State private var isEditingTitle = false
    @State private var titleDraft = ""
    @State private var isEditingTags = false
    @State private var newTagText = ""
    @State private var isAddingBlock = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                header
                if project.sortedBlocks.isEmpty {
                    emptyBlocks
                } else {
                    VStack(spacing: Theme.blockSpacing) {
                        ForEach(Array(project.sortedBlocks.enumerated()), id: \.element.id) { index, block in
                            BlockCardView(
                                block: block,
                                isFirst: index == 0,
                                isLast: index == project.sortedBlocks.count - 1
                            )
                        }
                    }
                    .padding(.top, 4)
                }
                addBlockRow
            }
            .padding(.horizontal, Theme.contentPadding)
            .padding(.vertical, 26)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Theme.paper)
        .sheet(item: $appState.blockCreation) { request in
            BlockEditorSheet(create: request)
                .environmentObject(store)
                .environmentObject(appState)
        }
    }

    // MARK: - 헤더

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("\(workspaceName) / PROJECT")
                .font(.system(size: 12))
                .kerning(0.4)
                .foregroundStyle(Theme.muted)

            if isEditingTitle {
                TextField("Project 이름", text: $titleDraft)
                    .font(Theme.serif(40))
                    .foregroundStyle(Theme.ink)
                    .textFieldStyle(.plain)
                    .onSubmit(commitTitle)
                CapsuleButton(title: "저장", style: .primary, action: commitTitle)
            } else {
                Text(project.name)
                    .font(Theme.serif(40))
                    .foregroundStyle(Theme.ink)
                    .lineLimit(2)
            }

            HStack(spacing: 12) {
                Text("수정 \(relativeDate)")
                Text("•")
                Text("블록 \(project.blocks.count)개")
                if project.codeCount > 0 {
                    Text("•")
                    Text("코드 \(project.codeCount)개")
                }
                tagRow
                Spacer(minLength: 0)
                CapsuleIconButton(
                    systemImage: project.isFavorite ? "star.fill" : "star",
                    tooltip: project.isFavorite ? "즐겨찾기됨" : "즐겨찾기",
                    tint: project.isFavorite ? Theme.gold : nil
                ) {
                    store.toggleFavorite(project)
                }
                CapsuleIconButton(systemImage: "pencil", tooltip: "제목 편집") { startTitleEdit() }
                CapsuleIconButton(systemImage: "doc.on.doc", tooltip: "전체 복사", style: .primary) { copyAll() }
            }
            .font(.system(size: 13))
            .foregroundStyle(Theme.muted)

            Divider().overlay(Theme.line).padding(.top, 12)
        }
        .padding(.bottom, 16)
    }

    private var relativeDate: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = Locale(identifier: "ko_KR")
        formatter.unitsStyle = .short
        return formatter.localizedString(for: project.updatedAt, relativeTo: Date())
    }

    // MARK: - 태그 편집

    @ViewBuilder
    private var tagRow: some View {
        if isEditingTags {
            ForEach(project.tags, id: \.self) { tag in
                HStack(spacing: 4) {
                    Text("#\(tag)")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.ink)
                    Button {
                        store.removeTag(tag, from: project)
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(Theme.muted)
                    }
                    .buttonStyle(.plain)
                    .help("태그 제거")
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Color.white, in: Capsule())
                .overlay(Capsule().strokeBorder(Theme.accent.opacity(0.5), lineWidth: 1))
            }
            TextField("태그 추가 후 Enter", text: $newTagText)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 12))
                .frame(width: 130)
                .onSubmit(commitTag)
            CapsuleButton(title: "완료", style: .primary) {
                commitTag()
                isEditingTags = false
            }
        } else {
            ForEach(project.tags, id: \.self) { tag in
                TagChip(text: tag)
            }
            Button {
                newTagText = ""
                isEditingTags = true
            } label: {
                HStack(spacing: 3) {
                    Image(systemName: "plus")
                        .font(.system(size: 10, weight: .bold))
                    Text("태그")
                        .font(.system(size: 12))
                }
                .foregroundStyle(Theme.muted)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Color.clear, in: Capsule())
                .overlay(Capsule().strokeBorder(Theme.line, lineWidth: 1))
            }
            .buttonStyle(.plain)
            .help("태그 편집")
        }
    }

    private var emptyBlocks: some View {
        VStack(spacing: 8) {
            Image(systemName: "capsule")
                .font(.system(size: 28, weight: .light))
                .foregroundStyle(Theme.muted)
            Text("아직 블록이 없습니다")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Theme.ink)
            Text("아래 + 버튼에서 텍스트·코드·웹·이미지·파일·계정 정보 블록을 추가해 보세요.")
                .font(.system(size: 13))
                .foregroundStyle(Theme.muted)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 48)
    }

    private var addBlockRow: some View {
        Button {
            isAddingBlock = true
        } label: {
            Image(systemName: "plus.circle.fill")
                .font(.system(size: 20))
                .foregroundStyle(Theme.accent)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(Theme.accentSoft, in: RoundedRectangle(cornerRadius: Theme.controlRadius))
                .overlay(RoundedRectangle(cornerRadius: Theme.controlRadius).strokeBorder(Theme.accent.opacity(0.4), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .help("블록 추가")
        .popover(isPresented: $isAddingBlock) {
            BlockTypePicker(projectId: project.id) { isAddingBlock = false }
        }
        .padding(.top, 16)
        .padding(.bottom, 40)
    }

    // MARK: - 동작

    private func commitTag() {
        let text = newTagText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !text.isEmpty {
            store.addTag(text, to: project)
            newTagText = ""
        }
    }

    private func startTitleEdit() {
        titleDraft = project.name
        isEditingTitle = true
    }

    private func commitTitle() {
        let trimmed = titleDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { store.renameProject(project, to: trimmed) }
        isEditingTitle = false
    }

    private func copyAll() {
        let includeSecrets = store.isVaultUnlocked
        let text = project.sortedBlocks
            .map { "## \($0.title)\n\($0.copyPayload(includeSecrets: includeSecrets))" }
            .joined(separator: "\n\n")
        guard !text.isEmpty else {
            appState.notify("복사할 블록이 없습니다")
            return
        }
        if ClipboardService.copy(text, label: project.name) {
            appState.notifyCopy(project.name)
        }
    }
}
