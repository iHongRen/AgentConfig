//
//  AgentProfileCodeEditor.swift
//  AgentConfig
//

import SwiftUI
import AppKit

enum AgentProfileEditorSizing {
    static let minimumHeight: CGFloat = 118
    static let fallbackHeight: CGFloat = 150
    static let maximumDefaultHeight: CGFloat = 460
    static let maximumCustomHeight: CGFloat = 900
    static let resizeCursorHotZoneHeight: CGFloat = 14

    static func clampedDefaultHeight(_ height: CGFloat) -> CGFloat {
        min(max(height, minimumHeight), maximumDefaultHeight)
    }

    static func clampedCustomHeight(_ height: CGFloat) -> CGFloat {
        min(max(height, minimumHeight), maximumCustomHeight)
    }

    static func defaultHeight(for field: AgentProfileEditorField) -> CGFloat {
        clampedDefaultHeight(field.defaultHeight)
    }

    static func defaultHeight(for field: AgentProfileEditorField, measuredHeight: CGFloat) -> CGFloat {
        max(defaultHeight(for: field), clampedDefaultHeight(measuredHeight))
    }
}

struct AgentProfileCodeEditor: NSViewRepresentable {

    @Binding var text: String
    @Binding var measuredHeight: CGFloat
    let fileType: FileType
    let isDarkMode: Bool
    let shouldMeasureHeight: Bool
    let currentHeight: CGFloat
    let onResizeStart: () -> Void
    let onResize: (CGFloat) -> Void
    let onResizeEnd: () -> Void

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: AgentProfileCodeEditor
        var highlighter: SyntaxHighlighter?
        var isUpdatingFromSwiftUI = false
        var isComposingMarkedText = false
        var lastHighlightedFileType: FileType?
        var lastHighlightedIsDarkMode: Bool?
        var lastMeasuredTextHash: Int?
        var pendingHighlightTask: Task<Void, Never>?

        init(_ parent: AgentProfileCodeEditor) {
            self.parent = parent
        }

        deinit {
            pendingHighlightTask?.cancel()
        }

        func textDidChange(_ notification: Notification) {
            guard !isUpdatingFromSwiftUI,
                  let textView = notification.object as? NSTextView else { return }

            if textView.hasMarkedText() {
                isComposingMarkedText = true
                scheduleHeightMeasurement(for: textView)
                return
            }

            isComposingMarkedText = false

            if parent.text != textView.string {
                parent.text = textView.string
            }

            scheduleHighlighting(for: textView)
            scheduleHeightMeasurement(for: textView)
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }

            if isComposingMarkedText && !textView.hasMarkedText() {
                isComposingMarkedText = false
                if parent.text != textView.string {
                    parent.text = textView.string
                }
                scheduleHighlighting(for: textView)
                scheduleHeightMeasurement(for: textView)
            }
        }

        func scheduleHighlighting(for textView: NSTextView) {
            pendingHighlightTask?.cancel()
            pendingHighlightTask = Task { [weak self, weak textView] in
                await Task.yield()
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    guard let self, let textView else { return }
                    self.applyHighlightingPreservingSelection(in: textView)
                }
            }
        }

        func applyHighlightingPreservingSelection(in textView: NSTextView) {
            guard !textView.hasMarkedText(), let storage = textView.textStorage else { return }

            let selectedRanges = textView.selectedRanges
            let length = storage.length

            storage.beginEditing()
            highlighter?.applyHighlighting(to: storage)
            storage.endEditing()

            textView.selectedRanges = selectedRanges.map { value in
                let range = value.rangeValue
                let location = min(range.location, length)
                let end = min(range.location + range.length, length)
                return NSValue(range: NSRange(location: location, length: end - location))
            }
        }

        func scheduleHeightMeasurement(for textView: NSTextView) {
            guard parent.shouldMeasureHeight else { return }

            let textHash = textView.string.hashValue
            guard lastMeasuredTextHash != textHash else { return }

            lastMeasuredTextHash = textHash

            DispatchQueue.main.async { [weak self, weak textView] in
                guard let self, let textView else { return }
                self.measureHeight(for: textView)
            }
        }

        private func measureHeight(for textView: NSTextView) {
            guard let layoutManager = textView.layoutManager,
                  let textContainer = textView.textContainer else { return }

            layoutManager.ensureLayout(for: textContainer)
            let usedRect = layoutManager.usedRect(for: textContainer)
            let verticalInset = textView.textContainerInset.height * 2
            let naturalHeight = ceil(usedRect.height + verticalInset + 10)
            let clampedHeight = AgentProfileEditorSizing.clampedDefaultHeight(naturalHeight)

            if abs(parent.measuredHeight - clampedHeight) > 1 {
                parent.measuredHeight = clampedHeight
            }
        }
    }

    final class ResizableTextView: CommentingTextView {
        var currentHeight: CGFloat = AgentProfileEditorSizing.fallbackHeight
        var onResizeStart: (() -> Void)?
        var onResize: ((CGFloat) -> Void)?
        var onResizeEnd: (() -> Void)?

        private var trackingArea: NSTrackingArea?
        private var startHeight: CGFloat?
        private var startMouseY: CGFloat?

        override init(frame frameRect: NSRect) {
            super.init(frame: frameRect)
            configureResizeTracking()
        }

        override init(frame frameRect: NSRect, textContainer container: NSTextContainer?) {
            super.init(frame: frameRect, textContainer: container)
            configureResizeTracking()
        }

        private func configureResizeTracking() {
            postsFrameChangedNotifications = true
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(viewFrameDidChange),
                name: NSView.frameDidChangeNotification,
                object: self
            )
        }

        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        override func updateTrackingAreas() {
            super.updateTrackingAreas()

            if let trackingArea {
                removeTrackingArea(trackingArea)
            }

            let area = NSTrackingArea(
                rect: .zero,
                options: [.mouseEnteredAndExited, .mouseMoved, .cursorUpdate, .activeAlways, .inVisibleRect],
                owner: self,
                userInfo: nil
            )
            addTrackingArea(area)
            trackingArea = area
        }

        override func resetCursorRects() {
            super.resetCursorRects()
            addCursorRect(visibleResizeHotZone, cursor: .resizeUpDown)
        }

        override func cursorUpdate(with event: NSEvent) {
            if isInResizeHotZone(event) {
                NSCursor.resizeUpDown.set()
            } else {
                super.cursorUpdate(with: event)
            }
        }

        override func mouseMoved(with event: NSEvent) {
            if isInResizeHotZone(event) {
                NSCursor.resizeUpDown.set()
            } else {
                super.mouseMoved(with: event)
            }
        }

        override func mouseEntered(with event: NSEvent) {
            if isInResizeHotZone(event) {
                NSCursor.resizeUpDown.set()
            } else {
                super.mouseEntered(with: event)
            }
        }

        override func mouseDown(with event: NSEvent) {
            guard isInResizeHotZone(event) else {
                super.mouseDown(with: event)
                return
            }

            window?.makeFirstResponder(self)
            NSCursor.resizeUpDown.set()
            startHeight = currentHeight
            startMouseY = event.locationInWindow.y
            onResizeStart?()
        }

        override func mouseDragged(with event: NSEvent) {
            guard let startHeight, let startMouseY else {
                super.mouseDragged(with: event)
                return
            }

            NSCursor.resizeUpDown.set()
            let delta = startMouseY - event.locationInWindow.y
            onResize?(AgentProfileEditorSizing.clampedCustomHeight(startHeight + delta))
        }

        override func mouseUp(with event: NSEvent) {
            guard startHeight != nil else {
                super.mouseUp(with: event)
                return
            }

            startHeight = nil
            startMouseY = nil
            if isInResizeHotZone(event) {
                NSCursor.resizeUpDown.set()
            }
            onResizeEnd?()
        }

        private var visibleResizeHotZone: NSRect {
            let visibleRect = visibleEditorRect
            let hotZoneHeight = min(AgentProfileEditorSizing.resizeCursorHotZoneHeight, visibleRect.height)
            let y = isFlipped ? visibleRect.maxY - hotZoneHeight : visibleRect.minY
            return NSRect(
                x: visibleRect.minX,
                y: y,
                width: visibleRect.width,
                height: hotZoneHeight
            )
        }

        private var visibleEditorRect: NSRect {
            guard let clipView = enclosingScrollView?.contentView else {
                return visibleRect
            }
            return convert(clipView.bounds, from: clipView)
        }

        private func isInResizeHotZone(_ event: NSEvent) -> Bool {
            let localPoint = convert(event.locationInWindow, from: nil)
            return visibleResizeHotZone.contains(localPoint)
        }

        @objc private func viewFrameDidChange() {
            updateTrackingAreas()
            window?.invalidateCursorRects(for: self)
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = true
        scrollView.backgroundColor = editorBackgroundColor

        let textView = ResizableTextView(frame: NSRect(x: 0, y: 0, width: 100, height: 100))
        textView.currentHeight = currentHeight
        textView.onResizeStart = onResizeStart
        textView.onResize = onResize
        textView.onResizeEnd = onResizeEnd
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(
            width: CGFloat.greatestFiniteMagnitude,
            height: CGFloat.greatestFiniteMagnitude
        )
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.lineBreakMode = .byCharWrapping
        textView.textContainer?.containerSize = NSSize(
            width: CGFloat.greatestFiniteMagnitude,
            height: CGFloat.greatestFiniteMagnitude
        )
        textView.font = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
        textView.backgroundColor = editorBackgroundColor
        textView.drawsBackground = true
        textView.textColor = editorTextColor
        textView.insertionPointColor = editorTextColor
        textView.textContainerInset = NSSize(width: 13, height: 11)
        textView.isEditable = true
        textView.isSelectable = true
        textView.allowsUndo = true
        textView.isRichText = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isGrammarCheckingEnabled = false
        textView.isContinuousSpellCheckingEnabled = false
        textView.commentFileType = fileType
        textView.delegate = context.coordinator

        scrollView.documentView = textView

        context.coordinator.highlighter = SyntaxHighlighter(fileType: fileType, isDarkMode: isDarkMode)
        textView.textStorage?.delegate = context.coordinator.highlighter
        textView.string = text
        textView.textStorage?.delegate = context.coordinator.highlighter
        textView.typingAttributes = typingAttributes

        if let storage = textView.textStorage, storage.length > 0 {
            storage.beginEditing()
            context.coordinator.highlighter?.applyHighlighting(to: storage)
            storage.endEditing()
        }

        context.coordinator.lastHighlightedFileType = fileType
        context.coordinator.lastHighlightedIsDarkMode = isDarkMode
        context.coordinator.scheduleHeightMeasurement(for: textView)

        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? ResizableTextView else { return }

        context.coordinator.parent = self
        textView.currentHeight = currentHeight
        textView.onResizeStart = onResizeStart
        textView.onResize = onResize
        textView.onResizeEnd = onResizeEnd
        textView.commentFileType = fileType

        let isComposingMarkedText = textView.hasMarkedText() || context.coordinator.isComposingMarkedText
        let contentChanged = !isComposingMarkedText
            && !context.coordinator.isUpdatingFromSwiftUI
            && textView.string != text
        let fileTypeChanged = context.coordinator.lastHighlightedFileType != fileType
        let darkModeChanged = context.coordinator.lastHighlightedIsDarkMode != isDarkMode

        if context.coordinator.highlighter == nil {
            context.coordinator.highlighter = SyntaxHighlighter(fileType: fileType, isDarkMode: isDarkMode)
            textView.textStorage?.delegate = context.coordinator.highlighter
        }

        context.coordinator.highlighter?.fileType = fileType
        context.coordinator.highlighter?.isDarkMode = isDarkMode

        if contentChanged {
            context.coordinator.isUpdatingFromSwiftUI = true
            let selectedRanges = textView.selectedRanges

            textView.string = text
            textView.textStorage?.delegate = context.coordinator.highlighter
            textView.typingAttributes = typingAttributes

            let length = (text as NSString).length
            textView.selectedRanges = selectedRanges.map { value in
                let range = value.rangeValue
                let location = min(range.location, length)
                let end = min(range.location + range.length, length)
                return NSValue(range: NSRange(location: location, length: end - location))
            }
            context.coordinator.isUpdatingFromSwiftUI = false
        }

        textView.backgroundColor = editorBackgroundColor
        textView.insertionPointColor = editorTextColor
        textView.typingAttributes = typingAttributes
        scrollView.backgroundColor = editorBackgroundColor

        if !isComposingMarkedText && (contentChanged || fileTypeChanged || darkModeChanged) {
            context.coordinator.applyHighlightingPreservingSelection(in: textView)
            context.coordinator.lastHighlightedFileType = fileType
            context.coordinator.lastHighlightedIsDarkMode = isDarkMode
        }

        if context.coordinator.lastHighlightedFileType == nil {
            context.coordinator.lastHighlightedFileType = fileType
        }
        if context.coordinator.lastHighlightedIsDarkMode == nil {
            context.coordinator.lastHighlightedIsDarkMode = isDarkMode
        }

        context.coordinator.scheduleHeightMeasurement(for: textView)
    }

    private var typingAttributes: [NSAttributedString.Key: Any] {
        [
            .font: NSFont.monospacedSystemFont(ofSize: 13, weight: .regular),
            .foregroundColor: editorTextColor
        ]
    }

    private var editorBackgroundColor: NSColor {
        NSColor.textBackgroundColor
    }

    private var editorTextColor: NSColor {
        isDarkMode ? NSColor(white: 0.92, alpha: 1) : NSColor(white: 0.10, alpha: 1)
    }
}
