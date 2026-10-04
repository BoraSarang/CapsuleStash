import Foundation

// MARK: - T-02 데이터 모델 (2단: Workspace → Project 문서)
// 사용자 확정: Collection이 곧 하나의 프로젝트(문서) 개념이므로 중간 단을 없애고
// 블록을 담는 문서 단위를 Project라 부른다. (docs/DESIGN.md §4)

// MARK: Workspace

struct Workspace: Identifiable, Hashable, Codable {
    let id: UUID
    var name: String
    var projects: [Project]

    init(id: UUID = UUID(), name: String, projects: [Project] = []) {
        self.id = id
        self.name = name
        self.projects = projects
    }
}

// MARK: Project (문서 — 블록을 직접 담는다)

struct Project: Identifiable, Hashable, Codable {
    let id: UUID
    var workspaceId: UUID
    var name: String
    var colorHex: String
    var note: String
    var tags: [String]
    var isFavorite: Bool
    var createdAt: Date
    var updatedAt: Date
    var blocks: [Block]

    init(id: UUID = UUID(), workspaceId: UUID, name: String,
         colorHex: String = "#FF5C00", note: String = "",
         tags: [String] = [], isFavorite: Bool = false,
         createdAt: Date = Date(), updatedAt: Date = Date(), blocks: [Block] = []) {
        self.id = id
        self.workspaceId = workspaceId
        self.name = name
        self.colorHex = colorHex
        self.note = note
        self.tags = tags
        self.isFavorite = isFavorite
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.blocks = blocks
    }

    var sortedBlocks: [Block] { blocks.sorted { $0.sortOrder < $1.sortOrder } }

    var codeCount: Int { blocks.filter { $0.type.isCode }.count }

    /// 프로젝트 전체를 플레인텍스트로 (복사·내보내기용).
    func plainText(includeTitle: Bool = false, includeSecrets: Bool = false) -> String {
        let blocks = sortedBlocks.map { "## \($0.title)\n\($0.copyPayload(includeSecrets: includeSecrets))" }
        return ((includeTitle ? [name] : []) + blocks).joined(separator: "\n\n")
    }
}

// MARK: BlockType

enum BlockType: String, Codable, CaseIterable, Identifiable {
    case text, markdown, code, shell, webLink, webArchive, image, file, credential

    /// 레거시 별칭. `webLink` 는 디코딩 호환용으로만 남기고 신규 생성은 `webArchive` 하나로 통일한다 (T-28).
    /// 로드 시 `DataStore.normalizeWebBlocks` 가 전부 `webArchive` 로 바꾼다.
    static var pickable: [BlockType] {
        allCases.filter { $0 != .webLink }
    }

    var id: String { rawValue }

    var isCode: Bool { self == .code || self == .shell }

    /// mockup `.type` 배지 라벨
    var label: String {
        switch self {
        case .text: return "TEXT"
        case .markdown: return "MARKDOWN"
        case .code: return "CODE"
        case .shell: return "SHELL"
        case .webLink: return "WEB · LINK"
        case .webArchive: return "WEB · ARCHIVE"
        case .image: return "IMAGE"
        case .file: return "FILE"
        case .credential: return "CREDENTIAL"
        }
    }

    var displayName: String {
        switch self {
        case .text: return "텍스트"
        case .markdown: return "마크다운"
        case .code: return "코드"
        case .shell: return "셸 명령"
        case .webLink: return "웹 링크"
        case .webArchive: return "웹"
        case .image: return "이미지"
        case .file: return "파일"
        case .credential: return "계정 정보"
        }
    }

    var symbolName: String {
        switch self {
        case .text: return "text.alignleft"
        case .markdown: return "text.document"
        case .code: return "chevron.left.forwardslash.chevron.right"
        case .shell: return "terminal"
        case .webLink: return "link"
        case .webArchive: return "globe"
        case .image: return "photo"
        case .file: return "doc"
        case .credential: return "lock"
        }
    }

    /// 타입 선택·입력 시점에 보여줄 한 줄 용도 설명.
    /// 웹 링크(북마크: 주소+메모, 브라우저로 열기)와
    /// 웹 아카이브(본문 오프라인 보관, 실파일은 T-09)의 차이를 여기서 명시한다.
    var purposeHint: String {
        switch self {
        case .text: return "자유 메모"
        case .markdown: return "서식 있는 메모"
        case .code: return "언어 지정 코드 조각"
        case .shell: return "터미널 명령 (실행 안 함, 복사만)"
        case .webLink: return "페이지 주소 + 메모 — 열기로 브라우저에서 바로 열기"
        case .webArchive: return "웹 페이지 저장 — 주소·메모 + 브라우저 열기 + 오프라인 보관 (카드에서 저장·보기)"
        case .image: return "이미지 첨부 (파일 선택기·드래그앤드롭)"
        case .file: return "파일 첨부 (파일 선택기·드래그앤드롭)"
        case .credential: return "계정·API Key 보관 (시크릿 2개까지, Keychain 보관·자동 마스킹)"
        }
    }
}

// MARK: Block

/// 블록 버전 스냅샷 (T-58). 내용 편집 전 상태를 최대 20개 보관한다.
/// 제목·본문·언어만 남긴다 (첨부·시크릿은 현행 블록이 들고 있어 복원에 영향 없음).
struct BlockVersion: Identifiable, Hashable, Codable {
    let id: UUID
    var title: String
    var content: String
    var language: String?
    var savedAt: Date

    init(id: UUID = UUID(), title: String, content: String,
         language: String? = nil, savedAt: Date = Date()) {
        self.id = id
        self.title = title
        self.content = content
        self.language = language
        self.savedAt = savedAt
    }
}

struct Block: Identifiable, Hashable, Codable {
    let id: UUID
    var projectId: UUID
    var type: BlockType
    var title: String
    var content: String
    var language: String?
    var url: String?
    var siteName: String?
    var savedAt: Date?
    /// 이미지 블록의 파일 이름 목록 (MVP는 파일명만 보관, 원본은 외부 경로)
    var imageNames: [String]
    /// 웹 아카이브 실파일명 (T-09, `web-archives/` 아래). 없으면 미저장.
    var archiveFile: String?
    /// 웹 아카이브 PDF 실파일명 (T-09, `pdf/` 아래). 없으면 미저장.
    var pdfFile: String?
    /// 웹 아카이브 썸네일 (T-28, 저장 시점 스크린샷, `thumbnails/` 아래).
    var thumbnailFile: String?
    /// Credential 본문. [HARD] 시크릿은 파일 저장에서 제외되고 Keychain에 보관된다.
    var credential: Credential?
    var isCollapsed: Bool
    var sortOrder: Int
    var createdAt: Date
    var updatedAt: Date
    /// 버전 기록 (최대 20개, 오래된 것부터 버림). 구 JSON에는 없어 decodeIfPresent.
    var versions: [BlockVersion] = []

    private enum CodingKeys: String, CodingKey {
        case id, projectId, type, title, content, language, url, siteName, savedAt
        case imageNames, archiveFile, pdfFile, thumbnailFile, credential
        case isCollapsed, sortOrder, createdAt, updatedAt, versions
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        projectId = try container.decode(UUID.self, forKey: .projectId)
        type = try container.decode(BlockType.self, forKey: .type)
        title = try container.decodeIfPresent(String.self, forKey: .title) ?? ""
        content = try container.decodeIfPresent(String.self, forKey: .content) ?? ""
        language = try container.decodeIfPresent(String.self, forKey: .language)
        url = try container.decodeIfPresent(String.self, forKey: .url)
        siteName = try container.decodeIfPresent(String.self, forKey: .siteName)
        savedAt = try container.decodeIfPresent(Date.self, forKey: .savedAt)
        imageNames = try container.decodeIfPresent([String].self, forKey: .imageNames) ?? []
        archiveFile = try container.decodeIfPresent(String.self, forKey: .archiveFile)
        pdfFile = try container.decodeIfPresent(String.self, forKey: .pdfFile)
        thumbnailFile = try container.decodeIfPresent(String.self, forKey: .thumbnailFile)
        credential = try container.decodeIfPresent(Credential.self, forKey: .credential)
        isCollapsed = try container.decodeIfPresent(Bool.self, forKey: .isCollapsed) ?? false
        sortOrder = try container.decodeIfPresent(Int.self, forKey: .sortOrder) ?? 0
        createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
        updatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt) ?? Date()
        versions = try container.decodeIfPresent([BlockVersion].self, forKey: .versions) ?? []
    }

    init(id: UUID = UUID(), projectId: UUID, type: BlockType, title: String,
         content: String = "", language: String? = nil, url: String? = nil,
         siteName: String? = nil, savedAt: Date? = nil, imageNames: [String] = [],
         archiveFile: String? = nil, pdfFile: String? = nil, thumbnailFile: String? = nil,
         credential: Credential? = nil, isCollapsed: Bool = false, sortOrder: Int = 0,
         createdAt: Date = Date(), updatedAt: Date = Date(),
         versions: [BlockVersion] = []) {
        self.id = id
        self.projectId = projectId
        self.type = type
        self.title = title
        self.content = content
        self.language = language
        self.url = url
        self.siteName = siteName
        self.savedAt = savedAt
        self.imageNames = imageNames
        self.archiveFile = archiveFile
        self.pdfFile = pdfFile
        self.thumbnailFile = thumbnailFile
        self.credential = credential
        self.isCollapsed = isCollapsed
        self.sortOrder = sortOrder
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.versions = versions
    }

    /// 검색 인덱스용 문자열. [HARD] Credential 비밀값은 포함하지 않는다.
    var searchIndexText: String {
        var parts: [String] = [title, content]
        if let language { parts.append(language) }
        if let url { parts.append(url) }
        if let siteName { parts.append(siteName) }
        parts.append(contentsOf: imageNames)
        if let credential {
            // 제목·홈페이지·아이디만 색인. password/secondSecret 은 제외.
            parts.append(credential.homepage)
            parts.append(credential.username)
        }
        return parts.joined(separator: " ")
    }

    /// 제목이 비었을 때 내용에서 끌어오는 기본 제목 (T-30).
    /// 마크다운 `#`·본문 첫 줄·URL 호스트·아이디 순으로 고르고, 없으면 타입 표시명.
    /// 제목은 사용자 데이터라 번역하지 않는다 (있는 그대로 저장).
    func suggestedTitle() -> String {
        switch type {
        case .webLink, .webArchive:
            if let site = siteName, !site.isEmpty { return site }
            if let url, let host = URL(string: url)?.host, !host.isEmpty { return host }
        case .text, .markdown, .code, .shell:
            let lines = content.split(separator: "\n", omittingEmptySubsequences: false)
            for rawLine in lines {
                var line = rawLine.trimmingCharacters(in: .whitespaces)
                if type == .markdown {
                    line = String(line.drop(while: { $0 == "#" })).trimmingCharacters(in: .whitespaces)
                }
                if !line.isEmpty { return String(line.prefix(40)) }
            }
        case .credential:
            if let credential {
                if !credential.username.isEmpty { return credential.username }
                if let host = URL(string: credential.homepage)?.host, !host.isEmpty { return host }
            }
        case .image, .file:
            break
        }
        return type.displayName
    }

    /// 복사 대상 문자열.
    /// - Parameter includeSecrets: Credential 비밀값을 포함할지. 기본값 false.
    ///   호출자는 `DataStore.isVaultUnlocked` 일 때만 true 를 전달한다 ([HARD]).
    func copyPayload(includeSecrets: Bool = false) -> String {
        if let credential {
            let open = [credential.homepage, credential.username].filter { !$0.isEmpty }
            if includeSecrets {
                let secrets = [credential.password, credential.secondSecret].filter { !$0.isEmpty }
                return (open + secrets).joined(separator: "\n")
            }
            return open.joined(separator: "\n")
        }
        if !imageNames.isEmpty && content.isEmpty {
            return imageNames.joined(separator: "\n")
        }
        return content
    }

    /// T-15 팔레트 단축키용 필드 복사 문자열 (`⌘1` 아이디, `⌘2` Secret 1).
    /// nil이면 복사 불가 — 호출자가 안내 토스트를 띄운다.
    /// [HARD] 시크릿은 `vaultUnlocked` 일 때만 반환한다.
    func credentialCopyText(secret: Bool, vaultUnlocked: Bool) -> String? {
        guard type == .credential, let credential else { return nil }
        if secret {
            guard vaultUnlocked, !credential.password.isEmpty else { return nil }
            return credential.password
        }
        return credential.username.isEmpty ? nil : credential.username
    }
}

// MARK: Credential

/// 계정/키 보관 정보. Secret 2개까지 보관한다 (예: Naver API Client ID + Client Secret).
/// [HARD] 시크릿(password/secondSecret)은 `DataStore.persistableSnapshot` 에서 비워지고
/// Keychain에만 보관된다. 홈페이지·아이디는 비밀값이 아니라 일반 저장소에 기록된다.
struct Credential: Hashable, Codable {
    var homepage: String
    var username: String
    var password: String
    /// 두 번째 시크릿 (선택, 비우면 미사용). 검색·로그·복사(기본)에서 제외, Vault 해제 시에만 취급.
    var secondSecret: String

    init(homepage: String = "", username: String = "", password: String = "", secondSecret: String = "") {
        self.homepage = homepage
        self.username = username
        self.password = password
        self.secondSecret = secondSecret
    }

    private enum CodingKeys: String, CodingKey {
        case homepage, username, password, secondSecret
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        homepage = try container.decodeIfPresent(String.self, forKey: .homepage) ?? ""
        username = try container.decodeIfPresent(String.self, forKey: .username) ?? ""
        password = try container.decodeIfPresent(String.self, forKey: .password) ?? ""
        secondSecret = try container.decodeIfPresent(String.self, forKey: .secondSecret) ?? ""
    }
}

// MARK: 검색

struct SearchQuery: Equatable {
    var freeText: String = ""
    var types: Set<BlockType> = []
    var projectName: String?
    var tags: Set<String> = []

    /// `type:code project:"Docker 배포" tag:swift docker` 형태 파싱 (PLAN §11).
    /// 공백이 포함된 값은 큰따옴표로 감싼다. `project:` 는 문서(Project)명, `tag:` 는 태그 기준.
    static func parse(_ raw: String) -> SearchQuery {
        var query = SearchQuery()
        var words: [String] = []
        for token in Self.tokenize(raw) {
            if token.hasPrefix("type:") {
                let value = String(token.dropFirst(5)).lowercased()
                // 레거시 별칭: 구 type:weblink 는 type:webarchive 와 같다 (T-28)
                if value == "weblink" {
                    query.types.insert(.webArchive)
                } else if let type = BlockType(rawValue: value) { query.types.insert(type) }
            } else if token.hasPrefix("project:") {
                let value = String(token.dropFirst(8)).trimmingCharacters(in: .whitespaces)
                if !value.isEmpty { query.projectName = value }
            } else if token.hasPrefix("tag:") {
                var value = String(token.dropFirst(4)).trimmingCharacters(in: .whitespaces)
                if value.hasPrefix("#") { value.removeFirst() }
                if !value.isEmpty { query.tags.insert(value.normalizedForSearch) }
            } else {
                words.append(token)
            }
        }
        query.freeText = words.joined(separator: " ").trimmingCharacters(in: .whitespaces).normalizedForSearch
        return query
    }

    /// 공백을 구분자로 삼되, `"..."` 안의 공백은 유지한다.
    static func tokenize(_ raw: String) -> [String] {
        var tokens: [String] = []
        var current = ""
        var insideQuotes = false

        for character in raw {
            if character == "\"" {
                if insideQuotes {
                    tokens.append(current)
                    current = ""
                    insideQuotes = false
                } else {
                    insideQuotes = true
                }
                continue
            }
            if character.isWhitespace && !insideQuotes {
                if !current.isEmpty { tokens.append(current); current = "" }
                continue
            }
            current.append(character)
        }
        if !current.isEmpty { tokens.append(current) }
        return tokens
    }

    var isEmpty: Bool { freeText.isEmpty && types.isEmpty && projectName == nil && tags.isEmpty }

    /// 팔레트 빈 결과 화면에 보여줄 사용법
    static let usageHint = "예: type:code · project:\"Docker 배포\" · tag:업무/진행중 · docker"
}

// MARK: - 검색 정규화 (T-16)

///
/// 전각(全角) 영숫자·공백을 반각으로 접어 검색한다. 쿼리·색인 양쪽에 적용.
extension String {
    var normalizedForSearch: String {
        var result = ""
        result.reserveCapacity(count)
        for scalar in unicodeScalars {
            let v = scalar.value
            if v == 0x3000 {
                result.append(" ")
            } else if v >= 0xFF01 && v <= 0xFF5E {
                result.append(Character(UnicodeScalar(v - 0xFEE0)!))
            } else {
                result.append(Character(scalar))
            }
        }
        return result.lowercased()
    }
}

struct SearchHit: Identifiable {
    enum Kind: String {
        case project, block, credential
    }

    let id: String
    let kind: Kind
    let project: Project
    let workspaceName: String
    let block: Block?
    let snippet: String

    var path: String { "\(workspaceName) / \(project.name)" }
    var title: String { block?.title ?? project.name }
}

// MARK: - 스마트 그룹 (T-55)

// T-55 스마트 그룹: 검색 문법을 저장 조건으로 재사용한다.
// 조건 자체가 데이터라 Workspace가 아니라 UserDefaults에 둔다 (문서 export 대상 아님).
struct SmartGroup: Identifiable, Hashable, Codable {
    let id: UUID
    var name: String
    /// `SearchQuery.parse` 그대로 먹는 조건 문자열.
    var query: String

    init(id: UUID = UUID(), name: String, query: String) {
        self.id = id
        self.name = name
        self.query = query
    }
}

// MARK: 최근 사용 항목

struct RecentEntry: Identifiable, Hashable, Codable {
    let id: UUID
    let title: String
    let visitedAt: Date

    init(id: UUID = UUID(), title: String, visitedAt: Date = Date()) {
        self.id = id
        self.title = title
        self.visitedAt = visitedAt
    }
}
