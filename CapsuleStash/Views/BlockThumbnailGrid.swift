import AppKit
import SwiftUI

/// 이미지·파일 블록 썸네일 그리드 (T-12).
/// T-42 썸네일 크기를 행에 고정. fill 원본의 이상 크기가 히트 영역까지
/// 커지면 펼친 이미지 카드의 헤더 버튼을 덮는다 (위로 오버플로).
struct BlockThumbnailGrid: View {
    static let thumbnailHeight: CGFloat = 120

    let block: Block

    @EnvironmentObject private var appState: AppState

    /// 보관 중인 실파일 URL 목록 (미리보기·복사용).
    static func existingURLs(for block: Block) -> [URL] {
        let kind = block.type == .image ? AttachmentStore.imagesKind : AttachmentStore.filesKind
        return block.imageNames.compactMap { name in
            guard let url = AttachmentStore.fileURL(kind: kind, name: name),
                  FileManager.default.fileExists(atPath: url.path) else { return nil }
            return url
        }
    }

    var body: some View {
        if block.imageNames.isEmpty {
            Text(block.type == .image
                ? LocalizedStringKey("첨부된 이미지가 없습니다. 편집에서 추가하세요.")
                : LocalizedStringKey("첨부된 파일이 없습니다. 편집에서 추가하세요."))
                .font(.system(size: 13))
                .foregroundStyle(Theme.muted)
        } else {
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                ForEach(Array(block.imageNames.enumerated()), id: \.element) { index, name in
                    cardThumbnail(for: name, index: index)
                        .help("더블클릭으로 보기 · 파일 끌어다 놓으면 이 블록에 추가됩니다")
                }
            }
        }
    }

    /// 카드 썸네일. 실파일이 있으면 미리보기, 없으면 파일명 타일.
    /// 더블클릭: 이미지 → QuickLook, 파일 → 기본 앱으로 열기 (T-32).
    @ViewBuilder
    private func cardThumbnail(for name: String, index: Int) -> some View {
        if block.type == .image,
           let url = AttachmentStore.fileURL(kind: AttachmentStore.imagesKind, name: name),
           FileManager.default.fileExists(atPath: url.path),
           let nsImage = NSImage(contentsOf: url) {
            GeometryReader { geo in
                Image(nsImage: nsImage)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: geo.size.width, height: Self.thumbnailHeight)
                    .clipped()
            }
            .frame(height: Self.thumbnailHeight)
            .contentShape(Rectangle())
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Theme.line, lineWidth: 1))
            .onTapGesture(count: 2) {
                QuickLookController.shared.show(urls: Self.existingURLs(for: block), index: index)
            }
        } else {
            FallbackTile {
                VStack(spacing: 6) {
                    Image(systemName: block.type == .image ? "photo" : "doc")
                        .font(.system(size: 18, weight: .light))
                    Text(name)
                        .font(.system(size: 11))
                        .lineLimit(2)
                }
                .foregroundStyle(Theme.tileText)
                .padding(8)
            }
            .frame(height: 120)
            .help("파일 위치: Application Support/CapsuleStash/\(block.type == .image ? "images" : "files")/\(name)")
            .onTapGesture(count: 2) { openAttachment(named: name) }
        }
    }

    /// 파일 타일 더블클릭 → 기본 앱으로 열기 (T-32).
    private func openAttachment(named name: String) {
        let kind = block.type == .image ? AttachmentStore.imagesKind : AttachmentStore.filesKind
        guard let url = AttachmentStore.fileURL(kind: kind, name: name),
              FileManager.default.fileExists(atPath: url.path) else {
            appState.notify("파일이 없습니다")
            return
        }
        NSWorkspace.shared.open(url)
    }
}
