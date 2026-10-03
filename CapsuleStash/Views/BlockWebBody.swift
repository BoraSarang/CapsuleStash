import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// 웹 아카이브 블록 본문 (썸네일·URL 행·오프라인 저장/보기, T-09).
struct BlockWebBody: View {
    let block: Block

    @EnvironmentObject private var store: DataStore
    @EnvironmentObject private var appState: AppState
    @State private var isSavingArchive = false
    @State private var showingOffline = false
    @State private var viewingPDF = false

    /// 목업 표기 `2026-09-28` 형식. 시스템 로케일과 무관하게 고정한다.
    private static let savedDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ko_KR")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    var body: some View {
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
                        Text(L10n.format("저장 %@", Self.savedDateFormatter.string(from: date)))
                            .font(.system(size: 11))
                            .foregroundStyle(Theme.muted)
                    }
                    // 웹은 단일 타입으로 통합됨 (T-28, 레거시 webLink는 로드 시 변환)
                    let saved = WebArchiveStore.hasOfflineFiles(for: block)
                    Text(saved ? LocalizedStringKey("오프라인 저장됨") : LocalizedStringKey("미저장 — 주소·메모만 보관 중"))
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(saved ? Theme.webBlue : Theme.muted)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background((saved ? Theme.webBlueSoft : Theme.tagBackground), in: Capsule())
                }
                Spacer(minLength: 0)
            }
            // URL 행은 항상 표시: 없으면 안내 문구 (빈 카드처럼 보이는 문제 해소)
            if let urlString = block.url, !urlString.isEmpty, let url = URL(string: urlString) {
                Button { appState.openExternal(url) } label: {
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
            // T-09 오프라인 저장·보기
            archiveActions
        }
        .sheet(isPresented: $showingOffline) {
            if let url = offlineFileURL(pdf: viewingPDF) {
                OfflineWebView(fileURL: url)
                    .frame(minWidth: 800, minHeight: 600)
            }
        }
    }

    /// 웹 아카이브 저장·보기 행. 아카이브와 PDF가 둘 다 있으면 각각 본다.
    private var archiveActions: some View {
        HStack(spacing: 8) {
            if isSavingArchive {
                ProgressView()
                    .controlSize(.small)
                Text("저장 중… (최대 30초)")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.muted)
            } else {
                let hasArchive = block.archiveFile != nil
                    && WebArchiveStore.fileURL(kind: WebArchiveStore.archiveKind, name: block.archiveFile!) != nil
                let hasPDF = block.pdfFile != nil
                    && WebArchiveStore.fileURL(kind: WebArchiveStore.pdfKind, name: block.pdfFile!) != nil
                if hasArchive || hasPDF {
                    if hasArchive {
                        CapsuleButton(title: "아카이브 보기") {
                            viewingPDF = false
                            showingOffline = true
                        }
                    }
                    if hasPDF {
                        CapsuleButton(title: "PDF 보기") {
                            viewingPDF = true
                            showingOffline = true
                        }
                        CapsuleButton(title: "PDF 내보내기", action: exportPDF)
                    }
                    CapsuleButton(title: "다시 저장", action: saveOfflineArchive)
                } else {
                    CapsuleButton(title: "아카이브 저장", style: .primary, action: saveOfflineArchive)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.top, 4)
    }

    /// 실파일 URL. 아카이브 우선이던 것을 보기 버튼에 따라 고른다.
    private func offlineFileURL(pdf: Bool) -> URL? {
        if !pdf,
           let name = block.archiveFile,
           let url = WebArchiveStore.fileURL(kind: WebArchiveStore.archiveKind, name: name) {
            return url
        }
        if let name = block.pdfFile,
           let url = WebArchiveStore.fileURL(kind: WebArchiveStore.pdfKind, name: name) {
            return url
        }
        // PDF가 없으면 아카이브로 폴백
        if let name = block.archiveFile,
           let url = WebArchiveStore.fileURL(kind: WebArchiveStore.archiveKind, name: name) {
            return url
        }
        return nil
    }

    /// 저장된 PDF를 Finder 위치에 복사한다 (다운로드).
    private func exportPDF() {
        guard let name = block.pdfFile,
              let src = WebArchiveStore.fileURL(kind: WebArchiveStore.pdfKind, name: name) else {
            appState.notify("내보낼 PDF가 없습니다")
            return
        }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "\(block.title.isEmpty ? "archive" : block.title).pdf"
        panel.allowedContentTypes = [.pdf]
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let dest = panel.url else { return }
        do {
            if FileManager.default.fileExists(atPath: dest.path) {
                try FileManager.default.removeItem(at: dest)
            }
            try FileManager.default.copyItem(at: src, to: dest)
            // [HARD] paths are user data — log file name only, never contents.
            DebugLogger.feature("PDF 내보내기: \(dest.lastPathComponent)")
            appState.notify("PDF 내보냄")
        } catch {
            DebugLogger.error(code: ErrorCode.storeSave, "PDF 내보내기 실패")
            appState.notify("PDF 내보내기 실패")
        }
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
                let oldThumbnail = block.thumbnailFile
                if let name = WebArchiveStore.save(captured.webarchive, ext: "webarchive") {
                    updated.archiveFile = name
                }
                if let name = WebArchiveStore.save(captured.pdf, ext: "pdf") {
                    updated.pdfFile = name
                }
                if let data = captured.thumbnail,
                   let name = WebArchiveStore.save(data, ext: "png", kind: WebArchiveStore.thumbnailKind) {
                    updated.thumbnailFile = name
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
                if let old = oldThumbnail, old != updated.thumbnailFile {
                    WebArchiveStore.remove(kind: WebArchiveStore.thumbnailKind, name: old)
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

    /// 웹 썸네일. 저장 시점 스크린샷이 있으면 실화면, 없으면 기본 타일 (T-28).
    private var webThumbnail: some View {
        Group {
            if let name = block.thumbnailFile,
               let url = WebArchiveStore.fileURL(kind: WebArchiveStore.thumbnailKind, name: name),
               let nsImage = NSImage(contentsOf: url) {
                Image(nsImage: nsImage)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                FallbackTile {
                    Image(systemName: "globe")
                        .font(.system(size: 20, weight: .light))
                        .foregroundStyle(Theme.tileText)
                }
            }
        }
        .frame(width: 120, height: 80)
        .clipShape(RoundedRectangle(cornerRadius: 10))
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
        parts.append("아카이브")
        return parts.joined(separator: " • ")
    }
}
