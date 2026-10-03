import Foundation

/// 코드 레벨 문자열의 앱 표시 언어 조회 (T-46).
/// SwiftUI 리터럴과 달리 번들 언어를 따르지 않으므로, 컴파일된 테이블에서 직접 읽는다.
/// 재시작 없이 in-app 언어 설정을 따른다. 없으면 키 그대로 (한국어 소스이므로 안전).
enum L10n {
    /// 명시 로케일 테이블에서 조회. 테스트는 locale을 직접 지정한다.
    static func string(_ key: String, locale: Locale = AppLanguage.effectiveLocale) -> String {
        let code = languageCode(of: locale)
        if code == "ko" { return key }
        return lookup(key, code: code) ?? key
    }

    /// `%@`/`%d` 자리 표시자를 채운다. 키 자체가 서식이다 (예: `"%@ 복사됨"`).
    static func format(_ key: String, _ args: CVarArg..., locale: Locale = AppLanguage.effectiveLocale) -> String {
        String(format: string(key, locale: locale), locale: locale, arguments: args)
    }

    private static func languageCode(of locale: Locale) -> String {
        locale.identifier.hasPrefix("ko") ? "ko" : "en"
    }

    private static func lookup(_ key: String, code: String) -> String? {
        guard let path = Bundle.main.path(forResource: code, ofType: "lproj"),
              let bundle = Bundle(path: path) else { return nil }
        let value = bundle.localizedString(forKey: key, value: nil, table: nil)
        return value == key ? nil : value
    }
}
