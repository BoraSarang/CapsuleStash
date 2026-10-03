import SwiftUI

/// 블록 타입 선택 목록 (생성 우선: 시트 → 저장 시 생성).
/// 사이드바 하단 `+` 팝오버와 타이틀바 `+` 팝오버가 공유한다.
/// Toolbar에는 `Menu`를 쓰지 않는다 — 숨긴 인디케이터 자리 때문에 셀이 비대칭으로 보인다.
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
                .help(type.purposeHint)
            }
        }
        .padding(.bottom, 6)
        .frame(width: 160)
        // T-37 팝오버는 창 환경을 못 물려받을 수 있어 로케일 명시
        .environment(\.locale, AppLanguage.effectiveLocale)
    }
}
