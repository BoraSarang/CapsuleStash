import Foundation

/// GitHub Releases 최신 조회 (T-47). 공개 저장소라 토큰 없이 조회한다.
/// 인앱 자동 설치는 하지 않고, 새 버전 알림 + 릴리스 페이지 이동만 한다.
struct GitHubRelease: Codable, Sendable, Equatable {
    let tagName: String
    let htmlURL: String
    let name: String?
    /// 릴리스 노트 (마크다운). 카드의 MarkdownBody로 그대로 그린다.
    let body: String?

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case htmlURL = "html_url"
        case name
        case body
    }
}

enum ReleaseCheckError: Error, Equatable {
    /// 릴리스 0개면 API가 404를 뱉는다. 네트워크 문제가 아니니 구분한다.
    case noPublishedRelease
    case fetchFailed
}

/// 업데이트 확인 주기 (T-47). 기본값은 매주.
enum UpdateFrequency: String, CaseIterable, Identifiable {
    case atLaunch, daily, weekly, never

    var id: String { rawValue }

    var labelKey: String {
        switch self {
        case .atLaunch: return "앱 실행 시"
        case .daily: return "매일"
        case .weekly: return "매주"
        case .never: return "안 함"
        }
    }
}

/// 업데이트 확인 상태 (T-47). AppState가 들고 설정·메뉴바가 함께 본다.
enum UpdateState: Equatable {
    case idle
    case checking
    case upToDate
    case updateAvailable(tag: String, htmlURL: String, notes: String)
    /// 메시지는 카탈로그 키 (L10n.string으로 푼다).
    case unavailable(String)
}

enum ReleaseChecker {
    /// 테스트가 임시 저장소로 바꿔 검증할 수 있게 var (가이드 §검증 방법).
    static var repository = "BoraSarang/CapsuleStash"

    static func fetchLatest() async throws -> GitHubRelease {
        try await fetchLatest(repository: repository)
    }

    static func fetchLatest(repository: String) async throws -> GitHubRelease {
        guard let url = URL(string: "https://api.github.com/repos/\(repository)/releases/latest") else {
            throw ReleaseCheckError.fetchFailed
        }
        var request = URLRequest(url: url)
        // User-Agent 버전 하드코딩 금지 — 번들에서 읽는다.
        request.setValue("CapsuleStash/\(Bundle.main.capsuleVersionString)", forHTTPHeaderField: "User-Agent")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw ReleaseCheckError.fetchFailed
        }
        guard let http = response as? HTTPURLResponse else { throw ReleaseCheckError.fetchFailed }
        if http.statusCode == 404 { throw ReleaseCheckError.noPublishedRelease }
        guard (200...299).contains(http.statusCode) else { throw ReleaseCheckError.fetchFailed }
        do {
            return try JSONDecoder().decode(GitHubRelease.self, from: data)
        } catch {
            throw ReleaseCheckError.fetchFailed
        }
    }

    /// `"v0.2.0" > "0.1.0"` 숫자 비교. 앞의 v/V는 떼고 자리수대로 본다.
    /// 순수 함수라 테스트가 직접 검증한다.
    static func isNewer(tag: String, than current: String) -> Bool {
        func normalized(_ s: String) -> [Int] {
            let stripped = s.trimmingCharacters(in: .whitespacesAndNewlines)
                .trimmingCharacters(in: CharacterSet(charactersIn: "vV"))
            return stripped.split(separator: ".").map { Int($0) ?? 0 }
        }
        let latest = normalized(tag)
        let base = normalized(current)
        for i in 0..<max(latest.count, base.count) {
            let a = i < latest.count ? latest[i] : 0
            let b = i < base.count ? base[i] : 0
            if a != b { return a > b }
        }
        return false
    }

    /// 주기 + 마지막 확인 시각 → 지금 확인할 차례인지. 순수 함수.
    /// 마지막 확인 시각은 UserDefaults에 영속화해야 재실행해도 주기가 산다.
    static func isDue(frequency: UpdateFrequency, lastChecked: Date?, now: Date, launchDate: Date) -> Bool {
        switch frequency {
        case .never:
            return false
        case .atLaunch:
            return lastChecked.map { $0 < launchDate } ?? true
        case .daily:
            return lastChecked.map { now.timeIntervalSince($0) >= 86_400 } ?? true
        case .weekly:
            return lastChecked.map { now.timeIntervalSince($0) >= 604_800 } ?? true
        }
    }
}
