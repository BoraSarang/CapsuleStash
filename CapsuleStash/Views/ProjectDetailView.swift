import SwiftUI
import UniformTypeIdentifiers

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
    @State private var isDropTargeted = false
    @State private var railOpen = false
    @Environment(\.locale) private var locale

    var body: some View {
        ScrollViewReader { proxy in
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
                                .id(block.id)
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
            // T-43 팔레트에서 온 블록 이동 요청 처리 (프로젝트 전환·같은 문서 모두 onChange로 받는다)
            .onAppear { consumePendingScroll(proxy) }
            .onChange(of: appState.pendingBlockScroll) { _, _ in consumePendingScroll(proxy) }
            // T-38 본문 우측 플로팅 블록 바로가기 (···). 접힌 블록은 펼치고 이동.
            .overlay(alignment: .trailing) {
                if project.sortedBlocks.count > 1 {
                    blockRail(proxy: proxy)
                }
            }
            // T-14 외부 드롭으로 블록 추가 (파일·텍스트·웹URL). 카드가 파일을 선점하면 건너뛴다.
            .overlay(
                RoundedRectangle(cornerRadius: Theme.cardRadius)
                    .strokeBorder(isDropTargeted ? Theme.accent : Color.clear, lineWidth: 2)
                    .padding(8)
            )
            .onDrop(of: [.fileURL, .plainText, .url], isTargeted: $isDropTargeted) { providers in
                let cardClaimedFiles = appState.fileDropHandled
                appState.fileDropHandled = false
                handleExternalDrop(providers, skipFiles: cardClaimedFiles)
                return true
            }
            .sheet(item: $appState.blockCreation) { request in
                BlockEditorSheet(create: request)
                    .environmentObject(store)
                    .environmentObject(appState)
            }
        }
    }

    /// T-43 팔레트에서 온 블록 이동 요청 처리. 펼치고 해당 위치로 스크롤한다.
    /// 요청은 한 번만 소비한다 (nil로 비움). 펼친 뒤 레이아웃이 잡히고 이동한다.
    private func consumePendingScroll(_ proxy: ScrollViewProxy) {
        guard let id = appState.pendingBlockScroll,
              project.sortedBlocks.contains(where: { $0.id == id }) else { return }
        appState.pendingBlockScroll = nil
        scrollToBlock(id, proxy: proxy)
    }

    /// 블록으로 스크롤 (접혔으면 펼치고 이동). 레일·팔레트 이동 공유.
    private func scrollToBlock(_ id: UUID, proxy: ScrollViewProxy) {
        store.expandBlock(id)
        DispatchQueue.main.async {
            withAnimation(.easeOut(duration: 0.25)) {
                proxy.scrollTo(id, anchor: .top)
            }
        }
    }

    /// 우측 플로팅 블록 바로가기 (T-38).
    /// 평소엔 ≡ 버튼만, 누르면 네모 패널에 아이콘·점·제목 목록. 행 호버하면 전체 제목 툴팁.
    /// 클릭하면 해당 블록으로 이동 (접혀 있으면 먼저 펼친다).
    /// T-44 패널은 고정 폭(꽉 채우지 않음) + 본문과 다른 배경 + 벗어나면 자동 닫기.
    private func blockRail(proxy: ScrollViewProxy) -> some View {
        VStack {
            if railOpen {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(project.sortedBlocks.enumerated()), id: \.element.id) { index, block in
                            Button {
                                railOpen = false
                                scrollToBlock(block.id, proxy: proxy)
                            } label: {
                                HStack(spacing: 8) {
                                    Image(systemName: block.type.symbolName)
                                        .font(.system(size: 12))
                                        .foregroundStyle(Theme.muted)
                                        .frame(width: 16, alignment: .leading)
                                    Circle()
                                        .fill(block.isCollapsed ? Theme.muted : Theme.badgeColor(for: block.type))
                                        .frame(width: 6, height: 6)
                                    Text(block.title)
                                        .font(.system(size: 13))
                                        .foregroundStyle(Theme.ink)
                                        .lineLimit(1)
                                        .truncationMode(.tail)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                                .padding(.horizontal, 10)
                                .padding(.vertical, 7)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .help(block.title)
                            if index < project.sortedBlocks.count - 1 {
                                Divider().overlay(Theme.line)
                            }
                        }
                    }
                }
                .frame(width: 210)
                .frame(maxHeight: 280)
                .padding(.vertical, 4)
                .background(Theme.tagBackground, in: RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Theme.line, lineWidth: 1))
                .shadow(color: .black.opacity(0.2), radius: 12, y: 6)
            }
            Button {
                withAnimation(.easeOut(duration: 0.15)) {
                    railOpen.toggle()
                }
            } label: {
                Image(systemName: "line.3.horizontal")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.ink)
                    .frame(width: 32, height: 32)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .background(Theme.tagBackground, in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Theme.line, lineWidth: 1))
            .shadow(color: .black.opacity(0.2), radius: 12, y: 6)
            .help("블록 바로가기")
        }
        .padding(.trailing, 10)
        // T-44 패널 영역에서 벗어나면 자동으로 닫는다
        .onHover { hovering in
            if !hovering {
                withAnimation(.easeOut(duration: 0.12)) {
                    railOpen = false
                }
            }
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
                Text(L10n.format("수정 %@", relativeDate))
                Text("•")
                Text(L10n.format("블록 %lld개", project.blocks.count))
                if project.codeCount > 0 {
                    Text("•")
                    Text(L10n.format("코드 %lld개", project.codeCount))
                }
                tagRow
                Spacer(minLength: 0)
                // T-27 모두 접기/펼치기 (상태에 따라 한 버튼만)
                CapsuleButton(
                    title: project.blocks.allSatisfy(\.isCollapsed) ? "모두 펼치기" : "모두 접기"
                ) {
                    let collapsed = !project.blocks.allSatisfy(\.isCollapsed)
                    store.setAllBlocksCollapsed(collapsed, in: project.id)
                }
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
        // 템플릿("Modified %@")과 같은 로케일을 써서 언어가 엇갈리지 않게 한다
        formatter.locale = locale
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
                .background(Theme.card, in: Capsule())
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

    /// 팝오버 대신 네이티브 Menu (베타 popover 크래시 회피 — ContentView.addMenu 참조).
    private var addBlockRow: some View {
        Menu {
            ForEach(BlockType.pickable) { type in
                Button {
                    appState.requestBlockCreation(type: type, in: project.id)
                } label: {
                    LText(key: type.displayName)
                }
                .help(L10n.string(type.purposeHint))
            }
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
        let text = project.plainText(includeSecrets: includeSecrets)
        guard !text.isEmpty else {
            appState.notify("복사할 블록이 없습니다")
            return
        }
        if ClipboardService.copy(text, label: project.name) {
            appState.notifyCopy(project.name)
        }
    }

    // MARK: - T-14 외부 드롭

    /// Finder·브라우저·텍스트 드롭으로 블록을 만든다.
    /// 카드가 파일을 선점했으면(`skipFiles`) 파일은 건너뛰고 텍스트·URL만 처리한다.
    private func handleExternalDrop(_ providers: [NSItemProvider], skipFiles: Bool) {
        if !skipFiles {
            AttachmentStore.urls(from: providers) { urls in
                guard !urls.isEmpty else { return }
                let created = self.store.importFileDrops(urls, to: self.project.id)
                if created > 0 {
                    self.appState.notify(L10n.format("블록 %lld개 추가됨", created))
                }
            }
        }
        for provider in providers {
            let isFile = provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier)
            if provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier), !isFile {
                provider.loadObject(ofClass: NSString.self) { object, _ in
                    guard let text = object as? String,
                          // 블록·문서 순서 드롭은 각자 카드·행이 처리 (T-27/T-35)
                          !text.hasPrefix(DataStore.blockDragPrefix),
                          !text.hasPrefix(DataStore.projectDragPrefix) else { return }
                    Task { @MainActor in
                        if self.store.importTextDrop(text, to: self.project.id) {
                            self.appState.notify("텍스트 블록 추가됨")
                        }
                    }
                }
            } else if provider.hasItemConformingToTypeIdentifier(UTType.url.identifier), !isFile {
                provider.loadItem(forTypeIdentifier: UTType.url.identifier, options: nil) { item, _ in
                    var url: URL?
                    if let direct = item as? URL {
                        url = direct
                    } else if let data = item as? Data {
                        url = URL(dataRepresentation: data, relativeTo: nil)
                    }
                    guard let url, url.scheme?.hasPrefix("http") == true else { return }
                    Task { @MainActor in
                        if self.store.importFileDrops([url], to: self.project.id) > 0 {
                            self.appState.notify("웹 링크 추가됨")
                        }
                    }
                }
            }
        }
    }
}
