import SwiftUI

/// 마크다운 표시용 미니 렌더러 (T-26).
/// 전체 파서 의존성 없이 화면에 필요한 것만: 제목(#~###)·인용(>)·불릿(-/*)·펜스 코드(```).
/// 원문은 그대로 두고 표시만 바꾼다 (검색·복사·인라인 편집은 소스 기준).
enum MarkdownSegment: Equatable {
    case heading(level: Int, text: String)
    case quote(lines: [String])
    case bullet(items: [String])
    case code(language: String, lines: [String])
    case table(header: [String], rows: [[String]])
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

        /// `|---|---|` 구분행 판별
        func isDelimiter(_ line: String) -> Bool {
            let cells = line.split(separator: "|", omittingEmptySubsequences: true)
            guard cells.count >= 1 else { return false }
            return cells.allSatisfy { cell in
                let t = cell.trimmingCharacters(in: .whitespaces)
                return !t.isEmpty && t.allSatisfy { $0 == "-" || $0 == ":" }
            }
        }

        /// `| a | b |` → ["a", "b"]
        func splitRow(_ line: String) -> [String] {
            line.split(separator: "|", omittingEmptySubsequences: true)
                .map { $0.trimmingCharacters(in: .whitespaces) }
        }

        let lines = text.components(separatedBy: "\n")
        var index = 0
        while index < lines.count {
            let rawLine = lines[index]
            let trimmed = rawLine.trimmingCharacters(in: .whitespaces)
            // 표: 헤더행 + 구분행이 오면 본문 행까지 묶는다
            if trimmed.hasPrefix("|"), index + 1 < lines.count,
               isDelimiter(lines[index + 1].trimmingCharacters(in: .whitespaces)) {
                flush()
                let header = splitRow(trimmed)
                var rows: [[String]] = []
                index += 2
                while index < lines.count {
                    let rowTrimmed = lines[index].trimmingCharacters(in: .whitespaces)
                    guard rowTrimmed.hasPrefix("|") else { break }
                    rows.append(splitRow(rowTrimmed))
                    index += 1
                }
                segments.append(.table(header: header, rows: rows))
                continue
            }
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
                index += 1
                continue
            }
            if inFence {
                fenceLines.append(rawLine)
                index += 1
                continue
            }
            if trimmed.hasPrefix(">") {
                if !bulletItems.isEmpty || !paragraphLines.isEmpty { flush() }
                quoteLines.append(String(trimmed.dropFirst()).trimmingCharacters(in: .whitespaces))
                index += 1
                continue
            }
            if trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ")
                || trimmed.hasPrefix("· ") || trimmed.hasPrefix("• ") {
                if !paragraphLines.isEmpty { flush() }
                bulletItems.append(String(trimmed.dropFirst(2)).trimmingCharacters(in: .whitespaces))
                index += 1
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
                index += 1
                continue
            }
            if trimmed.isEmpty {
                flush()
                segments.append(.blank)
                index += 1
                continue
            }
            if !quoteLines.isEmpty { flush() }
            paragraphLines.append(rawLine)
            index += 1
        }
        if inFence {
            // 닫히지 않은 펜스는 코드로 간주
            segments.append(.code(language: fenceLanguage, lines: fenceLines))
        }
        flush()
        return segments
    }
}

/// 인라인 서식 토큰 (`**굵게**`·`*기울임*`·`` `코드` ``).
/// 닫히지 않거나 비어 있는 마커는 그대로 둔다. 순수 함수라 테스트가 직접 검증한다.
enum MarkdownInline: Equatable {
    case plain(String)
    case bold(String)
    case italic(String)
    case code(String)

    static func tokenize(_ raw: String) -> [MarkdownInline] {
        guard !raw.isEmpty else { return [] }
        var tokens: [MarkdownInline] = []
        var plain = ""
        var index = raw.startIndex

        func flush() {
            if !plain.isEmpty {
                tokens.append(.plain(plain))
                plain = ""
            }
        }

        while index < raw.endIndex {
            let char = raw[index]
            let next = raw.index(after: index)
            // `` `코드` `` — 펜스 코드와 달리 한 줄 안에서만 닫힌다
            if char == "`", next < raw.endIndex,
               let close = raw[next...].firstIndex(of: "`") {
                let code = String(raw[next..<close])
                if !code.isEmpty {
                    flush()
                    tokens.append(.code(code))
                    index = raw.index(after: close)
                    continue
                }
            }
            if char == "*" {
                // `**굵게**` 우선, 다음 `**` 가 없으면 리터럴
                if next < raw.endIndex, raw[next] == "*" {
                    let from = raw.index(index, offsetBy: 2, limitedBy: raw.endIndex) ?? raw.endIndex
                    if let range = raw[from...].range(of: "**"),
                       !raw[from..<range.lowerBound].isEmpty {
                        flush()
                        tokens.append(.bold(String(raw[from..<range.lowerBound])))
                        index = range.upperBound
                        continue
                    }
                    plain += "**"
                    index = from
                    continue
                }
                // `*기울임*`
                if next < raw.endIndex, let close = raw[next...].firstIndex(of: "*") {
                    let text = String(raw[next..<close])
                    if !text.isEmpty {
                        flush()
                        tokens.append(.italic(text))
                        index = raw.index(after: close)
                        continue
                    }
                }
            }
            plain.append(char)
            index = next
        }
        flush()
        return tokens
    }
}

/// 파싱 결과를 카드에 그린다. 색상은 토큰이라 라이트·다크 모두 보인다.
struct MarkdownBody: View {
    let text: String

    /// 인라인 서식 적용. 기본 글꼴은 호출 쪽이 정하고 굵게·기울임·코드는 토큰마다 입힌다.
    static func styled(_ raw: String, base: Font) -> Text {
        var result = Text("")
        for token in MarkdownInline.tokenize(raw) {
            switch token {
            case .plain(let string):
                result = result + Text(string).font(base)
            case .bold(let string):
                result = result + Text(string).font(base).fontWeight(.bold)
            case .italic(let string):
                result = result + Text(string).font(base).italic()
            case .code(let string):
                // Text 연결을 유지해야 해서 배경 필은 생략 (모노+색상으로 구분)
                result = result + Text(string)
                    .font(Theme.monoBody)
                    .foregroundStyle(Theme.codeForeground)
            }
        }
        return result
    }

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
            let base: Font = level == 1 ? Theme.serif(22)
                : level == 2 ? Theme.serif(18) : .system(size: 15, weight: .semibold)
            Self.styled(text, base: base)
                .foregroundStyle(Theme.ink)
        case .quote(let lines):
            HStack(alignment: .top, spacing: 8) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(Theme.muted)
                    .frame(width: 3)
                Self.styled(lines.joined(separator: "\n"), base: .system(size: 14))
                    .italic()
                    .foregroundStyle(Theme.muted)
            }
        case .bullet(let items):
            VStack(alignment: .leading, spacing: 3) {
                ForEach(items.indices, id: \.self) { index in
                    HStack(alignment: .top, spacing: 6) {
                        Text("•").foregroundStyle(Theme.muted)
                        Self.styled(items[index], base: .system(size: 14))
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
            Self.styled(lines.joined(separator: "\n"), base: .system(size: 14))
                .foregroundStyle(Theme.ink)
                .lineSpacing(3)
                .textSelection(.enabled)
        case .table(let header, let rows):
            tableView(header: header, rows: rows)
        case .blank:
            Spacer(minLength: 2)
        }
    }

    /// 표 렌더링. 헤더 굵게 + 행 줄무늬 없이 선으로만 구분.
    private func tableView(header: [String], rows: [[String]]) -> some View {
        let columnCount = max(header.count, rows.map(\.count).max() ?? 0)
        return Grid(alignment: .leading, horizontalSpacing: 0, verticalSpacing: 0) {
            GridRow {
                ForEach(0..<columnCount, id: \.self) { index in
                    Self.styled(index < header.count ? header[index] : "",
                                base: .system(size: 13, weight: .semibold))
                        .foregroundStyle(Theme.ink)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .background(Theme.tagBackground)
            Divider().overlay(Theme.line)
            ForEach(rows.indices, id: \.self) { rowIndex in
                GridRow {
                    ForEach(0..<columnCount, id: \.self) { colIndex in
                        Self.styled(colIndex < rows[rowIndex].count ? rows[rowIndex][colIndex] : "",
                                    base: .system(size: 13))
                            .foregroundStyle(Theme.ink)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                if rowIndex < rows.count - 1 {
                    Divider().overlay(Theme.line)
                }
            }
        }
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Theme.line, lineWidth: 1))
        .textSelection(.enabled)
    }
}
