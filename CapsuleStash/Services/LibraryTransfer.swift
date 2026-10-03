import Foundation

/// T-50 일괄 내보내기·가져오기.
/// 파일에 시크릿이 닿지 않게 스냅샷(시크릿 제거)만 다룬다 ([HARD]).
/// 바이너리(이미지·첨부·아카이브 실파일)는 JSON에 묶지 않는다 — 가져올 때 참조는 비운다.
enum LibraryTransfer {
    static let schemaVersion = 1

    enum TransferError: Error, Equatable {
        case unsupportedVersion
        case decodeFailed
        case writeFailed
    }

    struct Envelope: Codable {
        let capsuleStashExport: Int
        let exportedAt: Date
        let workspaces: [Workspace]
    }

    // MARK: - JSON

    /// 스냅샷을 버전 봉투에 담아 인코딩한다. 시크릿은 스냅샷 단계에서 이미 비워진다.
    static func exportJSON(workspaces: [Workspace]) throws -> Data {
        let envelope = Envelope(capsuleStashExport: schemaVersion, exportedAt: Date(),
                                workspaces: DataStore.persistableSnapshot(from: workspaces))
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(envelope)
    }

    static func decodeJSON(_ data: Data) throws -> [Workspace] {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let envelope = try? decoder.decode(Envelope.self, from: data) else {
            throw TransferError.decodeFailed
        }
        guard envelope.capsuleStashExport == schemaVersion else {
            throw TransferError.unsupportedVersion
        }
        return envelope.workspaces
    }

    /// 가져온 데이터를 새 복사본으로 바꾼다. ID를 전부 새로 뽑고 참조를 맞춘다.
    /// 바이너리 참조(이미지·첨부·아카이브·썸네일)는 파일이 함께 오지 않으므로 비운다.
    /// 순수 함수라 테스트가 직접 검증한다.
    static func remapForImport(_ workspaces: [Workspace]) -> [Workspace] {
        workspaces.map { ws in
            let wsId = UUID()
            return Workspace(id: wsId, name: ws.name, projects: ws.projects.map { project in
                let projectId = UUID()
                return Project(
                    id: projectId, workspaceId: wsId, name: project.name,
                    colorHex: project.colorHex, note: project.note, tags: project.tags,
                    isFavorite: project.isFavorite, createdAt: project.createdAt,
                    updatedAt: project.updatedAt,
                    blocks: project.blocks.map { block in
                        // [HARD] 가져오기 경로로 시크릿이 들어오지 못하게 여기서도 비운다.
                        var credential = block.credential
                        credential?.password = ""
                        credential?.secondSecret = ""
                        return Block(
                            id: UUID(), projectId: projectId, type: block.type,
                            title: block.title, content: block.content,
                            language: block.language, url: block.url,
                            siteName: block.siteName, savedAt: block.savedAt,
                            credential: credential, isCollapsed: block.isCollapsed,
                            sortOrder: block.sortOrder, createdAt: block.createdAt,
                            updatedAt: block.updatedAt
                        )
                    }
                )
            })
        }
    }

    // MARK: - Markdown

    /// 파일명 금지 문자(`/` 등)를 `_`로 바꾼다. 순수 함수.
    static func safeFilename(_ name: String, ext: String) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let base = trimmed.isEmpty ? "untitled" : trimmed
        let cleaned = base.map { "/:\\?%*|\"<>".contains($0) ? "_" : $0 }
        return String(cleaned) + "." + ext
    }

    static func markdown(for project: Project) -> String {
        var lines: [String] = ["# \(project.name)", ""]
        if !project.note.isEmpty {
            lines.append("> \(project.note)")
            lines.append("")
        }
        if !project.tags.isEmpty {
            lines.append(project.tags.map { "#\($0)" }.joined(separator: " "))
            lines.append("")
        }
        for block in project.sortedBlocks {
            lines.append("## \(block.title)")
            lines.append("")
            lines.append(contentsOf: markdownBody(for: block))
            lines.append("")
        }
        return lines.joined(separator: "\n")
    }

    static func markdown(for workspace: Workspace) -> String {
        var lines: [String] = ["# \(workspace.name)", ""]
        for project in workspace.projects {
            lines.append("## \(project.name)")
            lines.append("")
            if !project.note.isEmpty {
                lines.append("> \(project.note)")
                lines.append("")
            }
            for block in project.sortedBlocks {
                lines.append("### \(block.title)")
                lines.append("")
                lines.append(contentsOf: markdownBody(for: block))
                lines.append("")
            }
        }
        return lines.joined(separator: "\n")
    }

    private static func markdownBody(for block: Block) -> [String] {
        switch block.type {
        case .code, .shell:
            let fence = "```\(block.language ?? "")"
            return [fence, block.content, "```"]
        case .webLink, .webArchive:
            var lines: [String] = []
            if let site = block.siteName, !site.isEmpty { lines.append(site) }
            if let url = block.url, !url.isEmpty { lines.append(url) }
            if !block.content.isEmpty { lines.append(""); lines.append(block.content) }
            return lines
        case .image, .file:
            return block.imageNames.map { "- \($0)" }
        case .credential:
            var lines: [String] = []
            if let credential = block.credential {
                // [HARD] 비밀값은 내보내지 않는다. 홈페이지·아이디만.
                if !credential.homepage.isEmpty { lines.append("\(L10n.string("홈페이지")): \(credential.homepage)") }
                if !credential.username.isEmpty { lines.append("\(L10n.string("아이디")): \(credential.username)") }
            }
            if !block.content.isEmpty { lines.append(""); lines.append(block.content) }
            return lines
        default:
            return [block.content]
        }
    }
}
