import XCTest
@testable import CapsuleStash

/// T-47 업데이트 확인 (버전 비교·주기·디코딩). 네트워크 호출은 테스트하지 않는다.
final class UpdateTests: XCTestCase {
    // MARK: - 버전 비교

    func testIsNewerBasic() {
        XCTAssertTrue(ReleaseChecker.isNewer(tag: "v0.2.0", than: "0.1.0"))
        XCTAssertFalse(ReleaseChecker.isNewer(tag: "v0.1.0", than: "0.1.0"))
        XCTAssertFalse(ReleaseChecker.isNewer(tag: "v0.1.0", than: "0.2.0"))
    }

    func testIsNewerNumericNotLexical() {
        // "0.10.0" > "0.9.0" — 문자열 비교면 실패한다
        XCTAssertTrue(ReleaseChecker.isNewer(tag: "0.10.0", than: "0.9.0"))
        XCTAssertTrue(ReleaseChecker.isNewer(tag: "v1.0.0", than: "0.99.99"))
    }

    func testIsNewerPrefixAndLength() {
        XCTAssertTrue(ReleaseChecker.isNewer(tag: "V0.1.1", than: "0.1.0"))
        XCTAssertFalse(ReleaseChecker.isNewer(tag: "0.1", than: "0.1.0"))
        XCTAssertTrue(ReleaseChecker.isNewer(tag: "0.1.0.1", than: "0.1.0"))
    }

    // MARK: - 주기

    func testIsDueNeverAndFirstRun() {
        let now = Date()
        XCTAssertFalse(ReleaseChecker.isDue(frequency: .never, lastChecked: nil, now: now, launchDate: now))
        XCTAssertTrue(ReleaseChecker.isDue(frequency: .weekly, lastChecked: nil, now: now, launchDate: now))
    }

    func testIsDueWeeklyDaily() {
        let now = Date()
        XCTAssertFalse(ReleaseChecker.isDue(frequency: .weekly, lastChecked: now.addingTimeInterval(-1000),
                                            now: now, launchDate: now.addingTimeInterval(-2000)))
        XCTAssertTrue(ReleaseChecker.isDue(frequency: .weekly, lastChecked: now.addingTimeInterval(-604_801),
                                           now: now, launchDate: now.addingTimeInterval(-700_000)))
        XCTAssertTrue(ReleaseChecker.isDue(frequency: .daily, lastChecked: now.addingTimeInterval(-86_401),
                                           now: now, launchDate: now.addingTimeInterval(-100_000)))
    }

    func testIsDueAtLaunch() {
        let launch = Date()
        let before = launch.addingTimeInterval(-10)
        // 이번 실행 전에 확인했으면 다시 확인
        XCTAssertTrue(ReleaseChecker.isDue(frequency: .atLaunch, lastChecked: before,
                                           now: launch.addingTimeInterval(5), launchDate: launch))
        // 이번 실행에서 이미 확인했으면 건너뜀
        XCTAssertFalse(ReleaseChecker.isDue(frequency: .atLaunch, lastChecked: launch.addingTimeInterval(1),
                                            now: launch.addingTimeInterval(5), launchDate: launch))
    }

    // MARK: - 디코딩

    func testGitHubReleaseDecoding() throws {
        let json = """
        {"tag_name":"v0.2.0","html_url":"https://github.com/BoraSarang/CapsuleStash/releases/tag/v0.2.0","name":"v0.2.0","body":"## 변경\\n- 수정"}
        """.data(using: .utf8)!
        let release = try JSONDecoder().decode(GitHubRelease.self, from: json)
        XCTAssertEqual(release.tagName, "v0.2.0")
        XCTAssertEqual(release.body, "## 변경\n- 수정")
    }

    // MARK: - 표시 언어 기본값

    func testSavedUpdateFrequencyDefault() {
        let saved = UserDefaults.standard.string(forKey: "updateFrequency")
        UserDefaults.standard.removeObject(forKey: "updateFrequency")
        XCTAssertEqual(AppState.savedUpdateFrequency(), .weekly)
        if let saved { UserDefaults.standard.set(saved, forKey: "updateFrequency") }
    }
}
