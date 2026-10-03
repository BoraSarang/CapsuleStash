import AppKit
import Foundation
import WebKit

/// 헤드리스 WKWebView 캡처 (T-09). 화면 없이 URL을 읽어 .webarchive + PDF Data를 만든다.
/// 반드시 메인 스레드에서 호출한다 (WKWebView 제약).
@MainActor
final class WebCaptureService: NSObject {
    /// 캡처 제한 시간 (네트워크 무응답 대비).
    static let timeoutSeconds: UInt64 = 30

    private var webView: WKWebView?
    private var navigationContinuation: CheckedContinuation<Void, Error>?

    /// URL을 읽어 웹아카이브 + PDF + 썸네일을 반환한다. 썸네일이 없으면 nil (본 저장은 진행).
    static func capture(url: URL) async throws -> (webarchive: Data, pdf: Data, thumbnail: Data?) {
        try await withThrowingTaskGroup(of: (Data, Data, Data?).self) { group in
            group.addTask { @MainActor in
                let service = WebCaptureService()
                return try await service.run(url: url)
            }
            group.addTask {
                try await Task.sleep(nanoseconds: timeoutSeconds * 1_000_000_000)
                throw CapsuleError.store(code: ErrorCode.webArchive, message: "캡처 시간 초과")
            }
            guard let result = try await group.next() else {
                throw CapsuleError.store(code: ErrorCode.webArchive, message: "캡처 실패")
            }
            group.cancelAll()
            return result
        }
    }

    private func run(url: URL) async throws -> (Data, Data, Data?) {
        let webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 1280, height: 800))
        self.webView = webView
        webView.navigationDelegate = self
        webView.load(URLRequest(url: url))
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            self.navigationContinuation = continuation
        }
        self.webView = nil

        async let archive: Data = withCheckedThrowingContinuation { continuation in
            webView.createWebArchiveData { result in
                switch result {
                case .success(let data): continuation.resume(returning: data)
                case .failure(let error): continuation.resume(throwing: error)
                }
            }
        }
        async let pdf: Data = withCheckedThrowingContinuation { continuation in
            webView.createPDF { result in
                switch result {
                case .success(let data): continuation.resume(returning: data)
                case .failure(let error): continuation.resume(throwing: error)
                }
            }
        }
        // T-28 저장 시점 스크린샷 (카드 썸네일용, 480px). 실패해도 본 저장은 진행.
        let thumbnail: Data? = await withCheckedContinuation { continuation in
            let config = WKSnapshotConfiguration()
            config.snapshotWidth = 480
            webView.takeSnapshot(with: config) { image, _ in
                guard let image,
                      let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
                    continuation.resume(returning: nil)
                    return
                }
                let png = NSBitmapImageRep(cgImage: cgImage)
                    .representation(using: .png, properties: [:])
                continuation.resume(returning: png)
            }
        }
        return try await (archive, pdf, thumbnail)
    }
}

// MARK: - WKNavigationDelegate

extension WebCaptureService: WKNavigationDelegate {
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        navigationContinuation?.resume()
        navigationContinuation = nil
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        navigationContinuation?.resume(throwing: error)
        navigationContinuation = nil
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        navigationContinuation?.resume(throwing: error)
        navigationContinuation = nil
    }
}
