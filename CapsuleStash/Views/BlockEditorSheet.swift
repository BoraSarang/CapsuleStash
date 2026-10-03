import AppKit
import SwiftUI

/// 블록 편집 시트. 목업에는 편집 UI가 없으나 우측 콘텐츠 수정 수단으로 MVP에 추가했다.
/// (docs/DESIGN.md §4). 입력 컨트롤 색상은 토큰을 사용해 외관 모드를 따라간다.
struct BlockEditorSheet: View {
    @EnvironmentObject private var store: DataStore
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss

    @FocusState private var titleFocused: Bool

    let original: Block

    /// 생성 모드 여부. true면 저장 시 `insertBlock`, false면 `updateBlock`.
    let isCreating: Bool
    private let creationType: BlockType

    @State private var title: String
    @State private var content: String
    @State private var language: String
    @State private var urlText: String
    @State private var siteName: String
    @State private var imageNames: [String]
    @State private var homepage: String
    @State private var username: String
    @State private var password: String
    @State private var secondSecret: String
    @State private var revealPassword = false
    @State private var revealSecondSecret = false
    /// 이번 시트에서 새로 가져온 첨부. 취소 시 삭제해 고아 파일을 남기지 않는다.
    @State private var sessionAdded: [String] = []
    @State private var isDropTargeted = false

    /// 기존 블록 편집
    init(block: Block) {
        self.original = block
        self.isCreating = false
        self.creationType = block.type
        _title = State(initialValue: block.title)
        _content = State(initialValue: block.content)
        _language = State(initialValue: block.language ?? "")
        _urlText = State(initialValue: block.url ?? "")
        _siteName = State(initialValue: block.siteName ?? "")
        _imageNames = State(initialValue: block.imageNames)
        _homepage = State(initialValue: block.credential?.homepage ?? "")
        _username = State(initialValue: block.credential?.username ?? "")
        _password = State(initialValue: block.credential?.password ?? "")
        _secondSecret = State(initialValue: block.credential?.secondSecret ?? "")
    }

    /// 새 블록 추가 (입력 우선 — 저장할 때만 생성된다)
    init(create request: BlockCreationRequest) {
        let template = Block(projectId: request.projectId, type: request.type, title: "")
        self.original = template
        self.isCreating = true
        self.creationType = request.type
        _title = State(initialValue: "")
        _content = State(initialValue: "")
        _language = State(initialValue: "")
        _urlText = State(initialValue: "")
        _siteName = State(initialValue: "")
        _imageNames = State(initialValue: [])
        _homepage = State(initialValue: "")
        _username = State(initialValue: "")
        _password = State(initialValue: "")
        _secondSecret = State(initialValue: "")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // 고정 헤더
            HStack(spacing: 10) {
                TypeBadge(text: headerBadgeText, type: original.type)
                Text(isCreating ? L10n.format("%@ 블록 추가", L10n.string(creationType.displayName)) : L10n.string("블록 편집"))
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.ink)
                Spacer(minLength: 8)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)

            if isCreating {
                Text(L10n.string(creationType.purposeHint))
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.muted)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 10)
            }

            DashedLine(color: Theme.line, pattern: [5, 4]).frame(height: 1)

            // 고정 제목 (스크롤되지 않음)
            field("제목") {
                TextField("블록 제목", text: $title)
                    .textFieldStyle(.roundedBorder)
                    .focused($titleFocused)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)

            DashedLine(color: Theme.line, pattern: [5, 4]).frame(height: 1)

            // 중간만 스크롤
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    typeFields

                    if original.type == .credential {
                        HStack(spacing: 6) {
                            Image(systemName: "info.circle")
                            Text("시크릿은 이 기기의 Keychain에 암호화 보관됩니다. 홈페이지·아이디만 일반 저장소에 기록됩니다.")
                        }
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.muted)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
            }

            // 고정 푸터
            DashedLine(color: Theme.line, pattern: [5, 4]).frame(height: 1)
            HStack(spacing: 10) {
                Spacer(minLength: 0)
                CapsuleButton(title: "취소", action: cancel)
                CapsuleButton(title: isCreating ? "추가" : "저장", style: .primary, action: save)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
        }
        .frame(width: 560, height: 600)
        .background(Theme.paper)
        // T-37 시트는 창 환경을 못 물려받을 수 있어 로케일 명시
        .environment(\.locale, AppLanguage.effectiveLocale)
        .onAppear { titleFocused = true }
    }

    // MARK: - 타입별 필드

    @ViewBuilder
    private var typeFields: some View {
        switch original.type {
        case .text, .markdown:
            field("내용") {
                editor(text: $content, mono: false, minHeight: 160)
            }
        case .code, .shell:
            field("언어 (예: swift, bash)") {
                TextField("swift", text: $language)
                    .textFieldStyle(.roundedBorder)
                    .font(Theme.monoBody)
            }
            field("코드") {
                editor(text: $content, mono: true, minHeight: 200)
            }
        case .webLink, .webArchive:
            let isArchive = original.type == .webArchive
            Text(isArchive
                ? LocalizedStringKey("페이지 본문을 오프라인으로 보관합니다. 실파일 저장은 카드의 ‘아카이브 저장’으로, 보기는 ‘오프라인 보기’로 합니다.")
                : LocalizedStringKey("자주 보는 페이지의 주소와 메모입니다. 열기로 브라우저에서 바로 엽니다."))
                .font(.system(size: 12))
                .foregroundStyle(Theme.muted)
            if isArchive, WebArchiveStore.hasOfflineFiles(for: original) {
                Text("오프라인 파일 있음 (.webarchive/PDF) — 카드에서 보거나 다시 저장할 수 있습니다.")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.muted)
            }
            field("URL") {
                TextField("https://…", text: $urlText)
                    .textFieldStyle(.roundedBorder)
                    .font(Theme.monoBody)
            }
            field("사이트명 (비우면 주소에서 자동 표시)") {
                TextField("example.com", text: $siteName)
                    .textFieldStyle(.roundedBorder)
            }
            field("설명") {
                TextField("페이지 설명", text: $content)
                    .textFieldStyle(.roundedBorder)
            }
        case .image, .file:
            let isImage = original.type == .image
            field(isImage ? "이미지" : "파일") {
                VStack(alignment: .leading, spacing: 10) {
                    if imageNames.isEmpty {
                        Text(isImage
                            ? LocalizedStringKey("아직 첨부된 이미지가 없습니다.")
                            : LocalizedStringKey("아직 첨부된 파일이 없습니다."))
                            .font(.system(size: 13))
                            .foregroundStyle(Theme.muted)
                    } else {
                        Group {
                            if isImage {
                                Text(L10n.format("이미지 %lld개", imageNames.count))
                            } else {
                                Text(L10n.format("파일 %lld개", imageNames.count))
                            }
                        }
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.muted)
                        LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                            ForEach(imageNames, id: \.self) { name in
                                ZStack(alignment: .topTrailing) {
                                    attachmentThumbnail(for: name, isImage: isImage)
                                    Button {
                                        imageNames.removeAll { $0 == name }
                                    } label: {
                                        Image(systemName: "xmark.circle.fill")
                                            .font(.system(size: 18))
                                            .foregroundStyle(Theme.ink)
                                            .background(Theme.card, in: Circle())
                                    }
                                    .buttonStyle(.plain)
                                    .padding(6)
                                    .help("제거")
                                }
                            }
                        }
                    }
                    HStack(spacing: 10) {
                        CapsuleIconButton(
                            systemImage: "plus",
                            tooltip: isImage ? "이미지 추가" : "파일 추가"
                        ) {
                            pickFiles()
                        }
                        Text("Finder에서 끌어다 놓을 수도 있습니다")
                            .font(.system(size: 12))
                            .foregroundStyle(Theme.muted)
                    }
                    .padding(.top, 4)
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(isDropTargeted ? Theme.accentSoft : Color.clear, in: RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(isDropTargeted ? Theme.accent : Color.clear, lineWidth: 2))
                .onDrop(of: [.fileURL], isTargeted: $isDropTargeted) { providers in
                    dropFiles(providers, imageOnly: isImage)
                    return true
                }
            }
        case .credential:
            Text("Secret 1·2는 Vault 해제 후에만 보이고 복사됩니다. Naver API처럼 키가 2개면 둘에 나눠 입력하세요.")
                .font(.system(size: 12))
                .foregroundStyle(Theme.muted)
            field("홈페이지 (선택)") {
                TextField("https://… (없으면 비워두기)", text: $homepage)
                    .textFieldStyle(.roundedBorder)
                    .font(Theme.monoBody)
            }
            field("아이디 / 키 이름") {
                TextField("아이디 또는 키 이름 (예: OPENAI_API_KEY)", text: $username)
                    .textFieldStyle(.roundedBorder)
            }
            field("Secret 1 (패스워드·API Key·Client ID)") {
                HStack(spacing: 8) {
                    Group {
                        if revealPassword {
                            TextField("sk-… 또는 패스워드", text: $password)
                        } else {
                            SecureField("sk-… 또는 패스워드", text: $password)
                        }
                    }
                    .textFieldStyle(.roundedBorder)
                    .font(Theme.monoBody)
                    Button {
                        revealPassword.toggle()
                    } label: {
                        Image(systemName: revealPassword ? "eye.slash" : "eye")
                            .foregroundStyle(Theme.muted)
                    }
                    .buttonStyle(.plain)
                    .help(Text(revealPassword ? LocalizedStringKey("가리기") : LocalizedStringKey("보기")))
                }
            }
            field("Secret 2 (선택, 예: Client Secret)") {
                HStack(spacing: 8) {
                    Group {
                        if revealSecondSecret {
                            TextField("두 번째 시크릿 (없으면 비움)", text: $secondSecret)
                        } else {
                            SecureField("두 번째 시크릿 (없으면 비움)", text: $secondSecret)
                        }
                    }
                    .textFieldStyle(.roundedBorder)
                    .font(Theme.monoBody)
                    Button {
                        revealSecondSecret.toggle()
                    } label: {
                        Image(systemName: revealSecondSecret ? "eye.slash" : "eye")
                            .foregroundStyle(Theme.muted)
                    }
                    .buttonStyle(.plain)
                    .help(Text(revealSecondSecret ? LocalizedStringKey("가리기") : LocalizedStringKey("보기")))
                }
            }
        }
    }

    // MARK: - 공용 필드

    private func field<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            LText(key: label)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Theme.muted)
            content()
        }
    }

    /// 멀티라인 에디터. 배경·전경 모두 토큰이라 외관 모드를 따라간다.
    private func editor(text: Binding<String>, mono: Bool, minHeight: CGFloat) -> some View {
        TextEditor(text: text)
            .font(mono ? Theme.monoBody : .system(size: 14))
            .foregroundStyle(Theme.ink)
            .scrollContentBackground(.hidden)
            .padding(8)
            .frame(minHeight: minHeight, alignment: .topLeading)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Theme.line, lineWidth: 1))
    }

    // MARK: - 저장

    private var attachmentKind: String {
        original.type == .image ? AttachmentStore.imagesKind : AttachmentStore.filesKind
    }

    private var headerBadgeText: String {
        if isCreating { return original.type.label }
        return original.badgeLabel
    }

    /// 취소: 이번 시트에서 가져온 첨부를 삭제하고, 아무것도 만들지 않는다.
    private func cancel() {
        for name in sessionAdded {
            AttachmentStore.remove(kind: attachmentKind, name: name)
        }
        sessionAdded = []
        dismiss()
    }

    private func pickFiles() {
        let isImage = original.type == .image
        let urls = AttachmentStore.runOpenPanel(
            imageOnly: isImage,
            message: isImage ? "블록에 넣을 이미지를 선택하세요" : "블록에 넣을 파일을 선택하세요"
        )
        guard !urls.isEmpty else { return }
        let names = AttachmentStore.importFiles(from: urls, kind: attachmentKind)
        imageNames += names
        sessionAdded += names
    }

    /// T-34 편집 시트에 파일 드롭 → 바로 첨부 (취소 시 sessionAdded로 정리됨).
    private func dropFiles(_ providers: [NSItemProvider], imageOnly: Bool) {
        AttachmentStore.urls(from: providers) { urls in
            var accepted = urls.filter { $0.isFileURL }
            if imageOnly {
                accepted = accepted.filter { AttachmentStore.isImageFile($0) }
            }
            guard !accepted.isEmpty else { return }
            let names = AttachmentStore.importFiles(from: accepted, kind: attachmentKind)
            guard !names.isEmpty else { return }
            imageNames += names
            sessionAdded += names
        }
    }

    @ViewBuilder
    private func attachmentThumbnail(for name: String, isImage: Bool) -> some View {
        if isImage,
           let url = AttachmentStore.fileURL(kind: AttachmentStore.imagesKind, name: name),
           FileManager.default.fileExists(atPath: url.path),
           let nsImage = NSImage(contentsOf: url) {
            Image(nsImage: nsImage)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(height: 110)
                .clipped()
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Theme.line, lineWidth: 1))
        } else {
            RoundedRectangle(cornerRadius: 10)
                .fill(Theme.card)
                .frame(height: 110)
                .overlay(
                    VStack(spacing: 6) {
                        Image(systemName: isImage ? "photo" : "doc")
                            .font(.system(size: 18, weight: .light))
                        Text(name)
                            .font(.system(size: 11))
                            .lineLimit(2)
                    }
                    .foregroundStyle(Theme.tileText)
                    .padding(8)
                )
                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Theme.line, lineWidth: 1))
        }
    }

    private func save() {
        // 생성 시 제목이 비면 내용에서 끌어온다 (빈 블록 방지)
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if !isCreating {
            guard !trimmedTitle.isEmpty else {
                appState.notify("제목을 입력하세요")
                return
            }
        }

        var updated = original
        updated.updatedAt = Date()

        switch original.type {
        case .text, .markdown:
            updated.content = content
        case .code, .shell:
            updated.content = content
            let lang = language.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            updated.language = lang.isEmpty ? nil : lang
        case .webLink, .webArchive:
            updated.content = content
            let url = urlText.trimmingCharacters(in: .whitespacesAndNewlines)
            updated.url = url.isEmpty ? nil : url
            let site = siteName.trimmingCharacters(in: .whitespacesAndNewlines)
            updated.siteName = site.isEmpty ? nil : site
        case .image, .file:
            updated.imageNames = imageNames
            // 시트에서 제거된 첨부 파일도 함께 삭제 (고아 파일 방지)
            let removed = Set(original.imageNames).subtracting(imageNames)
            for name in removed {
                AttachmentStore.remove(kind: attachmentKind, name: name)
            }
            sessionAdded = []
        case .credential:
            // [HARD] 값 자체를 로그에 남기지 않는다. 제목만 기록.
            updated.credential = Credential(
                homepage: homepage.trimmingCharacters(in: .whitespacesAndNewlines),
                username: username.trimmingCharacters(in: .whitespacesAndNewlines),
                password: password,
                secondSecret: secondSecret
            )
        }

        // 생성 시 제목이 비면 필드를 채운 뒤 내용에서 끌어온다 (빈 블록 방지)
        if trimmedTitle.isEmpty {
            updated.title = updated.suggestedTitle()
        } else {
            updated.title = trimmedTitle
        }

        if isCreating {
            store.insertBlock(updated)
            // [HARD] 값 자체를 로그에 남기지 않는다. 제목만 기록.
            DebugLogger.feature("블록 추가: \(updated.title) (\(original.type.displayName))")
            appState.notify(L10n.format("%@ 블록 추가됨", L10n.string(original.type.displayName)))
        } else {
            store.updateBlock(updated)
            DebugLogger.feature("블록 편집 저장: \(updated.title)")
            appState.notify("저장됨")
        }
        dismiss()
    }
}
