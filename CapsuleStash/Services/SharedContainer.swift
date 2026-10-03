import Foundation

/// T-48 공유 채널 (Share 확장·URL scheme·App Intents 공용).
/// App Group 컨테이너가 있으면 쓰고, 없으면(adhoc 서명·프로비저닝 전) 앱 저장소로 폴백한다.
/// 폴백이면 확장과 본체가 파일을 공유 못하므로, 그때 확장은 안내만 띄운다.
enum SharedContainer {
    /// 유료 팀 프로비저닝 후 활성화되는 그룹 ID. 바꾸면 양쪽 entitlements도 함께 바꾼다.
    static var groupID = "group.com.borasarang.CapsuleStash"
    static let inboxFolderName = "Inbox"

    /// 확장과 본체가 함께 보는 폴더. nil이면 공유 불가(폴백 위치라도 반환은 한다).
    static var directoryURL: URL {
        if let groupURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: groupID) {
            return groupURL
        }
        return PersistenceStore.directoryURL
    }

    /// 지금 그룹 컨테이너를 실제로 쓰고 있는지. 확장은 이걸 보고 저장/안내를 가른다.
    static var isShared: Bool {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: groupID) != nil
    }

    static var inboxURL: URL {
        if let override = inboxOverride { return override }
        return directoryURL.appendingPathComponent(inboxFolderName, isDirectory: true)
    }

    /// 테스트 격리용. 설정하면 수신함 파일이 실제 저장소 대신 여기로 간다.
    static var inboxOverride: URL? = nil
}

/// 수신함 파일 1건. 텍스트·URL만 받는다 (계정형은 Vault 잠금과 얽히니 제외, PLAN T-48).
struct InboxPayload: Codable, Equatable {
    static let version = 1
    var version: Int = 1
    /// 본문 텍스트 (빈 문자열이면 URL만 저장).
    var text: String
    var url: String?
    /// 어디서 왔는지 (확장·단축어·URL scheme). 표시·로그용, 파일명엔 안 쓴다.
    var source: String?

    init(text: String, url: String? = nil, source: String? = nil) {
        self.text = text
        self.url = url
        self.source = source
    }

    /// `inbox-<uuid>.json`. UUID라 동시 저장도 안 겹친다. 순수 함수.
    static func filename() -> String { "inbox-\(UUID().uuidString).json" }

    func write(to directory: URL = SharedContainer.inboxURL) throws -> URL {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(self)
        let url = directory.appendingPathComponent(Self.filename())
        try data.write(to: url, options: .atomic)
        return url
    }

    static func read(from url: URL) throws -> InboxPayload {
        let payload = try JSONDecoder().decode(InboxPayload.self, from: Data(contentsOf: url))
        guard payload.version == version else { throw InboxError.unsupportedVersion }
        return payload
    }

    /// 저장할 게 있는지 (공백·nil URL만이면 false).
    var hasContent: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !(url?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
    }

    enum InboxError: Error, Equatable {
        case unsupportedVersion
    }
}
