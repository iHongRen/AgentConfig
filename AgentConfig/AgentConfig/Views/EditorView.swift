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

    init(scrollView: NSScrollView, textView: NSTextView) {
        self.textView = textView
        super.init(scrollView: scrollView, orientation: .verticalRuler)
        self.clientView = textView
        self.ruleThickness = 40
    }

    required init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var requiredThickness: CGFloat {
        guard let text = textView?.string else { return 40 }
        let lineCount = max(1, text.components(separatedBy: "\n").count)
        let digits = max(2, String(lineCount).count)
        let sample = String(repeating: "9", count: digits) as NSString
        let w = sample.size(withAttributes: [.font: lineNumberFont]).width
        return w + 16
    }

    override func draw(_ dirtyRect: NSRect) {
        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }

        NSBezierPath(rect: bounds).setClip()

        let isDark = textView?.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        (isDark ? NSColor(white: 0.13, alpha: 1) : NSColor(white: 0.985, alpha: 1)).setFill()
        bounds.fill()

        drawLineNumbers()
    }

    private func drawLineNumbers() {
        guard let textView = textView,
              let layoutManager = textView.layoutManager,
              let textContainer = textView.textContainer else { return }

        let visibleRect = scrollView?.contentView.bounds ?? bounds
        let containerOrigin = textView.textContainerOrigin
        let attrs: [NSAttributedString.Key: Any] = [
            .font: lineNumberFont,
            .foregroundColor: NSColor.secondaryLabelColor
        ]

        let fullText = textView.string as NSString
        let totalLength = fullText.length
        var lineNumber = 1
        var charIndex = 0

        layoutManager.ensureLayout(for: textContainer)

        while charIndex <= totalLength {
            let glyphRange = layoutManager.glyphRange(
                forCharacterRange: NSRange(location: charIndex, length: 0),
                actualCharacterRange: nil
            )
            guard glyphRange.location < layoutManager.numberOfGlyphs || charIndex == 0 else { break }

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

    func refresh() {
        ruleThickness = requiredThickness
        needsDisplay = true
    }
}

// MARK: - CodeEditorView

struct CodeEditorView: NSViewRepresentable {

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
        /// 语法高亮完成后重新应用搜索背景色的回调（由 updateNSView 注入）
        var reapplySearchHighlights: ((NSTextView) -> Void)?

        init(_ parent: CodeEditorView) {
            self.parent = parent
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

            if finishedMarkedText {
                DispatchQueue.main.async { [weak self, weak tv] in
                    guard let self, let tv else { return }
                    self.applyHighlightingPreservingSelection(in: tv)
                    self.refreshLineNumberRuler(for: tv)
                }
            } else {
                applyHighlightingPreservingSelection(in: tv)
                refreshLineNumberRuler(for: tv)
            }
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            guard let tv = notification.object as? NSTextView else { return }

            if isComposingMarkedText && !tv.hasMarkedText() {
                isComposingMarkedText = false
                let newText = tv.string
                if parent.text != newText {
                    parent.text = newText
                }
                DispatchQueue.main.async { [weak self, weak tv] in
                    guard let self, let tv else { return }
                    self.applyHighlightingPreservingSelection(in: tv)
                    self.refreshLineNumberRuler(for: tv)
                }
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

            if parent.cursorLine != line {
                parent.cursorLine = line
            }
            if parent.cursorColumn != column {
                parent.cursorColumn = column
            }
        }

        func refreshLineNumberRuler(for textView: NSTextView) {
            if let sv = textView.enclosingScrollView,
               let ruler = sv.verticalRulerView as? LineNumberRulerView {
                ruler.refresh()
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
        let tv = NSTextView(frame: NSRect(x: 0, y: 0, width: 100, height: 100))

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
        
        // 手动触发一次高亮
        if let storage = tv.textStorage, storage.length > 0 {
            storage.beginEditing()
            context.coordinator.highlighter?.applyHighlighting(to: storage)
            storage.endEditing()
        }
        
        ruler.refresh()
        context.coordinator.updateCursorPosition(for: tv)

        return scrollView
    }

    // MARK: updateNSView

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let tv = scrollView.documentView as? NSTextView else { return }

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
            context.coordinator.applyHighlightingPreservingSelection(in: tv)
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

        // 搜索栏显隐时，补偿滚动位置，避免文本内容视觉跳动
        let searchVisibilityChanged = context.coordinator.lastSearchBarVisible != isSearchBarVisible
        let newTopInset: CGFloat = isSearchBarVisible ? 54 : 14
        tv.textContainerInset = NSSize(width: 16, height: newTopInset)
        if searchVisibilityChanged {
            let delta: CGFloat = isSearchBarVisible ? 40 : -40
            var origin = scrollView.contentView.bounds.origin
            origin.y = max(0, origin.y + delta)
            scrollView.contentView.setBoundsOrigin(origin)
            scrollView.reflectScrolledClipView(scrollView.contentView)
            context.coordinator.lastSearchBarVisible = isSearchBarVisible
        }

        // 刷新行号
        if let ruler = scrollView.verticalRulerView as? LineNumberRulerView {
            ruler.refresh()
        }
        context.coordinator.updateCursorPosition(for: tv)

        // 应用搜索高亮
        applySearchHighlights(to: tv, context: context)

        // 注入回调，确保语法高亮后搜索背景色不丢失
        context.coordinator.reapplySearchHighlights = { [searchResults, currentSearchIndex] textView in
            guard let storage = textView.textStorage else { return }
            let fullRange = NSRange(location: 0, length: storage.length)
            storage.removeAttribute(.backgroundColor, range: fullRange)
            guard !searchResults.isEmpty else { return }
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
        let fullRange = NSRange(location: 0, length: storage.length)

        // 先清除旧的搜索背景色
        storage.removeAttribute(.backgroundColor, range: fullRange)

        guard !searchResults.isEmpty else { return }

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
        isDarkMode ? NSColor(white: 0.12, alpha: 1) : NSColor(white: 0.985, alpha: 1)
    }
}

// MARK: - EditorView

struct EditorView: View {

    @ObservedObject var editorViewModel: EditorViewModel
    @ObservedObject var gitViewModel: GitViewModel
    @ObservedObject var saveCoordinator: CommandCoordinator

    @Environment(\.colorScheme) var colorScheme

    @State private var isSearchBarVisible = false
    @State private var isExamplesPaneVisible = false
    @State private var isShowingHistory = false
    @State private var cursorLine = 1
    @State private var cursorColumn = 1
    @State private var examplesPaneWidth: CGFloat = 340
    @State private var toastMessage: String? = nil
    @State private var toastTask: Task<Void, Never>? = nil

    var body: some View {
        Group {
            if editorViewModel.currentFile == nil {
                VStack(spacing: 0) {
                    editorToolbar
                    emptyStateView
                }
            } else {
                HStack(spacing: 0) {
                    VStack(spacing: 0) {
                        editorToolbar
                        editorContent
                    }
                    .frame(minWidth: 280)

                    if isExamplesPaneVisible {
                        ResizableDivider(width: $examplesPaneWidth)

                        ConfigExamplesPaneView(
                            groups: exampleGroups,
                            file: editorViewModel.currentFile,
                            onCopy: copyExampleToClipboard
                        )
                        .frame(width: examplesPaneWidth)
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                    }
                }
            }
        }
        .background(Color.editorPanelBackground)
        .onAppear {
            saveCoordinator.onSave = { [weak editorViewModel = editorViewModel] in
                guard let vm = editorViewModel else { return }
                try? await vm.save()
            }
            saveCoordinator.onToggleSearch = { [self] in
                withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                    isSearchBarVisible = true
                }
            }
        }
        .sheet(isPresented: $isShowingHistory) {
            GitHistoryView(gitViewModel: gitViewModel)
        }
        .alert(
            "文件已被外部修改",
            isPresented: $editorViewModel.hasExternalConflict
        ) {
            Button("保留本地修改") {
                Task { await editorViewModel.resolveConflict(keepLocal: true) }
            }
            Button("加载外部版本", role: .destructive) {
                Task { await editorViewModel.resolveConflict(keepLocal: false) }
            }
        } message: {
            Text("当前文件在外部被修改，请选择如何处理本地未保存的修改。")
        }
        .onChange(of: editorViewModel.sourceResult) { _, result in
            guard let result else { return }
            let msg = result.success ? "source 执行成功" : "source 失败：\(result.errorOutput)"
            showToast(msg)
        }
        .onChange(of: editorViewModel.currentFile) { _, newFile in
            cursorLine = 1
            cursorColumn = 1
            isSearchBarVisible = false
            if examples(for: newFile).isEmpty {
                isExamplesPaneVisible = false
            }
        }
    }

    private var editorToolbar: some View {
        EditorToolbarView(
            editorViewModel: editorViewModel,
            gitViewModel: gitViewModel,
            isExamplesVisible: isExamplesPaneVisible,
            hasExamples: hasExamples,
            onShowSearch: {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                    isSearchBarVisible = true
                }
            },
            onToggleExamples: {
                withAnimation(.easeInOut(duration: 0.18)) {
                    isExamplesPaneVisible.toggle()
                }
            },
            onShowHistory: { isShowingHistory = true }
        )
    }

    private var exampleGroups: [ConfigExampleGroup] {
        examples(for: editorViewModel.currentFile)
    }

    private var hasExamples: Bool {
        !exampleGroups.isEmpty
    }

    private func examples(for file: ConfigFile?) -> [ConfigExampleGroup] {
        guard let file else { return [] }
        return ConfigExamples.groups(for: file)
    }

    private var editorContent: some View {
        ZStack(alignment: .top) {
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
                    isSearchBarVisible: isSearchBarVisible
                )

                statusBar
            }

            SearchBarView(isVisible: $isSearchBarVisible, viewModel: editorViewModel)
                .offset(y: isSearchBarVisible ? 0 : -40)
                .opacity(isSearchBarVisible ? 1 : 0)
                .allowsHitTesting(isSearchBarVisible)

            if let msg = toastMessage {
                toastView(message: msg)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .padding(.bottom, 44)
            }
        }
    }

    private var emptyStateView: some View {
        VStack(spacing: 14) {
            Image(systemName: "doc.text")
                .font(.system(size: 44))
                .foregroundStyle(.tertiary)
            Text("选择左侧文件开始编辑")
                .font(.title3)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)
            Text("从侧边栏选择一个配置文件")
                .font(.callout)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.editorPanelBackground)
    }

    private var statusBar: some View {
        HStack(spacing: 0) {
            Spacer()

            statusText("行 \(cursorLine), 列 \(cursorColumn)")
            statusText("UTF-8")
            statusText(fileTypeLabel)
            statusText("LF")

            HStack(spacing: 6) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(Color.green)
                    .font(.system(size: 13))
                Text("无语法错误")
            }
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 14)
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

    private var fileTypeLabel: String {
        switch editorViewModel.currentFile?.fileType ?? .plainText {
        case .json:
            return "JSON"
        case .jsonc:
            return "JSONC"
        case .json5:
            return "JSON5"
        case .jsonl:
            return "JSONL"
        case .yaml:
            return "YAML"
        case .toml:
            return "TOML"
        case .shell:
            return "Shell Script"
        case .plainText:
            return "Plain Text"
        }
    }

    private func toastView(message: String) -> some View {
        Text(message)
            .font(.system(size: 13))
            .foregroundStyle(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(Capsule().fill(Color(nsColor: .labelColor).opacity(0.78)))
    }

    private func copyExampleToClipboard(_ code: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(code, forType: .string)
        showToast("已复制示例")
    }

    private func showToast(_ message: String) {
        toastTask?.cancel()
        withAnimation(.easeInOut(duration: 0.2)) { toastMessage = message }
        toastTask = Task {
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                withAnimation(.easeInOut(duration: 0.3)) { toastMessage = nil }
            }
        }
    }
}

private struct ResizableDivider: View {
    @Binding var width: CGFloat
    @State private var dragStartWidth: CGFloat?
    @State private var dragStartX: CGFloat?

    var body: some View {
        Rectangle()
            .fill(Color.clear)
            .frame(width: 12)
            .overlay(
                Rectangle()
                    .fill(Color(nsColor: .separatorColor))
                    .frame(width: 1)
            )
            .contentShape(Rectangle())
            .transaction { transaction in
                transaction.animation = nil
            }
            .gesture(
                DragGesture(minimumDistance: 1, coordinateSpace: .global)
                    .onChanged { value in
                        if dragStartWidth == nil {
                            dragStartWidth = width
                            dragStartX = value.startLocation.x
                        }
                        guard let dragStartWidth, let dragStartX else { return }
                        let proposedWidth = dragStartWidth - (value.location.x - dragStartX)
                        width = min(max(proposedWidth, 260), 560)
                    }
                    .onEnded { _ in
                        dragStartWidth = nil
                        dragStartX = nil
                    }
            )
            .onHover { isHovering in
                if isHovering {
                    NSCursor.resizeLeftRight.push()
                } else {
                    NSCursor.pop()
                }
            }
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

// MARK: - Preview
//
//#Preview("Empty State") {
//    EditorView(editorViewModel: EditorViewModel(), gitViewModel: GitViewModel())
//        .frame(width: 700, height: 500)
//}
