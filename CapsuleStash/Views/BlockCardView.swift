import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// T-04 블록 카드. 목업 `.block` 대응 (접기/펼치기 · 타입별 본문 · 복사).
struct BlockCardView: View {
    let block: Block
    var isFirst: Bool
    var isLast: Bool

    @EnvironmentObject private var store: DataStore
    @EnvironmentObject private var appState: AppState
    @State private var isEditing = false
    @State private var isDropTargeted = false
    @State private var isSavingArchive = false
    @State private var showingOffline = false
    /// 인라인 편집 상태 (T-13, 텍스트·코드 계열만)
    @State private var isInlineEditing = false
    @State private var draftContent = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            if !block.isCollapsed {
                DashedLine(color: Theme.line, pattern: [4, 3])
                    .frame(height: 1)
                bodyView
                    .padding(.horizontal, Theme.blockPadding)
                    .padding(.vertical, 14)
            }
        }
        .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.cardRadius))
        .overlay(RoundedRectangle(cornerRadius: Theme.cardRadius).strokeBorder(Theme.line, lineWidth: 1))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.cardRadius)
                .strokeBorder(isDropTargeted ? Theme.accent : Color.clear, lineWidth: 2)
        )
        .onDrop(of: [.fileURL], isTargeted: $isDropTargeted) { providers in
            // 이미지·파일 블록이 소비를 선언하면 상세 화면의 파일 드롭이 건너뛴다 (T-14 중복 방지)
            if block.type == .image || block.type == .file {
                appState.fileDropHandled = true
            }
            handleDrop(providers)
            return true
        }
        .sheet(isPresented: $isEditing) {
            BlockEditorSheet(block: block)
                .environmentObject(store)
                .environmentObject(appState)
        }
    }

    // MARK: - 헤더 (목업 `.block-head` + `편집` 버튼)

    private var header: some View {
        HStack(spacing: 10) {
            TypeBadge(text: block.badgeLabel, type: block.type)

            Text(block.title)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Theme.ink)
                .lineLimit(1)

            Spacer(minLength: 8)

            CapsuleIconButton(systemImage: "pencil", tooltip: "편집") {
                if canInlineEdit { startInlineEdit() } else { isEditing = true }
            }

            if block.type == .webLink || block.type == .webArchive {
                if let url = URL(string: block.url ?? "") {
                    CapsuleIconButton(systemImage: "arrow.up.forward.app", tooltip: "브라우저로 열기") {
                        open(url)
                    }
                }
                CapsuleIconButton(systemImage: "link", tooltip: "URL 복사") { copyURL() }
            } else if block.type == .credential {
                LText(key: vaultLabel)
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.muted)
            } else if block.type == .image || block.type == .file {
                CapsuleIconButton(systemImage: "folder", tooltip: "경로 복사") { copyImagePaths() }
            } else {
                CapsuleIconButton(systemImage: "doc.on.doc", tooltip: "복사", style: .primary) { copyBlockContent() }
            }

            CapsuleIconButton(
                systemImage: block.isCollapsed ? "chevron.down" : "chevron.up",
                tooltip: block.isCollapsed ? "펼치기" : "접기"
            ) {
                store.toggleBlockCollapsed(block)
            }

            Menu {
                Button(canInlineEdit ? "편집" : "편집…") {
                    if canInlineEdit { startInlineEdit() } else { isEditing = true }
                }
                if canInlineEdit {
                    Button("전체 편집…") { isEditing = true }
                }
                Divider()
                Button("위로") { store.moveBlock(block, offset: -1) }.disabled(isFirst)
                Button("아래로") { store.moveBlock(block, offset: 1) }.disabled(isLast)
                Button("이 Project 즐겨찾기") { toggleProjectFavorite() }
                Divider()
                Button("복사", action: copyBlockContent)
                Button("삭제", role: .destructive) {
                    store.deleteBlock(block)
                    appState.notify("블록 삭제됨")
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.ink)
                    .frame(width: 24, height: 22)
                    .contentShape(Rectangle())
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("더 보기")
        }
        .padding(.horizontal, Theme.blockPadding)
        .padding(.vertical, 12)
    }

    // MARK: - 본문

    @ViewBuilder
    private var bodyView: some View {
        switch block.type {
        case .code, .shell:
            if isInlineEditing {
                inlineEditor(mono: true)
            } else {
                codeBody
                    .onTapGesture(count: 2) { startInlineEdit() }
            }
        case .webLink, .webArchive:
            webBody
        case .image, .file:
            imageBody
        case .credential:
            credentialBody
        default:
            if isInlineEditing {
                inlineEditor(mono: false)
            } else {
                Text(block.content)
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.ink)
                    .lineSpacing(3)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .onTapGesture(count: 2) { startInlineEdit() }
            }
        }
    }

    /// T-13 인라인 편집기. 코드 계열은 줄번호+모노+다크 박스, 텍스트는 시스템 폰트.
    private func inlineEditor(mono: Bool) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            BlockTextEditor(
                text: $draftContent,
                font: mono
                    ? .monospacedSystemFont(ofSize: 13, weight: .regular)
                    : .systemFont(ofSize: 14),
                textColor: NSColor(mono ? Theme.codeForeground : Theme.ink),
                backgroundColor: .clear,
                showLineNumbers: mono,
                onSave: saveInlineEdit,
                onCancel: { isInlineEditing = false }
            )
            .frame(minHeight: 140, maxHeight: 420)
            HStack(spacing: 8) {
                Text("⌘Enter 저장 · esc 취소 · 더블클릭으로 편집 시작")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.muted)
                Spacer(minLength: 0)
                CapsuleButton(title: "취소") { isInlineEditing = false }
                CapsuleButton(title: "저장", style: .primary, action: saveInlineEdit)
            }
        }
        .padding(mono ? 12 : 0)
        .background(mono ? Theme.codeBackground : .clear, in: RoundedRectangle(cornerRadius: 10))
    }

    /// 텍스트·코드 계열만 인라인 편집 (구조형 블록은 시트 유지).
    private var canInlineEdit: Bool {
        [.text, .markdown, .code, .shell].contains(block.type)
    }

    private func startInlineEdit() {
        guard canInlineEdit, !isInlineEditing else { return }
        draftContent = block.content
        isInlineEditing = true
    }

    private func saveInlineEdit() {
        var updated = block
        updated.content = draftContent
        updated.updatedAt = Date()
        store.updateBlock(updated)
        isInlineEditing = false
        DebugLogger.feature("인라인 편집 저장: \(block.title)")
    }

    private var codeBody: some View {
        Text(block.content)
            .font(Theme.monoBody)
            .foregroundStyle(Theme.codeForeground)
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.codeBackground, in: RoundedRectangle(cornerRadius: 10))
            .textSelection(.enabled)
    }

    private var webBody: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 12) {
                webThumbnail
                VStack(alignment: .leading, spacing: 4) {
                    Text(block.content.isEmpty ? (block.title) : block.content)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Theme.ink)
                        .lineLimit(2)
                    Text(subtitleText)
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.muted)
                        .lineLimit(1)
                    if let date = block.savedAt {
                        Text("저장 \(Self.savedDateFormatter.string(from: date))")
                            .font(.system(size: 11))
                            .foregroundStyle(Theme.muted)
                    }
                    if block.type == .webArchive {
                        let saved = WebArchiveStore.hasOfflineFiles(for: block)
                        Text(saved ? "오프라인 저장됨" : "미저장 — 주소·메모만 보관 중")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(saved ? Theme.webBlue : Theme.muted)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 2)
                            .background((saved ? Theme.webBlueSoft : Theme.tagBackground), in: Capsule())
                    }
                }
                Spacer(minLength: 0)
            }
            // URL 행은 항상 표시: 없으면 안내 문구 (빈 카드처럼 보이는 문제 해소)
            if let urlString = block.url, !urlString.isEmpty, let url = URL(string: urlString) {
                Button { open(url) } label: {
                    Text(urlString)
                        .font(Theme.monoCaption)
                        .foregroundStyle(Theme.webBlue)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                .buttonStyle(.plain)
                .help("브라우저로 열기")
            } else {
                Text("URL 없음 — 편집에서 URL을 추가하면 열기·검색이 됩니다")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.muted)
            }
            // T-09 오프라인 저장·보기 (웹 아카이브만)
            if block.type == .webArchive {
                archiveActions
            }
        }
        .sheet(isPresented: $showingOffline) {
            if let url = offlineFileURL {
                OfflineWebView(fileURL: url)
                    .frame(minWidth: 800, minHeight: 600)
            }
        }
    }

    /// 웹 아카이브 저장·보기 행.
    private var archiveActions: some View {
        HStack(spacing: 8) {
            if isSavingArchive {
                ProgressView()
                    .controlSize(.small)
                Text("저장 중… (최대 30초)")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.muted)
            } else {
                if WebArchiveStore.hasOfflineFiles(for: block) {
                    CapsuleButton(title: "오프라인 보기", action: { showingOffline = true })
                    CapsuleButton(title: "다시 저장", action: saveOfflineArchive)
                } else {
                    CapsuleButton(title: "아카이브 저장", style: .primary, action: saveOfflineArchive)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.top, 4)
    }

    /// 실파일 URL (아카이브 우선, 없으면 PDF).
    private var offlineFileURL: URL? {
        if let name = block.archiveFile,
           let url = WebArchiveStore.fileURL(kind: WebArchiveStore.archiveKind, name: name) {
            return url
        }
        if let name = block.pdfFile,
           let url = WebArchiveStore.fileURL(kind: WebArchiveStore.pdfKind, name: name) {
            return url
        }
        return nil
    }

    /// WKWebView로 읽어 .webarchive + PDF를 저장한다. 기존 파일은 새 저장 성공 후 정리.
    private func saveOfflineArchive() {
        guard let urlString = block.url, !urlString.isEmpty, let url = URL(string: urlString) else {
            appState.notify("URL이 없어 저장할 수 없습니다")
            return
        }
        guard !isSavingArchive else { return }
        isSavingArchive = true
        Task {
            defer { isSavingArchive = false }
            do {
                let captured = try await WebCaptureService.capture(url: url)
                var updated = block
                let oldArchive = block.archiveFile
                let oldPDF = block.pdfFile
                if let name = WebArchiveStore.save(captured.webarchive, ext: "webarchive") {
                    updated.archiveFile = name
                }
                if let name = WebArchiveStore.save(captured.pdf, ext: "pdf") {
                    updated.pdfFile = name
                }
                guard updated.archiveFile != nil || updated.pdfFile != nil else {
                    throw CapsuleError.store(code: ErrorCode.webArchive, message: "파일 기록 실패")
                }
                if let old = oldArchive, old != updated.archiveFile {
                    WebArchiveStore.remove(kind: WebArchiveStore.archiveKind, name: old)
                }
                if let old = oldPDF, old != updated.pdfFile {
                    WebArchiveStore.remove(kind: WebArchiveStore.pdfKind, name: old)
                }
                updated.savedAt = Date()
                updated.updatedAt = Date()
                store.updateBlock(updated)
                // [HARD] 값 자체를 로그에 남기지 않는다. 제목만 기록.
                DebugLogger.feature("아카이브 저장: \(block.title)")
                appState.notify("오프라인 저장됨")
            } catch {
                DebugLogger.error(code: ErrorCode.webArchive, "아카이브 저장 실패: \(block.title)")
                appState.notify("오프라인 저장 실패 — 네트워크·URL 확인 필요")
            }
        }
    }

    private var webThumbnail: some View {
        RoundedRectangle(cornerRadius: 10)
            .fill(
                LinearGradient(
                    colors: [Theme.tileTop, Theme.tileBottom],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .frame(width: 120, height: 80)
            .overlay(
                Image(systemName: "globe")
                    .font(.system(size: 20, weight: .light))
                    .foregroundStyle(Theme.tileText)
            )
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Theme.line, lineWidth: 1))
    }

    private var subtitleText: String {
        var parts: [String] = []
        if let site = block.siteName, !site.isEmpty {
            parts.append(site)
        } else if let host = block.webHost {
            // 사이트명이 비면 URL 호스트를 대신 표시
            parts.append(host)
        }
        parts.append(block.type == .webArchive ? "아카이브" : "링크 저장")
        return parts.joined(separator: " • ")
    }

    @ViewBuilder
    private var imageBody: some View {
        if block.imageNames.isEmpty {
            Text(block.type == .image ? "첨부된 이미지가 없습니다. 편집에서 추가하세요." : "첨부된 파일이 없습니다. 편집에서 추가하세요.")
                .font(.system(size: 13))
                .foregroundStyle(Theme.muted)
        } else {
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                ForEach(block.imageNames, id: \.self) { name in
                    cardThumbnail(for: name)
                        .help("Finder에서 이미지·파일을 끌어다 놓으면 이 블록에 추가됩니다")
                }
            }
        }
    }

    /// 카드 썸네일. 실파일이 있으면 미리보기, 없으면 파일명 타일.
    @ViewBuilder
    private func cardThumbnail(for name: String) -> some View {
        if block.type == .image,
           let url = AttachmentStore.fileURL(kind: AttachmentStore.imagesKind, name: name),
           FileManager.default.fileExists(atPath: url.path),
           let nsImage = NSImage(contentsOf: url) {
            Image(nsImage: nsImage)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(height: 120)
                .clipped()
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Theme.line, lineWidth: 1))
        } else {
            RoundedRectangle(cornerRadius: 10)
                .fill(
                    LinearGradient(
                        colors: [Theme.tileTop, Theme.tileBottom],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(height: 120)
                .overlay(
                    VStack(spacing: 6) {
                        Image(systemName: block.type == .image ? "photo" : "doc")
                            .font(.system(size: 18, weight: .light))
                        Text(name)
                            .font(.system(size: 11))
                            .lineLimit(2)
                    }
                    .foregroundStyle(Theme.tileText)
                    .padding(8)
                )
                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Theme.line, lineWidth: 1))
                .help("파일 위치: Application Support/CapsuleStash/\(block.type == .image ? "images" : "files")/\(name)")
        }
    }

    private var credentialBody: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let credential = block.credential {
                credentialRow(
                    label: "홈페이지",
                    value: credential.homepage,
                    isSecret: false,
                    systemImage: "arrow.up.forward.app",
                    tooltip: "브라우저로 열기"
                ) {
                    if let url = URL(string: credential.homepage) {
                        open(url)
                    } else {
                        DebugLogger.error(code: ErrorCode.webOpen, "URL 형식 오류")
                        appState.notify("열 수 없는 URL입니다")
                    }
                }

                Divider().overlay(Theme.line)
                credentialRow(
                    label: "아이디",
                    value: credential.username,
                    isSecret: false,
                    systemImage: "doc.on.doc",
                    tooltip: "아이디 복사",
                    primary: true
                ) {
                    if ClipboardService.copy(credential.username, label: "\(block.title) 아이디") {
                        appState.notifyCopy("\(block.title) 아이디")
                    }
                }

                Divider().overlay(Theme.line)
                secretRow(
                    label: "Secret 1",
                    value: credential.password,
                    copyLabel: "\(block.title) Secret 1"
                )

                // 두 번째 시크릿은 값이 있을 때만 표시 (빈 행으로 산만해지지 않게)
                if !credential.secondSecret.isEmpty {
                    Divider().overlay(Theme.line)
                    secretRow(
                        label: "Secret 2",
                        value: credential.secondSecret,
                        copyLabel: "\(block.title) Secret 2"
                    )
                }
            } else {
                Text("저장된 계정 정보가 없습니다. 편집에서 입력하면 시크릿은 Keychain에 보관됩니다.")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.muted)
            }
        }
    }

    /// Vault 잠금과 연동된 시크릿 행. 잠금 상태면 마스킹 표시 + 복사 차단.
    private func secretRow(label: String, value: String, copyLabel: String) -> some View {
        credentialRow(
            label: label,
            value: store.isVaultUnlocked ? value : "••••••••••",
            isSecret: true,
            systemImage: "doc.on.doc",
            tooltip: "\(label) 복사",
            primary: true
        ) {
            guard store.isVaultUnlocked else {
                DebugLogger.error(code: ErrorCode.vaultLocked, "\(block.title) 비밀값 접근 시도")
                appState.notify("Vault를 먼저 해제하세요")
                return
            }
            if ClipboardService.copy(value, label: copyLabel, isSecret: true) {
                appState.notifyCopy(copyLabel, isSecret: true)
            }
        }
    }

    private func credentialRow(label: String, value: String, isSecret: Bool,                               systemImage: String, tooltip: String, primary: Bool = false,
                               action: @escaping () -> Void) -> some View {
        HStack(spacing: 10) {
            LText(key: label)
                .font(.system(size: 13))
                .foregroundStyle(Theme.muted)
                .frame(width: 72, alignment: .leading)
            Text(value.isEmpty ? "—" : value)
                .font(isSecret ? Theme.monoBody : .system(size: 14))
                .foregroundStyle(Theme.ink)
                .lineLimit(1)
            Spacer(minLength: 8)
            CapsuleIconButton(systemImage: systemImage, tooltip: tooltip, style: primary ? .primary : .plain, action: action)
        }
        .padding(.vertical, 8)
    }

    // MARK: - 동작

    /// 목업 표기 `2026-09-28` 형식. 시스템 로케일과 무관하게 고정한다.
    private static let savedDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ko_KR")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    private var vaultLabel: String {
        store.isVaultUnlocked ? "● Vault 열림" : "●●● 잠금됨"
    }

    /// 카드에 파일을 끌어다 놓으면 이미지/파일 블록에 첨부한다.
    /// 다른 타입 블록에는 받지 않는다.
    private func handleDrop(_ providers: [NSItemProvider]) {
        guard block.type == .image || block.type == .file else {
            appState.notify("이미지·파일 블록에만 끌어다 놓을 수 있습니다")
            return
        }
        AttachmentStore.urls(from: providers) { urls in
            let kind = self.block.type == .image ? AttachmentStore.imagesKind : AttachmentStore.filesKind
            let accepted: [URL]
            if self.block.type == .image {
                accepted = urls.filter { AttachmentStore.isImageFile($0) }
                guard !accepted.isEmpty else {
                    self.appState.notify("이미지 파일을 끌어다 놓으세요")
                    return
                }
            } else {
                accepted = urls.filter { $0.isFileURL }
            }
            guard !accepted.isEmpty else { return }
            let names = AttachmentStore.importFiles(from: accepted, kind: kind)
            guard !names.isEmpty else { return }
            var updated = self.block
            updated.imageNames += names
            updated.updatedAt = Date()
            self.store.updateBlock(updated)
            self.appState.notify("\(names.count)개 \(self.block.type.displayName) 추가됨")
        }
    }

    private func copyBlockContent() {
        let text = block.copyPayload(includeSecrets: store.isVaultUnlocked)
        guard !text.isEmpty else {
            appState.notify("복사할 내용이 없습니다")
            return
        }
        if ClipboardService.copy(text, label: block.title) {
            appState.notifyCopy(block.title)
        }
    }

    /// 이미지/파일 블록의 예상 보관 경로를 복사한다 (원본 뷰어는 T-12).
    private func copyImagePaths() {
        guard !block.imageNames.isEmpty else {
            appState.notify("첨부된 파일이 없습니다")
            return
        }
        let base = PersistenceStore.attachmentsURL(kind: block.type == .image ? "images" : "files").path
        let text = block.imageNames.map { base + "/" + $0 }.joined(separator: "\n")
        if ClipboardService.copy(text, label: "\(block.title) 경로") {
            appState.notifyCopy("\(block.title) 경로")
        }
    }

    private func copyURL() {
        guard let url = block.url, !url.isEmpty else {
            appState.notify("저장된 URL이 없습니다")
            return
        }
        if ClipboardService.copy(url, label: "\(block.title) URL") {
            appState.notifyCopy("URL")
        }
    }

    private func open(_ url: URL) {
        DebugLogger.feature("외부 링크 열기: \(url.host() ?? url.absoluteString)")
        NSWorkspace.shared.open(url)
    }

    private func toggleProjectFavorite() {
        if let project = store.selectedProject { store.toggleFavorite(project) }
    }
}

// MARK: - 점선 구분선 (목업 `border-bottom: 1px dashed`)

struct DashedLine: Shape {
    var color: Color = Theme.line
    var pattern: [CGFloat] = [4, 3]

    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: 0, y: rect.height / 2))
        var x: CGFloat = 0
        var index = 0
        while x < rect.width {
            let segment = pattern[index % pattern.count]
            path.addLine(to: CGPoint(x: min(x + segment, rect.width), y: rect.height / 2))
            x += segment
            index += 1
        }
        return path
    }
}