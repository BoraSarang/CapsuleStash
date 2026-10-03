import Foundation

/// T-53 URL scheme (`capsule://`). Alfred·Raycast·Shortcuts·브라우저가 앱을 깨운다.
/// - `capsule://search?query=...` — 팔레트를 열고 검색어를 채운다
/// - `capsule://save?text=...&url=...` — 수신함에 바로 저장한다
/// - `capsule://open?project=...` — 문서를 선택하고 메인 창을 연다
enum CapsuleLink {
    enum Action: Equatable {
        case search(String)
        case save(text: String, url: String?)
        case openProject(String)
    }

    static let scheme = "capsule"

    /// 순수 함수라 테스트가 직접 검증한다.
    static func parse(_ url: URL) -> Action? {
        guard url.scheme?.lowercased() == scheme,
              let host = url.host?.lowercased(),
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return nil
        }
        func value(_ name: String) -> String? {
            components.queryItems?.first { $0.name == name }?.value
        }
        switch host {
        case "search":
            guard let query = value("query"), !query.isEmpty else { return nil }
            return .search(query)
        case "save":
            guard let text = value("text"), !text.isEmpty else { return nil }
            let rawURL = value("url")
            return .save(text: text, url: rawURL?.isEmpty == true ? nil : rawURL)
        case "open":
            guard let project = value("project"), !project.isEmpty else { return nil }
            return .openProject(project)
        default:
            return nil
        }
    }

    /// Shortcuts·Alfred가 여는 URL을 만든다. 순수 함수.
    static func searchURL(query: String) -> URL? {
        var components = URLComponents()
        components.scheme = scheme
        components.host = "search"
        components.queryItems = [URLQueryItem(name: "query", value: query)]
        return components.url
    }

    static func saveURL(text: String, url: String? = nil) -> URL? {
        var components = URLComponents()
        components.scheme = scheme
        components.host = "save"
        var items = [URLQueryItem(name: "text", value: text)]
        if let url { items.append(URLQueryItem(name: "url", value: url)) }
        components.queryItems = items
        return components.url
    }
}
