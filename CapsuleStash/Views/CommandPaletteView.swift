import SwiftUI

/// T-05/T-06 Command Palette. 목업 `.palette` 대응.
/// `⌘⇧Space` 로 어디서든 호출, 검색 결과에서 Enter 열기 / ⌘C 복사.
struct CommandPaletteView: View {
    @EnvironmentObject private var store: DataStore
    @EnvironmentObject private var appState: AppState
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    @FocusState private var isFieldFocused: Bool
    @State private var highlightedIndex: Int = 0

    private var hits: [SearchHit] { store.searchHits }

    var body: some View {
        ZStack {
            // 배경 흐림 + 클릭 닫기
            Color.black.opacity(0.45)
                .ignoresSafeArea()
                .onTapGesture { appState.hidePalette() }

            paletteCard
                .frame(width: 640)
                .padding(.horizontal, 24)
                .onKeyPress(.escape) {
                    appState.hidePalette()
                    return .handled
                }
                .onKeyPress(.upArrow) {
                    moveHighlight(-1)
                    return .handled
                }
                .onKeyPress(.downArrow) {
                    moveHighlight(1)
                    return .handled
                }
                // T-15 Credential 필드 단축키: ⌘1 아이디, ⌘2 Secret 1(Vault 해제 시만).
                // ⌘C 는 검색창의 기본 텍스트 복사와 충돌하므로 결과 행의 복사 버튼을 쓴다.
                .onKeyPress(phases: .down) { press in
                    guard press.modifiers.contains(.command) else { return .ignored }
                    if press.characters == "1" {
                        return copyCredentialField(secret: false) ? .handled : .ignored
                    }
                    if press.characters == "2" {
                        return copyCredentialField(secret: true) ? .handled : .ignored
                    }
                    return .ignored
                }
        }
        .onAppear {
            isFieldFocused = true
            highlightedIndex = 0
            DebugLogger.perf("팔레트 표시")
        }
        .onChange(of: store.searchQuery) { _, _ in
            highlightedIndex = 0
        }
    }

    private var paletteCard: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(Theme.muted)
                TextField("검색: docker, github, swift…", text: $store.searchQuery)
                    .textFieldStyle(.plain)
                    .font(.system(size: 17))
                    .foregroundStyle(Theme.ink)
                    .focused($isFieldFocused)
                    .onSubmit(openHighlighted)
                if !store.searchQuery.isEmpty {
                    Button {
                        store.searchQuery = ""
                        highlightedIndex = 0
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(Theme.muted)
                    }
                    .buttonStyle(.plain)
                }
                Text("esc")
                    .font(Theme.monoCaption)
                    .foregroundStyle(Theme.muted)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Theme.tagBackground, in: Capsule())
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)

            DashedLine(color: Theme.line, pattern: [5, 4]).frame(height: 1)

            results
        }
        .background(cardBackground, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(.white.opacity(0.6), lineWidth: 1))
        .shadow(color: .black.opacity(0.35), radius: 30, y: 18)
    }

    private var cardBackground: Color {
        reduceTransparency ? Theme.card : Theme.card.opacity(0.98)
    }

    @ViewBuilder
    private var results: some View {
        ScrollView {
            VStack(spacing: 2) {
                if store.searchQuery.isEmpty {
                    hintRow(systemImage: "clock", text: "최근 사용", project: recentProject)
                } else if hits.isEmpty {
                    VStack(spacing: 6) {
                        Text("일치하는 항목이 없습니다")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Theme.ink)
                        Text(SearchQuery.usageHint)
                            .font(.system(size: 12))
                            .foregroundStyle(Theme.muted)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 28)
                } else {
                    ForEach(Array(hits.enumerated()), id: \.element.id) { index, hit in
                        hitRow(hit, isHighlighted: index == highlightedIndex)
                            .onTapGesture { activate(hit) }
                    }
                }
            }
            .padding(8)
        }
        .frame(maxHeight: 380)
    }

    private var recentProject: Project? {
        guard let id = store.recents.first?.id else { return store.selectedProject }
        return store.allProjects.first { $0.project.id == id }?.project ?? store.selectedProject
    }

    private func hintRow(systemImage: String, text: String, project: Project?) -> some View {
        Button {
            if let project { store.select(project); appState.hidePalette() }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: systemImage)
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.muted)
                    .frame(width: 16)
                VStack(alignment: .leading, spacing: 2) {
                    Text(project?.name ?? "최근 사용 없음")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Theme.ink)
                    Text(text)
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.muted)
                }
                Spacer()
                Text("↵ 열기")
                    .font(Theme.monoCaption)
                    .foregroundStyle(Theme.muted)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func hitRow(_ hit: SearchHit, isHighlighted: Bool) -> some View {
        HStack(spacing: 12) {
            badge(for: hit)

            VStack(alignment: .leading, spacing: 2) {
                Text(hit.title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.ink)
                    .lineLimit(1)
                Text(hit.path + (hit.snippet.isEmpty ? "" : " · \(hit.snippet)"))
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.muted)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            if hit.kind == .block, hit.block != nil {
                CapsuleIconButton(systemImage: "doc.on.doc", tooltip: "복사", style: .primary) {
                    copy(hit)
                }
            }

            Text(shortcutHint(for: hit))
                .font(Theme.monoCaption)
                .foregroundStyle(Theme.muted)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(isHighlighted ? Theme.accentSoft : .clear, in: RoundedRectangle(cornerRadius: 10))
        .contentShape(Rectangle())
    }

    private func badge(for hit: SearchHit) -> some View {
        switch hit.kind {
        case .project:
            return TypeBadge(text: "PROJECT", type: .text)
        case .credential:
            return TypeBadge(text: "CRED", type: .credential)
        case .block:
            guard let block = hit.block else { return TypeBadge(text: "BLOCK", type: .text) }
            return TypeBadge(text: block.badgeLabel, type: block.type)
        }
    }

    private func shortcutHint(for hit: SearchHit) -> String {
        switch hit.kind {
        case .project: return "↵ 열기"
        case .block: return "↵ 열기"
        case .credential: return "⌘1 ID ⌘2 PW"
        }
    }

    /// 결과 행의 복사 버튼 동작. Credential 은 비밀값을 직접 복사하지 않는다.
    private func copy(_ hit: SearchHit) {
        guard let block = hit.block else {
            let text = hit.project.sortedBlocks
                .map { "## \($0.title)\n\($0.copyPayload())" }
                .joined(separator: "\n\n")
            if ClipboardService.copy(text, label: hit.project.name) {
                appState.notifyCopy(hit.project.name)
            }
            return
        }

        // [HARD] Credential 비밀값은 팔레트에서 복사하지 않는다. 잠금 해제 후 본문에서 복사.
        if block.type == .credential, let credential = block.credential {
            let payload = [credential.username, credential.homepage].filter { !$0.isEmpty }.joined(separator: "\n")
            if ClipboardService.copy(payload, label: "\(block.title) (계정·비밀값 제외)") {
                appState.notifyCopy("\(block.title) 아이디/홈페이지")
            }
            return
        }

        if ClipboardService.copy(block.copyPayload(), label: block.title) {
            appState.notifyCopy(block.title)
        }
    }

    // MARK: - 키보드 처리

    /// T-15 하이라이트된 Credential 행의 필드 복사. 복사했으면 true.
    /// 시크릿은 Vault 잠금 해제 상태에서만 복사한다 ([HARD]).
    @discardableResult
    private func copyCredentialField(secret: Bool) -> Bool {
        guard !hits.isEmpty else { return false }
        let hit = hits[min(highlightedIndex, hits.count - 1)]
        guard hit.kind == .credential, let block = hit.block else { return false }
        if let text = block.credentialCopyText(secret: secret, vaultUnlocked: store.isVaultUnlocked) {
            let label = secret ? "\(block.title) Secret 1" : "\(block.title) 아이디"
            if ClipboardService.copy(text, label: label, isSecret: secret) {
                appState.notifyCopy(label, isSecret: secret)
                return true
            }
            return false
        }
        if secret {
            if !store.isVaultUnlocked {
                DebugLogger.error(code: ErrorCode.vaultLocked, "\(block.title) 비밀값 접근 시도")
                appState.notify("Vault를 먼저 해제하세요")
            } else {
                appState.notify("복사할 Secret 1이 없습니다")
            }
        } else {
            appState.notify("복사할 아이디가 없습니다")
        }
        return true
    }

    private func openHighlighted() {
        guard !hits.isEmpty else { return }
        activate(hits[min(highlightedIndex, hits.count - 1)])
    }

    private func activate(_ hit: SearchHit) {
        store.select(hit.project)
        DebugLogger.feature("팔레트 이동: \(hit.title)")
        appState.hidePalette()
    }

    /// 하이라이트 이동 (↑/↓). `KeyPress` 초기화가 없어 `.onKeyPress` 대신 스크롤 오프셋으로 반영한다.
    func moveHighlight(_ delta: Int) {
        guard !hits.isEmpty else { return }
        highlightedIndex = (highlightedIndex + delta + hits.count) % hits.count
    }
}