import AppKit
import Quartz

/// QuickLook 미리보기 (T-32). 이미지 더블클릭 → 시스템 미리보기 패널.
/// [HARD] paths are user data — log file name only, never contents.
final class QuickLookController: NSObject, QLPreviewPanelDataSource, QLPreviewPanelDelegate {
    static let shared = QuickLookController()

    private var urls: [URL] = []
    private var startIndex: Int = 0

    /// 미리보기 패널을 연다. 이미 열려 있으면 그 파일로 갱신.
    func show(urls: [URL], index: Int = 0) {
        guard !urls.isEmpty else { return }
        self.urls = urls
        self.startIndex = min(max(index, 0), urls.count - 1)
        guard let panel = QLPreviewPanel.shared() else { return }
        panel.dataSource = self
        panel.delegate = self
        panel.reloadData()
        panel.makeKeyAndOrderFront(nil)
        DebugLogger.feature("QuickLook 미리보기: \(urls.count)개")
    }

    // MARK: - QLPreviewPanelDataSource

    func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int {
        urls.count
    }

    func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> QLPreviewItem! {
        urls[index] as NSURL
    }

    // MARK: - QLPreviewPanelDelegate

    func previewPanel(_ panel: QLPreviewPanel!, handle event: NSEvent!) -> Bool {
        false
    }
}
