import Foundation

/// 확장 타깃 자립용 수신함 기록기 (본체의 SharedContainer·InboxPayload와 같은 규격).
/// 본체와 코드를 나누지 않는 이유: appex는 앱 모듈을 import할 수 없다.
enum InboxDrop {
    static let groupID = "group.com.borasarang.CapsuleStash"

    static var isShared: Bool {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: groupID) != nil
    }

    static func save(text: String, url: String?, source: String) throws {
        guard let base = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: groupID) else {
            throw NSError(domain: "CapsuleStash", code: 1)
        }
        let directory = base.appendingPathComponent("Inbox", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        struct Payload: Codable {
            var version = 1
            var text: String
            var url: String?
            var source: String?
        }
        let data = try JSONEncoder().encode(Payload(text: text, url: url, source: source))
        let file = directory.appendingPathComponent("inbox-\(UUID().uuidString).json")
        try data.write(to: file, options: .atomic)
    }
}
