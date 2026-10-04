import SwiftUI

/// 블록 타입 선택 목록 (생성 우선: 시트 → 저장 시 생성).
/// 베타 popover 크래시 회피로 + 자리는 네이티브 Menu로 대체되어 현재 미사용.
/// 베타 종료 후 팝오버 복귀 시 재사용한다.
struct BlockTypePicker: View {
    @EnvironmentObject private var appState: AppState

    let projectId: UUID
    var onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("추가할 블록")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Theme.muted)
                .padding(.horizontal, 10)
                .padding(.top, 8)
                .padding(.bottom, 4)
            ForEach(BlockType.pickable) { type in
                Button {
                    onDismiss()
                    // 생성 우선: 입력 시트를 먼저 보여주고 저장될 때만 만든다
                    appState.requestBlockCreation(type: type, in: projectId)
                } label: {
                    LText(key: type.displayName)
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.ink)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(L10n.string(type.purposeHint))
            }
        }
        .padding(.bottom, 6)
        .frame(width: 160)
        // T-37 팝오버는 창 환경을 못 물려받을 수 있어 로케일 명시
        .environment(\.locale, AppLanguage.effectiveLocale)
    }
}
