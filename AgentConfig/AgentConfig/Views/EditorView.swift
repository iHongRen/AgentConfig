//
//  EditorView.swift
//  AgentConfig
//
//  Created by cxy on 2026/5/11.
//

import SwiftUI
import AppKit

// MARK: - LineNumberRulerView

final class LineNumberRulerView: NSRulerView {

    weak var textView: NSTextView?

    private let lineNumberFont = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
    private var cachedDigitCount = 2

    init(scrollView: NSScrollView, textView: NSTextView) {
        self.textView = textView
        super.init(scrollView: scrollView, orientation: .verticalRuler)
        self.clientView = textView
        self.ruleThickness = 40
        recalculateMetrics()
    }

    required init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var requiredThickness: CGFloat {
        let sample = String(repeating: "9", count: cachedDigitCount) as NSString
        let w = sample.size(withAttributes: [.font: lineNumberFont]).width
        return w + 16
    }

    override func draw(_ dirtyRect: NSRect) {
        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }

        NSBezierPath(rect: bounds).setClip()

        let isDark = textView?.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        (isDark ? NSColor.textBackgroundColor : NSColor.textBackgroundColor).setFill()
        bounds.fill()

        drawLineNumbers()
    }

    private func drawLineNumbers() {
        guard let textView = textView,
              let layoutManager = textView.layoutManager,
              let textContainer = textView.textContainer else { return }

        let visibleRect = scrollView?.contentView.bounds ?? bounds
        let containerOrigin = textView.textContainerOrigin
        let visibleTextRect = visibleRect.offsetBy(dx: -containerOrigin.x, dy: -containerOrigin.y)
        let attrs: [NSAttributedString.Key: Any] = [
            .font: lineNumberFont,
            .foregroundColor: NSColor.secondaryLabelColor
        ]

        let fullText = textView.string as NSString
        let totalLength = fullText.length
        let visibleGlyphRange = layoutManager.glyphRange(forBoundingRect: visibleTextRect, in: textContainer)
        let firstVisibleGlyphIndex = min(
            visibleGlyphRange.location,
            max(layoutManager.numberOfGlyphs - 1, 0)
        )
        let firstVisibleCharacterIndex = layoutManager.numberOfGlyphs > 0
            ? layoutManager.characterIndexForGlyph(at: firstVisibleGlyphIndex)
            : 0
        let firstLineCharacterIndex = fullText.lineRange(
            for: NSRange(location: min(firstVisibleCharacterIndex, totalLength), length: 0)
        ).location
        var lineNumber = Self.lineNumber(at: firstLineCharacterIndex, in: fullText)
        var charIndex = firstLineCharacterIndex

        while charIndex <= totalLength {
            let glyphRange = layoutManager.glyphRange(
                forCharacterRange: NSRange(location: charIndex, length: 0),
                actualCharacterRange: nil
            )
            guard glyphRange.location < layoutManager.numberOfGlyphs || (charIndex == 0 && totalLength == 0) else {
                break
            }

            var lineFragmentRect = layoutManager.lineFragmentRect(
                forGlyphAt: min(glyphRange.location, max(0, layoutManager.numberOfGlyphs - 1)),
                effectiveRange: nil
            )
            lineFragmentRect.origin.y += containerOrigin.y

            if lineFragmentRect.minY > visibleRect.maxY { break }

            if lineFragmentRect.maxY >= visibleRect.minY {
                let label = "\(lineNumber)" as NSString
                let labelSize = label.size(withAttributes: attrs)
                let drawY = lineFragmentRect.minY - visibleRect.minY
                    + (lineFragmentRect.height - labelSize.height) / 2
                let drawRect = NSRect(
                    x: bounds.width - labelSize.width - 6,
                    y: drawY,
                    width: labelSize.width,
                    height: labelSize.height
                )
                label.draw(in: drawRect, withAttributes: attrs)
            }

            if charIndex >= totalLength { break }
            let nsRange = NSRange(location: charIndex, length: totalLength - charIndex)
            let newlineRange = fullText.range(of: "\n", range: nsRange)
            if newlineRange.location == NSNotFound { break }
            charIndex = newlineRange.location + 1
            lineNumber += 1
        }
    }

    func refresh(recalculateMetrics: Bool = false) {
        if recalculateMetrics {
            self.recalculateMetrics()
        }
        ruleThickness = requiredThickness
        needsDisplay = true
    }

    private func recalculateMetrics() {
        guard let text = textView?.string else {
            cachedDigitCount = 2
            return
        }

        let lineCount = Self.countLines(in: text)
        cachedDigitCount = max(2, String(lineCount).count)
    }

    private static func countLines(in text: String) -> Int {
        guard !text.isEmpty else { return 1 }

        var lineCount = 1
        for codeUnit in text.utf16 where codeUnit == 10 {
            lineCount += 1
        }
        return lineCount
    }

    private static func lineNumber(at characterIndex: Int, in text: NSString) -> Int {
        guard characterIndex > 0 else { return 1 }

        var lineNumber = 1
        var searchLocation = 0

        while searchLocation < characterIndex {
            let range = NSRange(location: searchLocation, length: characterIndex - searchLocation)
            let newlineRange = text.range(of: "\n", range: range)
            guard newlineRange.location != NSNotFound else { break }
            lineNumber += 1
            searchLocation = newlineRange.location + 1
        }

        return lineNumber
    }
}

// MARK: - CodeEditorView

struct CodeEditorView: NSViewRepresentable {

    private static let deferredHighlightCharacterThreshold = 50_000

    @Binding var text: String
    @Binding var cursorLine: Int
    @Binding var cursorColumn: Int
    var fileType: FileType
    var isDarkMode: Bool
    // 搜索高亮
    var searchResults: [NSRange]
    var currentSearchIndex: Int
    var scrollRevision: Int
    var isSearchBarVisible: Bool
    var onEscape: (() -> Bool)?

    // MARK: Coordinator

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: CodeEditorView
        var isUpdatingFromSwiftUI = false
        // 记录上次高亮时的状态，避免不必要的全量重高亮
        var lastHighlightedFileType: FileType?
        var lastHighlightedIsDarkMode: Bool?
        var highlighter: SyntaxHighlighter?
        var isComposingMarkedText = false
        var lastScrollRevision: Int = -1
        var lastSearchBarVisible: Bool = false
        var lastSearchResultsHash: Int?
        var lastCurrentSearchIndex: Int?
        var lastSearchHighlightDarkMode: Bool?
        /// 语法高亮完成后重新应用搜索背景色的回调（由 updateNSView 注入）
        var reapplySearchHighlights: ((NSTextView) -> Void)?
        var pendingHighlightTask: Task<Void, Never>?

        init(_ parent: CodeEditorView) {
            self.parent = parent
        }

        deinit {
            pendingHighlightTask?.cancel()
        }

        func textDidChange(_ notification: Notification) {
            guard !isUpdatingFromSwiftUI,
                  let tv = notification.object as? NSTextView else { return }

            if tv.hasMarkedText() {
                isComposingMarkedText = true
                updateCursorPosition(for: tv)
                refreshLineNumberRuler(for: tv)
                return
            }

            let finishedMarkedText = isComposingMarkedText
            isComposingMarkedText = false

            let newText = tv.string
            if parent.text != newText {
                parent.text = newText
            }

            updateCursorPosition(for: tv)
            scheduleHighlighting(for: tv)
            refreshLineNumberRuler(for: tv, recalculateMetrics: finishedMarkedText)
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            guard let tv = notification.object as? NSTextView else { return }

            if isComposingMarkedText && !tv.hasMarkedText() {
                isComposingMarkedText = false
                let newText = tv.string
                if parent.text != newText {
                    parent.text = newText
                }
                scheduleHighlighting(for: tv)
                refreshLineNumberRuler(for: tv, recalculateMetrics: true)
            }

            updateCursorPosition(for: tv)
        }

        func updateCursorPosition(for textView: NSTextView) {
            let selectedLocation = textView.selectedRange().location
            let safeLocation = min(selectedLocation, (textView.string as NSString).length)
            let prefix = (textView.string as NSString).substring(to: safeLocation)
            let lines = prefix.components(separatedBy: "\n")
            let line = max(lines.count, 1)
            let column = (lines.last?.count ?? 0) + 1

            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                if self.parent.cursorLine != line {
                    self.parent.cursorLine = line
                }
                if self.parent.cursorColumn != column {
                    self.parent.cursorColumn = column
                }
            }
        }

        func refreshLineNumberRuler(for textView: NSTextView, recalculateMetrics: Bool = false) {
            if let sv = textView.enclosingScrollView,
               let ruler = sv.verticalRulerView as? LineNumberRulerView {
                ruler.refresh(recalculateMetrics: recalculateMetrics)
            }
        }

        func scheduleHighlighting(for textView: NSTextView, immediate: Bool? = nil) {
            pendingHighlightTask?.cancel()

            let shouldApplyImmediately = immediate ?? !shouldDeferHighlighting(for: textView)
            if shouldApplyImmediately {
                applyHighlightingPreservingSelection(in: textView)
                return
            }

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
            guard !textView.hasMarkedText() else { return }
            guard let storage = textView.textStorage else { return }

            let ranges = textView.selectedRanges
            let length = storage.length

            storage.beginEditing()
            highlighter?.applyHighlighting(to: storage)
            storage.endEditing()

            textView.selectedRanges = ranges.map { value in
                let range = value.rangeValue
                let location = min(range.location, length)
                let end = min(range.location + range.length, length)
                return NSValue(range: NSRange(location: location, length: end - location))
            }

            updateCursorPosition(for: textView)

            // 语法高亮完成后重新应用搜索背景色
            reapplySearchHighlights?(textView)
        }

        private func shouldDeferHighlighting(for textView: NSTextView) -> Bool {
            guard let storage = textView.textStorage else { return false }

            let isLargeDocument = storage.length >= CodeEditorView.deferredHighlightCharacterThreshold
            guard isLargeDocument else { return false }

            switch parent.fileType {
            case .json, .jsonc, .json5, .jsonl:
                return true
            case .yaml, .toml, .shell, .plainText:
                return false
            }
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    // MARK: makeNSView

    func makeNSView(context: Context) -> NSScrollView {
        // 1. ScrollView
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = true
        scrollView.backgroundColor = editorBackgroundColor

        // 2. TextView — 先给一个非零 frame，之后会随 scrollView 自动调整
        let tv = CommentingTextView(frame: NSRect(x: 0, y: 0, width: 100, height: 100))

        // 3. 布局配置：垂直可伸缩，宽度跟随 scrollView
        tv.isVerticallyResizable = true
        tv.isHorizontallyResizable = false
        tv.autoresizingMask = [.width]
        tv.minSize = NSSize(width: 0, height: 0)
        tv.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude,
                            height: CGFloat.greatestFiniteMagnitude)
        tv.textContainer?.widthTracksTextView = true
        tv.textContainer?.containerSize = NSSize(
            width: CGFloat.greatestFiniteMagnitude,
            height: CGFloat.greatestFiniteMagnitude
        )

        // 4. 外观
        let textColor = isDarkMode ? NSColor(white: 0.92, alpha: 1) : NSColor(white: 0.10, alpha: 1)
        tv.font = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
        tv.backgroundColor = editorBackgroundColor
        tv.drawsBackground = true
        tv.textColor = textColor
        tv.insertionPointColor = textColor
        tv.textContainerInset = NSSize(width: 16, height: 14)

        // 5. 编辑行为
        tv.isEditable = true
        tv.isSelectable = true
        tv.allowsUndo = true
        tv.isRichText = false
        tv.isAutomaticQuoteSubstitutionEnabled = false
        tv.isAutomaticDashSubstitutionEnabled = false
        tv.isAutomaticSpellingCorrectionEnabled = false
        tv.isGrammarCheckingEnabled = false
        tv.isContinuousSpellCheckingEnabled = false
        tv.commentFileType = fileType
        tv.onEscape = onEscape

        // 6. Delegate
        tv.delegate = context.coordinator

        // 7. 装入 scrollView（必须在设置 textStorage.delegate 之前）
        scrollView.documentView = tv

        // 8. 语法高亮 — 在 documentView 设置之后再设置 delegate
        context.coordinator.highlighter = SyntaxHighlighter(fileType: fileType, isDarkMode: isDarkMode)
        tv.textStorage?.delegate = context.coordinator.highlighter

        // 9. 行号 ruler
        let ruler = LineNumberRulerView(scrollView: scrollView, textView: tv)
        scrollView.verticalRulerView = ruler
        scrollView.hasVerticalRuler = true
        scrollView.rulersVisible = true

        // 10. 设置初始内容
        // 直接用 tv.string 设置，简单可靠
        tv.string = text
        
        // tv.string= 可能会替换 textStorage 对象，导致 delegate 丢失，重新设置
        tv.textStorage?.delegate = context.coordinator.highlighter
        
        // 设置 typingAttributes，确保新输入的文字有正确颜色
        tv.typingAttributes = [
            .font: NSFont.monospacedSystemFont(ofSize: 13, weight: .regular),
            .foregroundColor: textColor
        ]

        context.coordinator.lastHighlightedFileType = fileType
        context.coordinator.lastHighlightedIsDarkMode = isDarkMode
        context.coordinator.lastSearchResultsHash = searchResultsHash(for: searchResults)
        context.coordinator.lastCurrentSearchIndex = currentSearchIndex
        context.coordinator.lastSearchHighlightDarkMode = isDarkMode
        context.coordinator.lastScrollRevision = scrollRevision
        context.coordinator.scheduleHighlighting(for: tv)

        ruler.refresh(recalculateMetrics: true)
        context.coordinator.updateCursorPosition(for: tv)

        return scrollView
    }

    // MARK: updateNSView

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let tv = scrollView.documentView as? CommentingTextView else { return }

        let textColor = isDarkMode ? NSColor(white: 0.92, alpha: 1) : NSColor(white: 0.10, alpha: 1)
        let typingAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 13, weight: .regular),
            .foregroundColor: textColor
        ]

        // 检测需要重新高亮的条件
        let fileTypeChanged = context.coordinator.lastHighlightedFileType != fileType
        let darkModeChanged = context.coordinator.lastHighlightedIsDarkMode != isDarkMode
        let isComposingMarkedText = tv.hasMarkedText() || context.coordinator.isComposingMarkedText
        let contentChanged = !isComposingMarkedText
            && !context.coordinator.isUpdatingFromSwiftUI
            && tv.string != text

        // 同步高亮器的 fileType / isDarkMode
        if context.coordinator.highlighter == nil {
            context.coordinator.highlighter = SyntaxHighlighter(fileType: fileType, isDarkMode: isDarkMode)
            tv.textStorage?.delegate = context.coordinator.highlighter
        }

        tv.commentFileType = fileType
        tv.onEscape = onEscape
        context.coordinator.highlighter?.fileType = fileType
        context.coordinator.highlighter?.isDarkMode = isDarkMode

        if contentChanged {
            context.coordinator.isUpdatingFromSwiftUI = true
            let ranges = tv.selectedRanges

            tv.string = text

            // tv.string= 可能替换 textStorage 对象导致 delegate 丢失，重新绑定
            tv.textStorage?.delegate = context.coordinator.highlighter

            // 恢复光标位置（clamp 防越界）
            let len = (text as NSString).length
            tv.selectedRanges = ranges.map { r in
                let range = r.rangeValue
                let loc = min(range.location, len)
                let end = min(range.location + range.length, len)
                return NSValue(range: NSRange(location: loc, length: end - loc))
            }
            context.coordinator.isUpdatingFromSwiftUI = false
        }

        // 内容变化、fileType 变化、深浅色变化时重新高亮
        if !isComposingMarkedText && (contentChanged || fileTypeChanged || darkModeChanged) {
            context.coordinator.scheduleHighlighting(for: tv)
            context.coordinator.lastHighlightedFileType = fileType
            context.coordinator.lastHighlightedIsDarkMode = isDarkMode
        }

        if context.coordinator.lastHighlightedFileType == nil {
            context.coordinator.lastHighlightedFileType = fileType
        }
        if context.coordinator.lastHighlightedIsDarkMode == nil {
            context.coordinator.lastHighlightedIsDarkMode = isDarkMode
        }

        // 确保 typingAttributes 使用正确颜色
        tv.typingAttributes = typingAttrs

        // 深浅色切换时同步背景色和光标色
        tv.backgroundColor = editorBackgroundColor
        tv.insertionPointColor = textColor
        scrollView.backgroundColor = editorBackgroundColor

        // 刷新行号
        if let ruler = scrollView.verticalRulerView as? LineNumberRulerView {
            let needsMetricRefresh = contentChanged
            ruler.refresh(recalculateMetrics: needsMetricRefresh)
        }
        if contentChanged {
            context.coordinator.updateCursorPosition(for: tv)
        }

        // 应用搜索高亮
        applySearchHighlights(to: tv, context: context)

        // 注入回调，确保语法高亮后搜索背景色不丢失
        context.coordinator.reapplySearchHighlights = { [searchResults, currentSearchIndex] textView in
            guard let storage = textView.textStorage else { return }
            guard !searchResults.isEmpty else { return }
            let fullRange = NSRange(location: 0, length: storage.length)
            storage.removeAttribute(.backgroundColor, range: fullRange)
            let allColor: NSColor = self.isDarkMode
                ? NSColor(red: 0.80, green: 0.65, blue: 0.10, alpha: 0.45)
                : NSColor(red: 0.98, green: 0.85, blue: 0.10, alpha: 0.55)
            let currentColor: NSColor = self.isDarkMode
                ? NSColor(red: 1.00, green: 0.75, blue: 0.00, alpha: 0.85)
                : NSColor(red: 1.00, green: 0.72, blue: 0.00, alpha: 0.90)
            storage.beginEditing()
            for (i, range) in searchResults.enumerated() {
                guard NSMaxRange(range) <= storage.length else { continue }
                storage.addAttribute(.backgroundColor, value: i == currentSearchIndex ? currentColor : allColor, range: range)
            }
            storage.endEditing()
        }
    }

    // MARK: - Search Highlight

    private func applySearchHighlights(to tv: NSTextView, context: Context) {
        guard let storage = tv.textStorage else { return }

        let resultsHash = searchResultsHash(for: searchResults)

        let needsRepaint = context.coordinator.lastSearchResultsHash != resultsHash
            || context.coordinator.lastCurrentSearchIndex != currentSearchIndex
            || context.coordinator.lastSearchHighlightDarkMode != isDarkMode

        if needsRepaint {
            let fullRange = NSRange(location: 0, length: storage.length)
            storage.removeAttribute(.backgroundColor, range: fullRange)

            if !searchResults.isEmpty {
                let allMatchColor: NSColor = isDarkMode
                    ? NSColor(red: 0.80, green: 0.65, blue: 0.10, alpha: 0.45)
                    : NSColor(red: 0.98, green: 0.85, blue: 0.10, alpha: 0.55)
                let currentMatchColor: NSColor = isDarkMode
                    ? NSColor(red: 1.00, green: 0.75, blue: 0.00, alpha: 0.85)
                    : NSColor(red: 1.00, green: 0.72, blue: 0.00, alpha: 0.90)

                storage.beginEditing()
                for (i, range) in searchResults.enumerated() {
                    guard NSMaxRange(range) <= storage.length else { continue }
                    let color = i == currentSearchIndex ? currentMatchColor : allMatchColor
                    storage.addAttribute(.backgroundColor, value: color, range: range)
                }
                storage.endEditing()
            }

            context.coordinator.lastSearchResultsHash = resultsHash
            context.coordinator.lastCurrentSearchIndex = currentSearchIndex
            context.coordinator.lastSearchHighlightDarkMode = isDarkMode
        }

        // 滚动到当前匹配项（由 scrollRevision 驱动，避免每次 updateNSView 都滚动）
        let lastRevision = context.coordinator.lastScrollRevision
        if scrollRevision != lastRevision, currentSearchIndex < searchResults.count {
            context.coordinator.lastScrollRevision = scrollRevision
            let targetRange = searchResults[currentSearchIndex]
            if NSMaxRange(targetRange) <= (tv.string as NSString).length {
                tv.scrollRangeToVisible(targetRange)
                tv.setSelectedRange(targetRange)
            }
        }
    }

    private var editorBackgroundColor: NSColor {
        NSColor.textBackgroundColor
    }

    private func searchResultsHash(for ranges: [NSRange]) -> Int {
        var hasher = Hasher()
        hasher.combine(ranges.count)
        for range in ranges {
            hasher.combine(range.location)
            hasher.combine(range.length)
        }
        return hasher.finalize()
    }
}

// MARK: - EditorView

struct EditorView: View {

    @ObservedObject var editorViewModel: EditorViewModel
    @ObservedObject var saveCoordinator: CommandCoordinator
    let onConfirmNavigation: (EditorViewModel.PendingNavigationTarget) -> Void

    @Environment(\.colorScheme) var colorScheme

    @State private var isSearchBarVisible = false
    @State private var cursorLine = 1
    @State private var cursorColumn = 1
    @State private var saveErrorMessage: String?

    var body: some View {
        Group {
            if editorViewModel.currentFile == nil {
                VStack(spacing: 0) {
                    editorToolbar
                    emptyStateView
                }
            } else {
                VStack(spacing: 0) {
                    editorToolbar
                    editorContent
                }
            }
        }
        .background(Color.editorPanelBackground)
        .onAppear {
            saveCoordinator.onSave = { [weak editorViewModel = editorViewModel] in
                guard let vm = editorViewModel else { return }
                do {
                    try await vm.save()
                } catch {
                    await MainActor.run {
                        saveErrorMessage = error.localizedDescription
                    }
                }
            }
            saveCoordinator.onToggleSearch = { [self] in
                withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                    isSearchBarVisible = true
                }
            }
        }
        .alert(
            L10n.tr("editor.externalChange.title", value: "External Changes Detected"),
            isPresented: $editorViewModel.hasExternalConflict
        ) {
            Button(L10n.tr("editor.externalChange.keepLocal", value: "Keep App Changes")) {
                Task { await editorViewModel.resolveConflict(keepLocal: true) }
            }
            Button(L10n.tr("editor.externalChange.useExternal", value: "Use External Version"), role: .destructive) {
                Task { await editorViewModel.resolveConflict(keepLocal: false) }
            }
        } message: {
            Text(L10n.tr("editor.externalChange.message", value: "This file changed outside the app. Choose whether to write the app's unsaved changes back to disk or replace the editor with the external version."))
        }
        .alert(
            L10n.tr("editor.unsavedChanges.title", value: "Unsaved Changes"),
            isPresented: $editorViewModel.hasPendingUnsavedChangesConfirmation
        ) {
            Button(L10n.tr("editor.unsavedChanges.save", value: "Save")) {
                Task {
                    if let target = await editorViewModel.confirmPendingNavigationSavingChanges() {
                        await MainActor.run {
                            onConfirmNavigation(target)
                        }
                    }
                }
            }
            Button(L10n.tr("editor.unsavedChanges.discard", value: "Discard"), role: .destructive) {
                if let target = editorViewModel.confirmPendingNavigationDiscardingChanges() {
                    onConfirmNavigation(target)
                }
            }
            Button(L10n.tr("editor.unsavedChanges.cancel", value: "Cancel"), role: .cancel) {
                editorViewModel.cancelPendingNavigation()
            }
        } message: {
            Text(L10n.tr("editor.unsavedChanges.message", value: "You have unsaved changes. Save them before switching to another configuration?"))
        }
        .alert(L10n.tr("editor.saveFailed.title", value: "Save Failed"), isPresented: saveErrorBinding) {
            Button(L10n.tr("editor.saveFailed.ok", value: "OK"), role: .destructive) {
                saveErrorMessage = nil
            }
        } message: {
            Text(saveErrorMessage ?? L10n.tr("editor.saveFailed.message", value: "An unknown error occurred while saving."))
        }
        .onChange(of: editorViewModel.currentFile) { _, newFile in
            cursorLine = 1
            cursorColumn = 1
            isSearchBarVisible = false
            saveErrorMessage = nil
        }
    }

    private var editorToolbar: some View {
        EditorToolbarView(
            editorViewModel: editorViewModel,
            onShowSearch: {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                    isSearchBarVisible = true
                }
            },
            isSearchBarVisible: isSearchBarVisible,
            onCloseSearch: closeSearchBar
        )
    }

    private var editorContent: some View {
        VStack(spacing: 0) {
            CodeEditorView(
                text: $editorViewModel.content,
                cursorLine: $cursorLine,
                cursorColumn: $cursorColumn,
                fileType: editorViewModel.currentFile?.fileType ?? .plainText,
                isDarkMode: colorScheme == .dark,
                searchResults: editorViewModel.searchResults,
                currentSearchIndex: editorViewModel.currentSearchIndex,
                scrollRevision: editorViewModel.scrollRevision,
                isSearchBarVisible: isSearchBarVisible,
                onEscape: handleEscapeKey
            )

            statusBar
        }
    }

    private var emptyStateView: some View {
        VStack(spacing: 14) {
            Image(systemName: "doc.text")
                .font(.system(size: 44))
                .foregroundStyle(.tertiary)
            Text(L10n.tr("editor.empty.title", value: "Select a file to start editing"))
                .font(.title3)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)
            Text(L10n.tr("editor.empty.subtitle", value: "Choose a configuration file from the sidebar"))
                .font(.callout)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.editorPanelBackground)
    }

    private var statusBar: some View {
        HStack(spacing: 0) {
            Spacer()

            statusText(L10n.format("editor.status.lineColumn", value: "Line %d, Column %d", cursorLine, cursorColumn))
            statusText("UTF-8")
            statusText(fileTypeLabel)
            statusText("LF")
        }
        .frame(height: 31)
        .background(Color.editorChromeBackground)
        .overlay(Divider(), alignment: .top)
    }

    private func statusText(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .padding(.horizontal, 13)
    }

    private func handleEscapeKey() -> Bool {
        guard isSearchBarVisible else { return false }
        closeSearchBar()
        return true
    }

    private func closeSearchBar() {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
            isSearchBarVisible = false
        }
        editorViewModel.searchQuery = ""
        editorViewModel.search(query: "", caseSensitive: editorViewModel.isCaseSensitive)
    }

    private var fileTypeLabel: String {
        (editorViewModel.currentFile?.fileType ?? .plainText).displayName
    }

    private var saveErrorBinding: Binding<Bool> {
        Binding(
            get: { saveErrorMessage != nil },
            set: { isPresented in
                if !isPresented {
                    saveErrorMessage = nil
                }
            }
        )
    }
}

private extension Color {
    static var editorPanelBackground: Color {
        Color(nsColor: .textBackgroundColor)
    }

    static var editorChromeBackground: Color {
        Color(nsColor: .windowBackgroundColor)
    }
}
