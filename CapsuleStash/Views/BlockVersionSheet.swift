import SwiftUI

/// T-58 블록 버전 기록 시트. 저장된 스냅샷 목록에서 골라 되돌린다.
/// 되돌리면 현행도 스냅샷으로 남으니 취소 가능하다. 시트라 베타에서도 안전.
struct BlockVersionSheet: View {
    @EnvironmentObject private var store: DataStore
    @EnvironmentObject private var appState: AppState
    @Environment(\.locale) private var locale
    @Environment(\.dismiss) private var dismiss
    @State private var expandedVersionId: UUID?

    let blockId: UUID

    private var block: Block? {
        store.allProjects
            .flatMap { $0.project.blocks }
            .first { $0.id == blockId }
    }

    private func relative(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = locale
        formatter.unitsStyle = .short
        return formatter.localizedString(for: date, relativeTo: Date())
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                LText(key: "버전 기록")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Theme.ink)
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(Theme.muted)
                }
                .buttonStyle(.plain)
            }
            if let block {
                if block.versions.isEmpty {
                    LText(key: "이전 버전이 없습니다")
                        .font(.system(size: 14))
                        .foregroundStyle(Theme.muted)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, 32)
                } else {
                    ScrollView {
                        VStack(spacing: 8) {
                            ForEach(block.versions.sorted(by: { $0.savedAt > $1.savedAt })) { version in
                                versionRow(block: block, version: version)
                            }
                        }
                    }
                    .frame(minHeight: 200, maxHeight: 420)
                }
            } else {
                LText(key: "이전 버전이 없습니다")
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.muted)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 32)
            }
        }
        .padding(20)
        .frame(width: 440)
    }

    private func versionRow(block: Block, version: BlockVersion) -> some View {
        let diff = TextDiff.diff(old: version.content, new: block.content)
        return VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(version.title)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Theme.ink)
                        .lineLimit(1)
                    Text(version.content)
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.muted)
                        .lineLimit(3)
                    Text(relative(version.savedAt))
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.muted)
                }
                Spacer(minLength: 8)
                VStack(spacing: 6) {
                    CapsuleButton(title: "복원") {
                        if store.restoreVersion(blockId: block.id, versionId: version.id) {
                            appState.notify(L10n.string("복원됨"))
                        }
                    }
                    if diff.changed > 0 {
                        Button {
                            withAnimation(.easeOut(duration: 0.15)) {
                                expandedVersionId = (expandedVersionId == version.id) ? nil : version.id
                            }
                        } label: {
                            Text(expandedVersionId == version.id
                                ? L10n.string("변경 닫기")
                                : L10n.format("변경 %lld줄 보기", diff.changed))
                        }
                        .buttonStyle(.plain)
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.accent)
                    }
                }
            }
            if expandedVersionId == version.id {
                diffView(diff)
            }
        }
        .padding(10)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Theme.line, lineWidth: 1))
    }

    /// 변경 줄만 모노로. `-` 빨강, `+` 초록, 문맥은 회색.
    private func diffView(_ diff: TextDiff.Result) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(Array(diff.lines.enumerated()), id: \.offset) { _, line in
                HStack(alignment: .top, spacing: 6) {
                    Text(String(line.sign))
                        .frame(width: 10)
                    Text(line.text.isEmpty ? " " : line.text)
                        .lineLimit(2)
                }
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(line.sign == "-" ? .red : line.sign == "+" ? .green : Theme.muted)
            }
            if diff.omitted > 0 {
                Text(L10n.format("외 %lld줄", diff.omitted))
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.muted)
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.codeBackground, in: RoundedRectangle(cornerRadius: 8))
    }
}
