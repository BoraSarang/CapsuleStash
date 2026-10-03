import SwiftUI

/// 마크다운 표시용 미니 렌더러 (T-26).
/// 전체 파서 의존성 없이 화면에 필요한 것만: 제목(#~###)·인용(>)·불릿(-/*)·펜스 코드(```).
/// 원문은 그대로 두고 표시만 바꾼다 (검색·복사·인라인 편집은 소스 기준).
enum MarkdownSegment: Equatable {
    case heading(level: Int, text: String)
    case quote(lines: [String])
    case bullet(items: [String])
    case code(language: String, lines: [String])
    case paragraph(lines: [String])
    case blank

    /// 행 단위 파싱. 순수 함수라 테스트가 직접 검증한다.
    static func parse(_ text: String) -> [MarkdownSegment] {
        guard !text.isEmpty else { return [] }
        var segments: [MarkdownSegment] = []
        var inFence = false
        var fenceLanguage = ""
        var fenceLines: [String] = []
        var quoteLines: [String] = []
        var bulletItems: [String] = []
        var paragraphLines: [String] = []

        func flush() {
            if !quoteLines.isEmpty {
                segments.append(.quote(lines: quoteLines))
                quoteLines = []
            }
            if !bulletItems.isEmpty {
                segments.append(.bullet(items: bulletItems))
                bulletItems = []
            }
            if !paragraphLines.isEmpty {
                segments.append(.paragraph(lines: paragraphLines))
                paragraphLines = []
            }
        }

        for rawLine in text.components(separatedBy: "\n") {
            let trimmed = rawLine.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("```") {
                if inFence {
                    segments.append(.code(language: fenceLanguage, lines: fenceLines))
                    fenceLines = []
                    inFence = false
                } else {
                    flush()
                    fenceLanguage = String(trimmed.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                    inFence = true
                }
                continue
            }
            if inFence {
                fenceLines.append(rawLine)
                continue
            }
            if trimmed.hasPrefix(">") {
                if !bulletItems.isEmpty || !paragraphLines.isEmpty { flush() }
                quoteLines.append(String(trimmed.dropFirst()).trimmingCharacters(in: .whitespaces))
                continue
            }
            if trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") {
                if !paragraphLines.isEmpty { flush() }
                bulletItems.append(String(trimmed.dropFirst(2)))
                continue
            }
            var level = 0
            for character in trimmed {
                guard character == "#" else { break }
                level += 1
            }
            if level > 0, level <= 6,
               trimmed.dropFirst(level).first?.isWhitespace == true {
                flush()
                let heading = String(trimmed.dropFirst(level)).trimmingCharacters(in: .whitespaces)
                segments.append(.heading(level: min(level, 3), text: heading))
                continue
            }
            if trimmed.isEmpty {
                flush()
                segments.append(.blank)
                continue
            }
            if !quoteLines.isEmpty { flush() }
            paragraphLines.append(rawLine)
        }
        if inFence {
            // 닫히지 않은 펜스는 코드로 간주
            segments.append(.code(language: fenceLanguage, lines: fenceLines))
        }
        flush()
        return segments
    }
}

/// 파싱 결과를 카드에 그린다. 색상은 토큰이라 라이트·다크 모두 보인다.
struct MarkdownBody: View {
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(MarkdownSegment.parse(text).enumerated()), id: \.offset) { _, segment in
                segmentView(segment)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func segmentView(_ segment: MarkdownSegment) -> some View {
        switch segment {
        case .heading(let level, let text):
            Text(text)
                .font(level == 1 ? Theme.serif(22) : level == 2 ? Theme.serif(18) : .system(size: 15, weight: .semibold))
                .foregroundStyle(Theme.ink)
        case .quote(let lines):
            HStack(alignment: .top, spacing: 8) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(Theme.muted)
                    .frame(width: 3)
                Text(lines.joined(separator: "\n"))
                    .font(.system(size: 14))
                    .italic()
                    .foregroundStyle(Theme.muted)
            }
        case .bullet(let items):
            VStack(alignment: .leading, spacing: 3) {
                ForEach(items.indices, id: \.self) { index in
                    HStack(alignment: .top, spacing: 6) {
                        Text("•").foregroundStyle(Theme.muted)
                        Text(items[index])
                            .font(.system(size: 14))
                            .foregroundStyle(Theme.ink)
                    }
                }
            }
        case .code(let language, let lines):
            VStack(alignment: .leading, spacing: 6) {
                if !language.isEmpty {
                    Text(language.uppercased())
                        .font(Theme.monoCaption)
                        .foregroundStyle(Theme.muted)
                }
                Text(lines.joined(separator: "\n"))
                    .font(Theme.monoBody)
                    .foregroundStyle(Theme.codeForeground)
                    .textSelection(.enabled)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.codeBackground, in: RoundedRectangle(cornerRadius: 10))
        case .paragraph(let lines):
            Text(lines.joined(separator: "\n"))
                .font(.system(size: 14))
                .foregroundStyle(Theme.ink)
                .lineSpacing(3)
                .textSelection(.enabled)
        case .blank:
            Spacer(minLength: 2)
        }
    }
}
