import AppKit
import Foundation
import UniformTypeIdentifiers

/// 이미지/파일 첨부 보관소.
/// `Application Support/CapsuleStash/{images,files}` 아래에 실파일을 복사해 보관하고,
/// `Block.imageNames` 에는 파일명만 기록한다. (바이너리 자체는 로그·검색에 올리지 않는다.)
enum AttachmentStore {
    static let imagesKind = "images"
    static let filesKind = "files"

    /// 첨부 선택 패널 (동기). 취소 시 빈 배열.
    @MainActor
    static func runOpenPanel(imageOnly: Bool, message: String) -> [URL] {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = imageOnly ? [.image] : [.item]
        panel.allowsMultipleSelection = true
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.message = message
        return panel.runModal() == .OK ? panel.urls : []
    }

    /// 외부 파일을 보관 폴더로 복사하고 저장된 파일명 목록을 반환한다.
    /// - Parameter baseDirectory: 테스트 격리용. 기본값은 실제 Application Support.
    @discardableResult
    static func importFiles(
        from sourceURLs: [URL],
        kind: String,
        baseDirectory: URL? = nil
    ) -> [String] {
        let dir = (baseDirectory ?? PersistenceStore.directoryURL).appendingPathComponent(kind, isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        } catch {
            DebugLogger.error(code: ErrorCode.storeSave, "첨부 폴더 생성 실패")
            return []
        }

        var stored: [String] = []
        for url in sourceURLs {
            let ext = url.pathExtension
            let rawBase = url.deletingPathExtension().lastPathComponent
            let safeBase = String(rawBase.prefix(40)).filter { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" || $0 == " " }
            let stem = safeBase.isEmpty ? "file" : safeBase
            let name = "\(stem)-\(UUID().uuidString.prefix(8))\(ext.isEmpty ? "" : ".\(ext)")"
            let dest = dir.appendingPathComponent(name)
            do {
                // 같은 이름이 있으면 교체하지 않고 건너뛴다 (uuid 접미사로 사실상 충돌 없음)
                if FileManager.default.fileExists(atPath: dest.path) {
                    try FileManager.default.removeItem(at: dest)
                }
                try FileManager.default.copyItem(at: url, to: dest)
                stored.append(name)
            } catch {
                // [HARD] paths are user data — log file name only, never contents.
                DebugLogger.error(code: ErrorCode.storeSave, "첨부 복사 실패: \(url.lastPathComponent)")
            }
        }
        if !stored.isEmpty {
            DebugLogger.feature("첨부 \(stored.count)개 가져옴 (\(kind))")
        }
        return stored
    }

    /// 경로 탈출(`..`, `/`) 방지 후 보관 파일 URL 반환. 없으면 nil.
    static func fileURL(kind: String, name: String) -> URL? {
        guard !name.isEmpty, !name.contains("/"), !name.contains("..") else { return nil }
        return PersistenceStore.attachmentsURL(kind: kind).appendingPathComponent(name)
    }

    static func remove(kind: String, name: String) {
        guard let url = fileURL(kind: kind, name: name) else { return }
        try? FileManager.default.removeItem(at: url)
    }

    static func isImageFile(_ url: URL) -> Bool {
        guard let type = UTType(filenameExtension: url.pathExtension) else { return false }
        return type.conforms(to: .image)
    }

    /// 드래그앤드롭 provider에서 파일 URL을 꺼낸다 (비동기 로드 후 main 콜백).
    static func urls(from providers: [NSItemProvider], completion: @escaping ([URL]) -> Void) {
        let fileURLId = UTType.fileURL.identifier
        let group = DispatchGroup()
        var urls: [URL] = []
        let lock = NSLock()

        for provider in providers {
            guard provider.hasItemConformingToTypeIdentifier(fileURLId) else { continue }
            group.enter()
            provider.loadItem(forTypeIdentifier: fileURLId, options: nil) { item, _ in
                defer { group.leave() }
                var url: URL?
                if let data = item as? Data {
                    url = URL(dataRepresentation: data, relativeTo: nil)
                } else if let direct = item as? URL {
                    url = direct
                }
                if let url {
                    lock.lock()
                    urls.append(url)
                    lock.unlock()
                }
            }
        }
        group.notify(queue: .main) { completion(urls) }
    }
}
