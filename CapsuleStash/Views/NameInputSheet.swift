import SwiftUI

/// Workspace/Project 문서 이름 입력 시트.
/// 기본 `NSAlert`+`NSTextField` 조합은 입력창이 좁고 앱 테마와 어울리지 않아 전용 시트로 교체했다.
/// (docs/DESIGN.md §4) 입력창은 가로 100%, Enter=확인, esc=취소.
struct NamePrompt: Identifiable {
    let id = UUID()
    let title: String
    /// 템플릿 키(`'%@' 워크스페이스에...`)가 살아야 해서 합성된 String이 아니라 키 그대로 받는다.
    let subtitle: LocalizedStringKey?
    let placeholder: String
    let initial: String
    let confirmTitle: String
    let onConfirm: (String) -> Void
}

struct NameInputSheet: View {
    @Environment(\.dismiss) private var dismiss
    @FocusState private var fieldFocused: Bool

    let prompt: NamePrompt
    @State private var text: String

    init(prompt: NamePrompt) {
        self.prompt = prompt
        _text = State(initialValue: prompt.initial)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            LText(key: prompt.title)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Theme.ink)

            if let subtitle = prompt.subtitle {
                Text(subtitle)
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.muted)
            }

            TextField(LocalizedStringKey(prompt.placeholder), text: $text)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 14))
                .foregroundStyle(Theme.ink)
                .focused($fieldFocused)
                .frame(maxWidth: .infinity)
                .onSubmit(confirm)

            HStack(spacing: 10) {
                Spacer(minLength: 0)
                CapsuleButton(title: "취소", action: { dismiss() })
                CapsuleButton(title: prompt.confirmTitle, style: .primary, action: confirm)
                    .disabled(trimmed.isEmpty)
            }
            .padding(.top, 4)
        }
        .padding(20)
        .frame(width: 400)
        .background(Theme.paper)
        // T-37 시트는 창 환경을 못 물려받을 수 있어 로케일 명시
        .environment(\.locale, AppLanguage.effectiveLocale)
        .onAppear { fieldFocused = true }
        .onKeyPress(.escape) {
            dismiss()
            return .handled
        }
    }

    private var trimmed: String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func confirm() {
        guard !trimmed.isEmpty else { return }
        prompt.onConfirm(trimmed)
        dismiss()
    }
}
