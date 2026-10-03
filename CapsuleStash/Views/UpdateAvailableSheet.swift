import AppKit
import SwiftUI

/// 새 버전 안내 시트 (T-47). 인앱 설치는 안 한다 — 릴리스 노트 + 페이지 이동.
/// 설정·메뉴바가 함께 쓴다. 릴리스 노트는 카드용 MarkdownBody로 그대로 그린다.
struct UpdateAvailableSheet: View {
    let tag: String
    let htmlURL: String
    let notes: String

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L10n.format("새 버전 %@ 사용 가능", tag))
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Theme.ink)
            Text(L10n.format("현재 버전 %@", Bundle.main.capsuleVersionString))
                .font(.system(size: 13))
                .foregroundStyle(Theme.muted)

            if !notes.isEmpty {
                ScrollView {
                    MarkdownBody(text: notes)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 260)
                .padding(12)
                .background(Theme.card, in: RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Theme.line, lineWidth: 1))
            }

            Text(L10n.string("릴리스 페이지에서 ZIP을 내려받아 압축을 풀고, Capsule Stash를 Applications 폴더에 옮긴 뒤 우클릭→열기로 실행하세요. 공증 없는 배포라 첫 실행은 우클릭→열기가 필요합니다."))
                .font(.system(size: 12))
                .foregroundStyle(Theme.muted)

            HStack(spacing: 10) {
                Spacer(minLength: 0)
                CapsuleButton(title: "닫기", action: { dismiss() })
                CapsuleButton(title: "다운로드", style: .primary) {
                    // 에셋 직접 링크가 아니라 릴리스 페이지로 보낸다 (공증 없음 안내 노출 목적).
                    if let url = URL(string: htmlURL) {
                        NSWorkspace.shared.open(url)
                    }
                    dismiss()
                }
            }
            .padding(.top, 4)
        }
        .padding(20)
        .frame(width: 480)
        .background(Theme.paper)
        // 시트는 창 환경을 못 물려받을 수 있어 로케일 명시 (T-37과 동일)
        .environment(\.locale, AppLanguage.effectiveLocale)
    }
}
