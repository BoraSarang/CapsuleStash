import AppKit
import SwiftUI

/// 블록 본문 인라인 편집기 (T-13). AppKit `NSTextView` 기반 —
/// SwiftUI TextEditor엔 커서 위치 API가 없어 Tab 삽입이 안 되기 때문이다.
/// - 코드·셸: 줄번호 룰러 + 모노 + Tab→공백 2개
/// - 텍스트·마크다운: 룰러 없음 + 시스템 폰트
/// - `⌘Enter` 저장, `esc` 취소
struct BlockTextEditor: NSViewRepresentable {
    @Binding var text: String
    var font: NSFont
    var textColor: NSColor
    var backgroundColor: NSColor
    var showLineNumbers: Bool
    var onSave: () -> Void
    var onCancel: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false

        let textView = BlockTextView()
        textView.delegate = context.coordinator
        textView.onSave = onSave
        textView.onCancel = onCancel
        textView.font = font
        textView.textColor = textColor
        textView.backgroundColor = backgroundColor
        textView.isRichText = false
        textView.allowsUndo = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize = NSSize(width: scrollView.contentSize.width, height: .greatestFiniteMagnitude)
        textView.string = text

        scrollView.documentView = textView
        context.coordinator.textView = textView

        if showLineNumbers {
            let ruler = LineNumberRulerView(textView: textView)
            scrollView.verticalRulerView = ruler
            scrollView.hasVerticalRuler = true
            scrollView.rulersVisible = true
        }
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? BlockTextView else { return }
        textView.onSave = onSave
        textView.onCancel = onCancel
        if textView.string != text {
            textView.string = text
        }
        textView.font = font
        textView.textColor = textColor
        textView.backgroundColor = backgroundColor
        // 첫 표시 시 포커스 (make 시점엔 window가 없을 수 있어 여기서 시도)
        if !context.coordinator.didFocus, let window = scrollView.window {
            window.makeFirstResponder(textView)
            context.coordinator.didFocus = true
        }
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: BlockTextEditor
        weak var textView: BlockTextView?
        var didFocus = false

        init(parent: BlockTextEditor) {
            self.parent = parent
        }

        func textDidChange(_ notification: Notification) {
            guard let textView else { return }
            parent.text = textView.string
            (textView.enclosingScrollView?.verticalRulerView as? LineNumberRulerView)?.needsDisplay = true
        }
    }
}

// MARK: - 키 처리용 NSTextView

final class BlockTextView: NSTextView {
    var onSave: (() -> Void)?
    var onCancel: (() -> Void)?

    override func doCommand(by selector: Selector) {
        if selector == #selector(insertTab(_:)) {
            // Tab → 공백 2개 (포커스 이동 대신 코드 들여쓰기)
            insertText("  ", replacementRange: selectedRange())
            return
        }
        if selector == #selector(insertNewline(_:)),
           NSEvent.modifierFlags.contains(.command) {
            onSave?()
            return
        }
        if selector == #selector(cancelOperation(_:)) {
            onCancel?()
            return
        }
        super.doCommand(by: selector)
    }
}

// MARK: - 줄번호 룰러

final class LineNumberRulerView: NSRulerView {
    init(textView: NSTextView) {
        super.init(scrollView: textView.enclosingScrollView, orientation: .verticalRuler)
        ruleThickness = 34
    }

    @available(*, unavailable)
    required init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func drawHashMarksAndLabels(in rect: NSRect) {
        guard let textView = clientView as? NSTextView,
              let layoutManager = textView.layoutManager,
              let textContainer = textView.textContainer else {
            super.drawHashMarksAndLabels(in: rect)
            return
        }
        let visibleRect = scrollView?.contentView.bounds ?? bounds
        let glyphRange = layoutManager.glyphRange(forBoundingRect: visibleRect, in: textContainer)
        let nsText = textView.string as NSString
        let prefix = nsText.substring(to: min(glyphRange.location, nsText.length))
        // 접두사의 줄바꿈 수 + 1 = 첫 가시 줄 번호
        var lineNumber = prefix.components(separatedBy: "\n").count

        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 11, weight: .regular),
            .foregroundColor: NSColor.secondaryLabelColor,
        ]
        layoutManager.enumerateLineFragments(forGlyphRange: glyphRange) { _, usedRect, _, _, _ in
            let label = "\(lineNumber)" as NSString
            let size = label.size(withAttributes: attributes)
            let y = usedRect.minY - visibleRect.minY + (usedRect.height - size.height) / 2
            label.draw(at: NSPoint(x: self.ruleThickness - 6 - size.width, y: y), withAttributes: attributes)
            lineNumber += 1
        }
    }
}
