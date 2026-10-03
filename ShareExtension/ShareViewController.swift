import AppKit
import UniformTypeIdentifiers

/// T-48 Share 확장 본체. 선택 텍스트·URL을 수신함 파일로 떨구고 본체가 편입한다.
/// App Group(유료 팀 프로비저닝) 없이는 본체와 파일을 못 나누므로 안내만 띄운다.
final class ShareViewController: NSViewController {
    private var foundText = ""
    private var foundURL: String?
    private let statusLabel = NSTextField(labelWithString: "")

    override func loadView() {
        let view = NSView(frame: NSRect(x: 0, y: 0, width: 320, height: 140))
        statusLabel.frame = NSRect(x: 20, y: 70, width: 280, height: 40)
        statusLabel.lineBreakMode = .byWordWrapping
        view.addSubview(statusLabel)

        let saveButton = NSButton(title: "Capsule Stash에 저장", target: self, action: #selector(save))
        saveButton.frame = NSRect(x: 20, y: 20, width: 170, height: 28)
        saveButton.bezelStyle = .rounded
        saveButton.keyEquivalent = "\r"
        view.addSubview(saveButton)

        let cancelButton = NSButton(title: "취소", target: self, action: #selector(cancel))
        cancelButton.frame = NSRect(x: 200, y: 20, width: 100, height: 28)
        cancelButton.bezelStyle = .rounded
        view.addSubview(cancelButton)
        self.view = view
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        extractInput()
    }

    private func extractInput() {
        guard let item = extensionContext?.inputItems.first as? NSExtensionItem else {
            statusLabel.stringValue = "공유 내용을 읽지 못했습니다."
            return
        }
        let group = DispatchGroup()
        for provider in item.attachments ?? [] {
            if provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) {
                group.enter()
                provider.loadItem(forTypeIdentifier: UTType.plainText.identifier) { [weak self] data, _ in
                    defer { group.leave() }
                    if let text = data as? String, !text.isEmpty {
                        self?.foundText = text
                    } else if let data = data as? Data, let text = String(data: data, encoding: .utf8) {
                        self?.foundText = text
                    }
                }
            } else if provider.hasItemConformingToTypeIdentifier(UTType.url.identifier) {
                group.enter()
                provider.loadItem(forTypeIdentifier: UTType.url.identifier) { [weak self] data, _ in
                    defer { group.leave() }
                    if let url = data as? URL {
                        self?.foundURL = url.absoluteString
                    } else if let text = data as? String {
                        self?.foundURL = text
                    }
                }
            }
        }
        group.notify(queue: .main) { [weak self] in
            guard let self else { return }
            if self.foundText.isEmpty, let url = self.foundURL {
                self.statusLabel.stringValue = url
            } else if self.foundText.isEmpty, self.foundURL == nil {
                self.statusLabel.stringValue = "저장할 텍스트·URL이 없습니다."
            } else {
                self.statusLabel.stringValue = String(self.foundText.prefix(120))
            }
        }
    }

    @objc private func save() {
        guard !foundText.isEmpty || foundURL != nil else {
            cancel()
            return
        }
        guard InboxDrop.isShared else {
            statusLabel.stringValue = "App Group 설정 전이라 저장이 안 됩니다. 본체 앱에서 직접 저장하세요."
            return
        }
        do {
            try InboxDrop.save(text: foundText, url: foundURL, source: "Share 확장")
            extensionContext?.completeRequest(returningItems: nil)
        } catch {
            statusLabel.stringValue = "저장 실패. 다시 시도하세요."
        }
    }

    @objc private func cancel() {
        extensionContext?.cancelRequest(withError: NSError(domain: "CapsuleStash", code: 0))
    }
}
