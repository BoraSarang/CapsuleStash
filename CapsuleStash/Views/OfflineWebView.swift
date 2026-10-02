import SwiftUI
import WebKit

/// 로컬 실파일(.webarchive/.pdf) 오프라인 뷰어.
/// AppKit `WKWebView` 를 SwiftUI 시트에 올린다.
struct OfflineWebView: NSViewRepresentable {
    let fileURL: URL

    func makeNSView(context: Context) -> WKWebView {
        let webView = WKWebView()
        webView.loadFileURL(fileURL, allowingReadAccessTo: fileURL.deletingLastPathComponent())
        return webView
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {}
}
