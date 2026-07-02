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

    let fieldID: String
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
        var searchRanges: [NSRange] = []
        var currentSearchIndex: Int = 0
        var currentSearchQuery: String = ""
        var isSearchCaseSensitive = false
        var searchObservers: [NSObjectProtocol] = []

        init(_ parent: AgentProfileCodeEditor) {
            self.parent = parent
            super.init()
            subscribeToSearchNotifications()
        }

        deinit {
            pendingHighlightTask?.cancel()
            for observer in searchObservers {
                NotificationCenter.default.removeObserver(observer)
            }
        }

        private func subscribeToSearchNotifications() {
            let center = NotificationCenter.default

            searchObservers.append(
                center.addObserver(forName: .agentProfileSearchQueryChanged, object: nil, queue: .main) { [weak self] notification in
                    guard let self,
                          let payload = notification.object as? AgentProfileSearchUpdate,
                          payload.fieldID == self.parent.fieldID,
                          let textView = self.currentTextView else { return }
                    self.updateSearch(query: payload.query, caseSensitive: payload.isCaseSensitive, in: textView)
                }
            )

            searchObservers.append(
                center.addObserver(forName: .agentProfileSearchNextRequested, object: nil, queue: .main) { [weak self] notification in
                    guard let self,
                          let targetFieldID = notification.object as? String,
                          targetFieldID == self.parent.fieldID,
                          let textView = self.currentTextView else { return }
                    self.selectNextMatch(in: textView)
                }
            )

            searchObservers.append(
                center.addObserver(forName: .agentProfileSearchPreviousRequested, object: nil, queue: .main) { [weak self] notification in
                    guard let self,
                          let targetFieldID = notification.object as? String,
                          targetFieldID == self.parent.fieldID,
                          let textView = self.currentTextView else { return }
                    self.selectPreviousMatch(in: textView)
                }
            )
        }

        weak var currentTextView: NSTextView?

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
            updateSearch(query: currentSearchQuery, caseSensitive: isSearchCaseSensitive, in: textView)
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

            applySearchHighlights(in: textView)
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

        func updateSearch(query: String, caseSensitive: Bool, in textView: NSTextView) {
            currentSearchQuery = query
            isSearchCaseSensitive = caseSensitive
            searchRanges = Self.searchRanges(in: textView.string, query: query, caseSensitive: caseSensitive)
            currentSearchIndex = searchRanges.isEmpty ? 0 : min(currentSearchIndex, searchRanges.count - 1)
            applySearchHighlights(in: textView)
        }

        func selectNextMatch(in textView: NSTextView) {
            guard !searchRanges.isEmpty else { return }
            currentSearchIndex = (currentSearchIndex + 1) % searchRanges.count
            applySearchHighlights(in: textView)
            scrollCurrentMatchIntoView(in: textView)
        }

        func selectPreviousMatch(in textView: NSTextView) {
            guard !searchRanges.isEmpty else { return }
            currentSearchIndex = (currentSearchIndex - 1 + searchRanges.count) % searchRanges.count
            applySearchHighlights(in: textView)
            scrollCurrentMatchIntoView(in: textView)
        }

        func scrollCurrentMatchIntoView(in textView: NSTextView) {
            guard currentSearchIndex < searchRanges.count else { return }
            let range = searchRanges[currentSearchIndex]
            textView.scrollRangeToVisible(range)
            textView.setSelectedRange(range)
        }

        private func applySearchHighlights(in textView: NSTextView) {
            guard let storage = textView.textStorage else { return }

            let fullRange = NSRange(location: 0, length: storage.length)
            storage.removeAttribute(.backgroundColor, range: fullRange)
            highlighter?.applyHighlighting(to: storage)

            guard !searchRanges.isEmpty else { return }

            let allMatchColor = NSColor.systemYellow.withAlphaComponent(parent.isDarkMode ? 0.22 : 0.18)
            let currentMatchColor = NSColor.systemOrange.withAlphaComponent(parent.isDarkMode ? 0.32 : 0.24)

            for (index, range) in searchRanges.enumerated() where NSMaxRange(range) <= storage.length {
                storage.addAttribute(.backgroundColor, value: index == currentSearchIndex ? currentMatchColor : allMatchColor, range: range)
            }
        }

        private static func searchRanges(in text: String, query: String, caseSensitive: Bool) -> [NSRange] {
            let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedQuery.isEmpty else { return [] }

            let nsText = text as NSString
            let textLength = nsText.length
            var options: NSString.CompareOptions = [.literal]
            if !caseSensitive {
                options.insert(.caseInsensitive)
            }

            var results: [NSRange] = []
            var searchRange = NSRange(location: 0, length: textLength)

            while searchRange.location < textLength {
                let found = nsText.range(of: trimmedQuery, options: options, range: searchRange)
                guard found.location != NSNotFound else { break }
                results.append(found)
                let nextLocation = found.location + found.length
                searchRange = NSRange(location: nextLocation, length: textLength - nextLocation)
            }

            return results
        }
    }

    final class ResizableTextView: CommentingTextView {
        var currentHeight: CGFloat = AgentProfileEditorSizing.fallbackHeight
        var onResizeStart: (() -> Void)?
        var onResize: ((CGFloat) -> Void)?
        var onResizeEnd: (() -> Void)?
        var onFindRequested: (() -> Void)?

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

        override func performKeyEquivalent(with event: NSEvent) -> Bool {
            if event.type == .keyDown,
               event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command,
               event.charactersIgnoringModifiers?.lowercased() == "f" {
                onFindRequested?()
                return true
            }

            return super.performKeyEquivalent(with: event)
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
        context.coordinator.currentTextView = textView
        textView.currentHeight = currentHeight
        textView.onResizeStart = onResizeStart
        textView.onResize = onResize
        textView.onResizeEnd = onResizeEnd
        textView.onFindRequested = {
            NotificationCenter.default.post(name: .agentProfileSearchFocusRequested, object: fieldID)
        }
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
        context.coordinator.currentTextView = textView
        textView.currentHeight = currentHeight
        textView.onResizeStart = onResizeStart
        textView.onResize = onResize
        textView.onResizeEnd = onResizeEnd
        textView.onFindRequested = {
            NotificationCenter.default.post(name: .agentProfileSearchFocusRequested, object: fieldID)
        }
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

        context.coordinator.updateSearch(
            query: context.coordinator.currentSearchQuery,
            caseSensitive: context.coordinator.isSearchCaseSensitive,
            in: textView
        )

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

struct AgentProfileCodeEditorContainer: View {
    let fieldID: String
    @Binding var text: String
    @Binding var measuredHeight: CGFloat
    let fileType: FileType
    let isDarkMode: Bool
    let shouldMeasureHeight: Bool
    let currentHeight: CGFloat
    let onResizeStart: () -> Void
    let onResize: (CGFloat) -> Void
    let onResizeEnd: () -> Void

    @State private var isSearchVisible = false
    @State private var searchQuery = ""
    @State private var isCaseSensitive = false

    var body: some View {
        VStack(spacing: 0) {
            if isSearchVisible {
                agentProfileSearchBar
            }

            AgentProfileCodeEditor(
                fieldID: fieldID,
                text: $text,
                measuredHeight: $measuredHeight,
                fileType: fileType,
                isDarkMode: isDarkMode,
                shouldMeasureHeight: shouldMeasureHeight,
                currentHeight: currentHeight,
                onResizeStart: onResizeStart,
                onResize: onResize,
                onResizeEnd: onResizeEnd
            )
            .frame(height: currentHeight)
            .background(Color(nsColor: .textBackgroundColor))
        }
    }

    private var agentProfileSearchBar: some View {
        AgentProfileInlineSearchBar(
            fieldID: fieldID,
            query: $searchQuery,
            isCaseSensitive: $isCaseSensitive,
            isVisible: $isSearchVisible
        )
        .background(Color(nsColor: .windowBackgroundColor))
        .overlay(Divider(), alignment: .bottom)
    }
}

private struct AgentProfileInlineSearchBar: View {
    let fieldID: String
    @Binding var query: String
    @Binding var isCaseSensitive: Bool
    @Binding var isVisible: Bool

    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)

            TextField(L10n.tr("search.placeholder", value: "Search"), text: $query)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .focused($isFocused)
                .onChange(of: query) { _, newValue in
                    NotificationCenter.default.post(
                        name: .agentProfileSearchQueryChanged,
                        object: AgentProfileSearchUpdate(fieldID: fieldID, query: newValue, isCaseSensitive: isCaseSensitive)
                    )
                }
                .onChange(of: isCaseSensitive) { _, newValue in
                    NotificationCenter.default.post(
                        name: .agentProfileSearchQueryChanged,
                        object: AgentProfileSearchUpdate(fieldID: fieldID, query: query, isCaseSensitive: newValue)
                    )
                }

            Button {
                isCaseSensitive.toggle()
            } label: {
                Text("Aa")
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundStyle(isCaseSensitive ? Color.accentColor : .secondary)
                    .frame(width: 24, height: 20)
            }
            .buttonStyle(.plain)
            .help(L10n.tr("search.caseSensitive", value: "Match Case (⌥⌘C)"))

            Button {
                NotificationCenter.default.post(name: .agentProfileSearchPreviousRequested, object: fieldID)
            } label: {
                Image(systemName: "chevron.up")
                    .font(.system(size: 11, weight: .semibold))
            }
            .buttonStyle(.plain)

            Button {
                NotificationCenter.default.post(name: .agentProfileSearchNextRequested, object: fieldID)
            } label: {
                Image(systemName: "chevron.down")
                    .font(.system(size: 11, weight: .semibold))
            }
            .buttonStyle(.plain)

            Button {
                query = ""
                NotificationCenter.default.post(
                    name: .agentProfileSearchQueryChanged,
                    object: AgentProfileSearchUpdate(fieldID: fieldID, query: "", isCaseSensitive: isCaseSensitive)
                )
                isVisible = false
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .medium))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 10)
        .frame(height: 34)
        .onAppear {
            isFocused = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .agentProfileSearchFocusRequested)) { notification in
            guard let targetFieldID = notification.object as? String, targetFieldID == fieldID else { return }
            isVisible = true
            isFocused = true
        }
    }
}

private struct AgentProfileSearchUpdate {
    let fieldID: String
    let query: String
    let isCaseSensitive: Bool
}

private extension Notification.Name {
    static let agentProfileSearchFocusRequested = Notification.Name("AgentProfileCodeEditor.searchFocusRequested")
    static let agentProfileSearchQueryChanged = Notification.Name("AgentProfileCodeEditor.searchQueryChanged")
    static let agentProfileSearchNextRequested = Notification.Name("AgentProfileCodeEditor.searchNextRequested")
    static let agentProfileSearchPreviousRequested = Notification.Name("AgentProfileCodeEditor.searchPreviousRequested")
}
