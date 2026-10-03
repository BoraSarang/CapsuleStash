import XCTest
@testable import CapsuleStash

/// T-53 URL scheme 검증 (파싱·생성 왕복).
final class CapsuleLinkTests: XCTestCase {
    func testParseSearch() {
        let url = URL(string: "capsule://search?query=type:code%20docker")!
        XCTAssertEqual(CapsuleLink.parse(url), .search("type:code docker"))
    }

    func testParseSave() {
        let url = URL(string: "capsule://save?text=%EB%A9%94%EB%AA%A8&url=https://example.com")!
        XCTAssertEqual(CapsuleLink.parse(url), .save(text: "메모", url: "https://example.com"))
        let noURL = URL(string: "capsule://save?text=hello")!
        XCTAssertEqual(CapsuleLink.parse(noURL), .save(text: "hello", url: nil))
    }

    func testParseOpen() {
        XCTAssertEqual(CapsuleLink.parse(URL(string: "capsule://open?project=Inbox")!), .openProject("Inbox"))
    }

    func testParseRejects() {
        XCTAssertNil(CapsuleLink.parse(URL(string: "https://example.com")!), "다른 scheme 거부")
        XCTAssertNil(CapsuleLink.parse(URL(string: "capsule://delete?all=yes")!), "모르는 host 거부")
        XCTAssertNil(CapsuleLink.parse(URL(string: "capsule://save")!), "빈 저장은 거부")
        XCTAssertNil(CapsuleLink.parse(URL(string: "capsule://search")!), "빈 검색은 거부")
    }

    func testBuildersRoundTrip() {
        let search = CapsuleLink.searchURL(query: "한글 쿼리")!
        XCTAssertEqual(CapsuleLink.parse(search), .search("한글 쿼리"))
        let save = CapsuleLink.saveURL(text: "메모", url: "https://example.com/a?b=c")!
        XCTAssertEqual(CapsuleLink.parse(save), .save(text: "메모", url: "https://example.com/a?b=c"))
    }

    /// Safari 확장이 만드는 URL(JS URLSearchParams 규격)을 앱이 그대로 푼다.
    func testParsesSafariExtensionURL() {
        let url = URL(string: "capsule://save?text=%ED%95%9C%EA%B8%80%20%EC%A0%9C%EB%AA%A9&url=https%3A%2F%2Fexample.com%2Fa%3Fb%3Dc")!
        XCTAssertEqual(CapsuleLink.parse(url),
                       .save(text: "한글 제목", url: "https://example.com/a?b=c"))
    }
}
