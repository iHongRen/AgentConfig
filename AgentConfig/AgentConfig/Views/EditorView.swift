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
        // 用 NSGraphicsContext 保存状态，并严格 clip 到自身 bounds，
        // 防止任何绘制溢出到 textView 区域
        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }

        // clip 到 ruler 自身的 bounds，绝对不会溢出
        NSBezierPath(rect: bounds).setClip()

        // 背景
        NSColor(white: 0.96, alpha: 1.0).setFill()
        bounds.fill()

        // 右侧分隔线
        NSColor.separatorColor.setStroke()
        let line = NSBezierPath()
        line.move(to: NSPoint(x: bounds.maxX - 0.5, y: dirtyRect.minY))
        line.line(to: NSPoint(x: bounds.maxX - 0.5, y: dirtyRect.maxY))
        line.lineWidth = 0.5
        line.stroke()

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
    var fileType: FileType
    var isDarkMode: Bool

    // MARK: Coordinator

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: CodeEditorView
        var isUpdatingFromSwiftUI = false

        init(_ parent: CodeEditorView) {
            self.parent = parent
        }

        func textDidChange(_ notification: Notification) {
            guard !isUpdatingFromSwiftUI,
                  let tv = notification.object as? NSTextView else { return }
            let newText = tv.string
            if parent.text != newText {
                parent.text = newText
            }
            if let sv = tv.enclosingScrollView,
               let ruler = sv.verticalRulerView as? LineNumberRulerView {
                ruler.refresh()
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
        scrollView.backgroundColor = isDarkMode ? NSColor(white: 0.12, alpha: 1) : NSColor(white: 0.98, alpha: 1)

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
        tv.backgroundColor = isDarkMode ? NSColor(white: 0.12, alpha: 1) : NSColor(white: 0.98, alpha: 1)
        tv.textColor = textColor
        tv.insertionPointColor = textColor
        tv.textContainerInset = NSSize(width: 4, height: 4)

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
        let highlighter = SyntaxHighlighter(fileType: fileType, isDarkMode: isDarkMode)
        tv.textStorage?.delegate = highlighter

        // 9. 行号 ruler
        let ruler = LineNumberRulerView(scrollView: scrollView, textView: tv)
        scrollView.verticalRulerView = ruler
        scrollView.hasVerticalRuler = true
        scrollView.rulersVisible = true

        // 10. 设置初始内容
        // 直接用 tv.string 设置，简单可靠
        tv.string = text
        
        // tv.string= 可能会替换 textStorage 对象，导致 delegate 丢失，重新设置
        tv.textStorage?.delegate = highlighter
        
        // 设置 typingAttributes，确保新输入的文字有正确颜色
        tv.typingAttributes = [
            .font: NSFont.monospacedSystemFont(ofSize: 13, weight: .regular),
            .foregroundColor: textColor
        ]
        
        // 手动触发一次高亮
        if let storage = tv.textStorage, storage.length > 0 {
            storage.beginEditing()
            highlighter.applyHighlighting(to: storage)
            storage.endEditing()
        }
        
        ruler.refresh()

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

        // 更新高亮器配置
        if let h = tv.textStorage?.delegate as? SyntaxHighlighter {
            var needsRehighlight = false
            if h.fileType != fileType { h.fileType = fileType; needsRehighlight = true }
            if h.isDarkMode != isDarkMode { h.isDarkMode = isDarkMode; needsRehighlight = true }
            if needsRehighlight, let storage = tv.textStorage {
                storage.beginEditing()
                h.applyHighlighting(to: storage)
                storage.endEditing()
            }
        }

        // 仅在内容真正不同时才更新，避免光标跳动
        if tv.string != text {
            context.coordinator.isUpdatingFromSwiftUI = true
            let ranges = tv.selectedRanges
            
            // 先保存 highlighter 引用，tv.string= 可能替换 textStorage 对象
            let highlighter = tv.textStorage?.delegate as? SyntaxHighlighter

            tv.string = text

            // tv.string= 可能替换 textStorage 对象导致 delegate 丢失，重新设置
            if let h = highlighter {
                tv.textStorage?.delegate = h
            }

            // tv.string= 之后重新设置属性和高亮
            if let storage = tv.textStorage, storage.length > 0 {
                storage.beginEditing()
                let fullRange = NSRange(location: 0, length: storage.length)
                storage.addAttribute(.font, value: NSFont.monospacedSystemFont(ofSize: 13, weight: .regular), range: fullRange)
                storage.addAttribute(.foregroundColor, value: textColor, range: fullRange)
                if let h = storage.delegate as? SyntaxHighlighter {
                    h.applyHighlighting(to: storage)
                }
                storage.endEditing()
            }

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

        // 确保 typingAttributes 使用正确颜色
        tv.typingAttributes = typingAttrs

        // 深浅色切换时同步背景色和光标色
        tv.backgroundColor = isDarkMode ? NSColor(white: 0.12, alpha: 1) : NSColor(white: 0.98, alpha: 1)
        tv.insertionPointColor = textColor
        scrollView.backgroundColor = isDarkMode ? NSColor(white: 0.12, alpha: 1) : NSColor(white: 0.98, alpha: 1)

        // 刷新行号
        if let ruler = scrollView.verticalRulerView as? LineNumberRulerView {
            ruler.refresh()
        }
    }
}

// MARK: - EditorView

struct EditorView: View {

    @ObservedObject var editorViewModel: EditorViewModel
    @ObservedObject var gitViewModel: GitViewModel

    @Environment(\.colorScheme) var colorScheme

    @State private var isSearchBarVisible = false
    @State private var isShowingHistory = false
    @State private var toastMessage: String? = nil
    @State private var toastTask: Task<Void, Never>? = nil

    var body: some View {
        VStack(spacing: 0) {
            EditorToolbarView(
                editorViewModel: editorViewModel,
                gitViewModel: gitViewModel,
                onShowHistory: { isShowingHistory = true }
            )

            if isSearchBarVisible {
                SearchBarView(isVisible: $isSearchBarVisible, viewModel: editorViewModel)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }

            Divider()

            if editorViewModel.currentFile == nil {
                emptyStateView
            } else {
                ZStack(alignment: .bottom) {
                    CodeEditorView(
                        text: $editorViewModel.content,
                        fileType: editorViewModel.currentFile?.fileType ?? .plainText,
                        isDarkMode: colorScheme == .dark
                    )
                    if let msg = toastMessage {
                        toastView(message: msg)
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                            .padding(.bottom, 16)
                    }
                }
            }
        }
        .background(
            Button("") { Task { try? await editorViewModel.save() } }
                .keyboardShortcut("s", modifiers: .command)
                .hidden()
        )
        .background(
            Button("") {
                withAnimation(.easeInOut(duration: 0.2)) { isSearchBarVisible = true }
            }
            .keyboardShortcut("f", modifiers: .command)
            .hidden()
        )
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
            let msg = result.success ? "✓ source 执行成功" : "✗ source 失败：\(result.errorOutput)"
            showToast(msg)
        }
    }

    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "doc.text")
                .font(.system(size: 48))
                .foregroundStyle(.tertiary)
            Text("选择左侧文件开始编辑")
                .font(.title3)
                .foregroundStyle(.secondary)
            Text("从侧边栏选择一个配置文件")
                .font(.callout)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(NSColor.textBackgroundColor))
    }

    private func toastView(message: String) -> some View {
        Text(message)
            .font(.system(size: 13))
            .foregroundStyle(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(Capsule().fill(Color.black.opacity(0.75)))
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

// MARK: - Preview
//
//#Preview("Empty State") {
//    EditorView(editorViewModel: EditorViewModel(), gitViewModel: GitViewModel())
//        .frame(width: 700, height: 500)
//}
