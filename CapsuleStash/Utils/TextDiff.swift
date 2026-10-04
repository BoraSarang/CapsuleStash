import Foundation

/// 줄 단위 diff (T-58 버전 기록 표시용). LCS 기반 순수 함수.
/// 큰 문서(행 곱 25만 초과)는 전체 치환으로 표시한다.
enum TextDiff {
    struct Line: Hashable {
        /// " " 유지, "-" 삭제, "+" 추가
        var sign: Character
        var text: String
    }

    struct Result {
        /// 문맥 포함 평탄 리스트 (최대 maxLines, 초과분은 omitted)
        var lines: [Line]
        var omitted: Int
        /// 실제 변경 줄 수 (문맥 제외)
        var changed: Int
    }

    static func diff(old: String, new: String, context: Int = 2, maxLines: Int = 40) -> Result {
        let a = old.components(separatedBy: "\n")
        let b = new.components(separatedBy: "\n")
        if a == b { return Result(lines: [], omitted: 0, changed: 0) }
        guard a.count * b.count <= 250_000 else {
            let lines = a.map { Line(sign: "-", text: $0) } + b.map { Line(sign: "+", text: $0) }
            return cap(lines: lines, maxLines: maxLines)
        }
        // LCS 테이블
        var table = Array(repeating: Array(repeating: 0, count: b.count + 1), count: a.count + 1)
        for i in stride(from: a.count - 1, through: 0, by: -1) {
            for j in stride(from: b.count - 1, through: 0, by: -1) {
                table[i][j] = a[i] == b[j]
                    ? table[i + 1][j + 1] + 1
                    : max(table[i + 1][j], table[i][j + 1])
            }
        }
        // 역추적 → op 나열 (e/d/i)
        var ops: [(Character, String)] = []
        var i = 0, j = 0
        while i < a.count, j < b.count {
            if a[i] == b[j] { ops.append((" ", a[i])); i += 1; j += 1 }
            else if table[i + 1][j] >= table[i][j + 1] { ops.append(("-", a[i])); i += 1 }
            else { ops.append(("+", b[j])); j += 1 }
        }
        while i < a.count { ops.append(("-", a[i])); i += 1 }
        while j < b.count { ops.append(("+", b[j])); j += 1 }
        // 변경점 주변 문맥 묶기
        var keep = Array(repeating: false, count: ops.count)
        for (index, op) in ops.enumerated() where op.0 != " " {
            for k in max(0, index - context)...min(ops.count - 1, index + context) {
                keep[k] = true
            }
        }
        var lines: [Line] = []
        var changed = 0
        for (index, op) in ops.enumerated() where keep[index] {
            lines.append(Line(sign: op.0, text: op.1))
            if op.0 != " " { changed += 1 }
        }
        return cap(lines: lines, maxLines: maxLines, changed: changed)
    }

    private static func cap(lines: [Line], maxLines: Int, changed: Int? = nil) -> Result {
        let realChanged = changed ?? lines.filter { $0.sign != " " }.count
        guard lines.count > maxLines else {
            return Result(lines: lines, omitted: 0, changed: realChanged)
        }
        return Result(lines: Array(lines.prefix(maxLines)),
                      omitted: lines.count - maxLines, changed: realChanged)
    }
}
