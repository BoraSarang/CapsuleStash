import Foundation

/// 앱 표시 언어 (T-25 한·영).
/// 설정(⌘,)에서 시스템/한국어/English 선택. 기본값은 시스템 언어이며,
/// 시스템 언어가 한·영이 아니면 영어로 떨어진다.
enum AppLanguage {
    static let key = "appLanguage"

    /// 저장값·시스템 언어 코드 → 적용 언어 식별자 ("ko"/"en").
    /// 순수 함수라 테스트가 직접 검증한다.
    static func resolve(saved: String?, systemCode: String?) -> String {
        if saved == "ko" || saved == "en" { return saved! }
        if systemCode == "ko" || systemCode == "en" { return systemCode! }
        return "en"
    }

    static func effectiveIdentifier() -> String {
        resolve(saved: UserDefaults.standard.string(forKey: key),
                systemCode: Locale.current.language.languageCode?.identifier)
    }

    static var effectiveLocale: Locale { Locale(identifier: effectiveIdentifier()) }
}
