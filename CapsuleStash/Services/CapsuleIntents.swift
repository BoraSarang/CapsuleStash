import AppIntents
import Foundation

/// T-53 Shortcuts 액션 2종. 별도 설정 없이 단축어 앱에 자동 노출된다.
/// 저장은 수신함 파일로 떨군다 (앱이 꺼져 있어도 됨). 검색은 URL로 앱을 깨운다.
struct SaveCapsuleIntent: AppIntent {
    static var title: LocalizedStringResource = "Capsule Stash에 저장"
    static var description = IntentDescription("텍스트를 Capsule Stash 수신함에 저장합니다.")

    @Parameter(title: "텍스트")
    var text: String

    @Parameter(title: "URL")
    var url: String?

    static var parameterSummary: some ParameterSummary {
        Summary("텍스트 저장 \(\.$text)") {
            \.$url
        }
    }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let payload = InboxPayload(text: text.trimmingCharacters(in: .whitespacesAndNewlines),
                                   url: url, source: "Shortcuts")
        guard payload.hasContent else {
            throw IntentError.empty
        }
        try payload.write()
        return .result(dialog: "수신함에 저장했습니다.")
    }

    enum IntentError: Error, CustomLocalizedStringResourceConvertible {
        case empty
        var localizedStringResource: LocalizedStringResource { "저장할 내용이 없습니다." }
    }
}

struct SearchCapsuleIntent: AppIntent {
    static var title: LocalizedStringResource = "Capsule Stash에서 검색"
    static var description = IntentDescription("Capsule Stash를 열고 검색합니다.")

    @Parameter(title: "검색어")
    var query: String

    static var parameterSummary: some ParameterSummary {
        Summary("검색 \(\.$query)")
    }

    /// Shortcuts 실행 뒤 앱으로 넘어가 onOpenURL이 이어받는다.
    static var openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        // openAppWhenRun으로 앱이 살아나면 URL을 직접 연다.
        if let url = CapsuleLink.searchURL(query: query) {
            NotificationCenter.default.post(name: .capsuleHandleLink, object: url)
        }
        return .result()
    }
}

extension Notification.Name {
    /// Shortcuts 검색 인텐트 → 앱 내 URL 처리로 이어주는 내부 통로.
    static let capsuleHandleLink = Notification.Name("CapsuleStash.handleLink")
}
