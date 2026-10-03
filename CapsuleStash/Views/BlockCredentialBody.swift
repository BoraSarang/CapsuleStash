import SwiftUI

/// Credential 블록 본문 (홈페이지·아이디·시크릿 행).
/// 시크릿 값 자체는 Keychain에만 있고, 잠금 상태면 마스킹 + 복사 차단 (T-10).
struct BlockCredentialBody: View {
    let block: Block

    @EnvironmentObject private var store: DataStore
    @EnvironmentObject private var appState: AppState

    var body: some View {
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
                        appState.openExternal(url)
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
                    if ClipboardService.copy(credential.username, label: "\(block.title) \(L10n.string("아이디"))") {
                        appState.notifyCopy("\(block.title) \(L10n.string("아이디"))")
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
            tooltip: L10n.format("%@ 복사", label),
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
}
