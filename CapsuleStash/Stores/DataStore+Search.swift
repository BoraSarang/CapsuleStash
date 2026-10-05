import Foundation

/// 검색 (T-06/T-16). 매칭·스니펫·점수는 static 순수 함수로 두어 단위 테스트에서 직접 검증한다.
extension DataStore {
    /// 검색 매칭용 본문 상한 (문자 수). 거대 문서도 키 입력마다 전체 정규화를 안 타게.
    static let searchTextCap = 32_000

    var parsedQuery: SearchQuery { SearchQuery.parse(searchQuery) }

    var searchHits: [SearchHit] { hits(for: SearchQuery.parse(debouncedSearchQuery)) }

    /// T-55 스마트 그룹이 같은 검색 파이프를 쓴다. 저장 조건 = 검색 문법 그대로.
    func hits(for query: SearchQuery) -> [SearchHit] {
        guard !query.isEmpty else { return [] }
        let normalizedTerm = query.freeText.normalizedForSearch

        var hits: [SearchHit] = []

        for entry in allProjects {
            if let projectName = query.projectName,
               entry.project.name.normalizedForSearch != projectName.normalizedForSearch {
                continue
            }
            // T-16 태그 필터: 문서 태그 중 하나라도 포함해야 한다
            // T-56 중첩 태그: `tag:부모`는 `부모`와 `부모/자식`을 모두 잡는다 (접두 매칭)
            if !query.tags.isEmpty,
               !entry.project.tags.contains(where: { tag in
                   query.tags.contains { Self.tagMatches(queryTag: $0, tag: tag) }
               }) {
                continue
            }

            // 문서 자체
            if query.types.isEmpty, Self.matches(query.freeText, [entry.project.name, entry.project.note, entry.project.tags.joined(separator: " ")]) {
                hits.append(SearchHit(
                    id: "project-\(entry.project.id)",
                    kind: .project,
                    project: entry.project,
                    workspaceName: entry.workspace.name,
                    block: nil,
                    snippet: L10n.format("블록 %lld개", entry.project.blocks.count)
                ))
            }

            for block in entry.project.sortedBlocks {
                if !query.types.isEmpty, !query.types.contains(block.type) { continue }
                guard query.freeText.isEmpty
                    || cachedNormalizedText(block).contains(normalizedTerm) else { continue }

                let kind: SearchHit.Kind = block.type == .credential ? .credential : .block
                hits.append(SearchHit(
                    id: "block-\(block.id)",
                    kind: kind,
                    project: entry.project,
                    workspaceName: entry.workspace.name,
                    block: block,
                    snippet: Self.snippet(for: block, term: query.freeText)
                ))
            }
        }

        // 문서 히트 우선, 그 다음 블록 내용 일치 순
        return hits.sorted { lhs, rhs in
            if lhs.kind != rhs.kind {
                return Self.kindRank(lhs.kind) < Self.kindRank(rhs.kind)
            }
            return Self.score(rhs, term: query.freeText) > Self.score(lhs, term: query.freeText)
        }
    }

    /// 블록 검색색인 정규화 (캐시 적중 시 해시 비교만).
    /// 키 입력마다 바뀌는 블록만 정규화한다. 상한 32k자는 여기서 적용.
    func cachedNormalizedText(_ block: Block) -> String {
        let source = String(block.searchIndexText.prefix(Self.searchTextCap))
        let hash = source.hashValue
        if let cached = normalizedCache[block.id], cached.hash == hash { return cached.text }
        let normalized = source.normalizedForSearch
        normalizedCache[block.id] = (hash, normalized)
        return normalized
    }

    /// 캐시 비우기 (삭제 시 호출. 방치해도 정확성엔 영향 없고 메모리만 쓴다).
    func evictNormalizedCache(for blockIds: [UUID]) {
        for id in blockIds { normalizedCache.removeValue(forKey: id) }
    }

    static func kindRank(_ kind: SearchHit.Kind) -> Int {
        switch kind {
        case .project: return 0
        case .block: return 1
        case .credential: return 2
        }
    }

    static func score(_ hit: SearchHit, term: String) -> Int {
        let normalized = term.normalizedForSearch
        guard !normalized.isEmpty else { return 0 }
        if hit.title.normalizedForSearch.hasPrefix(normalized) { return 30 }
        if hit.title.normalizedForSearch.contains(normalized) { return 20 }
        // 블록 히트는 matches()를 통과한 것만 오므로 본문 포함은 확정. 재계산 안 한다.
        return 10
    }

    static func matches(_ term: String, _ candidates: [String]) -> Bool {
        if term.isEmpty { return true }
        let normalized = term.normalizedForSearch
        // 거대 본문은 앞에서만 찾는다 (전체 정규화 비용 회피).
        return candidates.contains {
            String($0.prefix(searchTextCap)).normalizedForSearch.contains(normalized)
        }
    }

    /// 끼워넣기 해석. 같은 문서에서 제목이(정규화 후) 일치하는 첫 블록. 순수 함수.
    nonisolated static func resolveEmbed(title: String, in blocks: [Block]) -> Block? {
        let want = title.normalizedForSearch
        guard !want.isEmpty else { return nil }
        return blocks.first { $0.title.normalizedForSearch == want }
    }

    /// 문서 ID로 끼워넣기 해석.
    func resolveEmbed(title: String, in projectId: UUID) -> Block? {
        guard let entry = allProjects.first(where: { $0.project.id == projectId }) else { return nil }
        return Self.resolveEmbed(title: title, in: entry.project.sortedBlocks)
    }

    /// 문서 내 타입 필터 (nil이면 전체). 타입 선택 드롭다운용. 순수 함수.
    nonisolated static func filterBlocks(_ blocks: [Block], by type: BlockType?) -> [Block] {
        guard let type else { return blocks }
        return blocks.filter { $0.type == type }
    }

    /// T-56 중첩 태그 접두 매칭. `tag:업무`는 `업무`·`업무/진행중`에 닿고 `업무용`에는 안 닿는다.
    /// 쿼리·태그 모두 정규화(전각·소문자) 후 비교한다. 순수 함수.
    nonisolated static func tagMatches(queryTag: String, tag: String) -> Bool {
        let query = queryTag.normalizedForSearch
        let candidate = tag.normalizedForSearch
        guard !query.isEmpty else { return false }
        return candidate == query || candidate.hasPrefix(query + "/")
    }

    static func snippet(for block: Block, term: String) -> String {
        if block.type.isCode {
            let firstLine = block.content.split(separator: "\n").first.map(String.init) ?? block.content
            return "\(block.language?.uppercased() ?? "CODE") · \(firstLine)"
        }
        guard !term.isEmpty else {
            return block.displaySubtitle
        }
        // 거대 본문은 앞에서만 찾는다 (전체 소문자화 비용 회피).
        let text = String(block.content.prefix(searchTextCap)).replacingOccurrences(of: "\n", with: " ")
        guard let range = text.lowercased().range(of: term) else { return block.displaySubtitle }
        let start = text.index(range.lowerBound, offsetBy: -20, limitedBy: text.startIndex) ?? text.startIndex
        let end = text.index(range.upperBound, offsetBy: 40, limitedBy: text.endIndex) ?? text.endIndex
        return (start == text.startIndex ? "" : "…") + text[start..<end] + (end == text.endIndex ? "" : "…")
    }
}
