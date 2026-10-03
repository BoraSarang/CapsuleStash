import XCTest
@testable import CapsuleStash

/// 마크다운 파서·인라인 검증.
final class MarkdownTests: XCTestCase {
    // MARK: - 마크다운 파서 (T-26)
    func testMarkdownParse() {
        let segments = MarkdownSegment.parse("# 제목\n## 부제\n### 소제\n본문\n> 인용\n- 하나\n- 둘\n```swift\nlet a = 1\n```\n")
        XCTAssertEqual(segments[0], .heading(level: 1, text: "제목"))
        XCTAssertEqual(segments[1], .heading(level: 2, text: "부제"))
        XCTAssertEqual(segments[2], .heading(level: 3, text: "소제"))
        XCTAssertEqual(segments[3], .paragraph(lines: ["본문"]))
        XCTAssertEqual(segments[4], .quote(lines: ["인용"]))
        XCTAssertEqual(segments[5], .bullet(items: ["하나", "둘"]))
        XCTAssertEqual(segments[6], .code(language: "swift", lines: ["let a = 1"]))
        // # 뒤 공백 없으면 제목 아님, 닫히지 않은 펜스는 코드로
        XCTAssertEqual(MarkdownSegment.parse("#태그"), [.paragraph(lines: ["#태그"])])
        XCTAssertEqual(MarkdownSegment.parse("```\nabc"), [.code(language: "", lines: ["abc"])])
        XCTAssertEqual(MarkdownSegment.parse(""), [])
    }

    func testMarkdownTableParse() {
        let text = "| 이름 | 값 |\n|---|---|\n| A | 1 |\n| B | 2 | extra |\n본문"
        let segments = MarkdownSegment.parse(text)
        XCTAssertEqual(segments[0], .table(header: ["이름", "값"],
                                           rows: [["A", "1"], ["B", "2", "extra"]]))
        XCTAssertEqual(segments[1], .paragraph(lines: ["본문"]))
        // 구분행 없으면 표 아님
        XCTAssertEqual(MarkdownSegment.parse("| a | b |"),
                       [.paragraph(lines: ["| a | b |"])])
    }

    // MARK: - 마크다운 인라인 (T-40: 굵게·기울임·코드·`·` 불릿)
    func testMarkdownInlineTokenize() {
        XCTAssertEqual(MarkdownInline.tokenize("**굵게** 일반 `코드` *기울임*"), [
            .bold("굵게"), .plain(" 일반 "), .code("코드"), .plain(" "), .italic("기울임")
        ])
        // 닫히지 않거나 비어 있는 마커는 리터럴 유지
        XCTAssertEqual(MarkdownInline.tokenize("**열림"), [.plain("**열림")])
        XCTAssertEqual(MarkdownInline.tokenize("`코드"), [.plain("`코드")])
        XCTAssertEqual(MarkdownInline.tokenize("*하나"), [.plain("*하나")])
        XCTAssertEqual(MarkdownInline.tokenize(""), [])
    }

    func testMarkdownDotBullets() {
        XCTAssertEqual(MarkdownSegment.parse("· 하나\n· 둘"), [.bullet(items: ["하나", "둘"])])
        XCTAssertEqual(MarkdownSegment.parse("• 하나"), [.bullet(items: ["하나"])])
        // 마커 뒤 공백이 여러 개여도 내용은 trim
        XCTAssertEqual(MarkdownSegment.parse("·  `KEY` 설명"), [.bullet(items: ["`KEY` 설명"])])
    }

}
