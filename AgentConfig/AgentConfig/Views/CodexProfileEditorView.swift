//
//  CodexProfileEditorView.swift
//  AgentConfig
//

import SwiftUI
import AppKit

struct CodexProfileEditorView: View {

    @ObservedObject var viewModel: CodexProfileViewModel
    @Environment(\.colorScheme) private var colorScheme
    @FocusState private var isNameFieldFocused: Bool

    @State private var toastMessage: String?
    @State private var toastTask: Task<Void, Never>?
    @State private var measuredEditorHeights: [ProfileCodeField: CGFloat] = [:]
    @State private var customEditorHeights: [ProfileCodeField: CGFloat] = [:]
    @State private var resizingFields: Set<ProfileCodeField> = []
    @State private var pendingDeleteProfile: CodexProfile?
    @State private var editingProfileName: String = ""

    private let profileNameMaxLength = 15

    var body: some View {
        VStack(spacing: 0) {
            if let profile = viewModel.selectedProfile {
                profileToolbar(profile: profile)

                ScrollView {
                    VStack(spacing: 12) {
                        codeCard(
                            title: "~/.codex/config.toml",
                            language: "TOML",
                            icon: "gearshape",
                            fileType: .toml,
                            field: .config,
                            textValue: profile.configText,
                            text: configBinding(for: profile.id)
                        )

                        codeCard(
                            title: "~/.codex/auth.json",
                            language: "JSON",
                            icon: "curlybraces",
                            fileType: .json,
                            field: .auth,
                            textValue: profile.authText,
                            text: authBinding(for: profile.id)
                        )

                        codeCard(
                            title: "~/.zshrc",
                            language: "Shell",
                            icon: "terminal",
                            fileType: .shell,
                            field: .zshrc,
                            textValue: profile.zshrcText,
                            text: zshrcBinding(for: profile.id)
                        )
                    }
                    .padding(14)
                }
            } else {
                emptyState
            }
        }
        .background(Color(nsColor: .textBackgroundColor))
        .contentShape(Rectangle())
        .onTapGesture {
            dismissAllInputsFocus()
        }
        .overlay(alignment: .bottom) {
            if let toastMessage {
                Text(toastMessage)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(Capsule().fill(Color(nsColor: .labelColor).opacity(0.78)))
                    .padding(.bottom, 18)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .onChange(of: viewModel.selectedProfileID) { _, _ in
            measuredEditorHeights = [:]
            customEditorHeights = [:]
            resizingFields = []
            editingProfileName = viewModel.selectedProfile?.name ?? ""
        }
        .onAppear {
            editingProfileName = viewModel.selectedProfile?.name ?? ""
        }
        .alert(item: $pendingDeleteProfile) { profile in
            Alert(
                title: Text("删除 Codex Profile？"),
                message: Text("将删除“\(profile.name.isEmpty ? "未命名配置" : profile.name)”。此操作不会修改已经写入磁盘的 Codex 配置文件。"),
                primaryButton: .destructive(Text("删除")) {
                    if viewModel.deleteProfile(id: profile.id) {
                        showToast("已删除配置")
                    } else {
                        showToast(viewModel.lastErrorMessage ?? "删除失败")
                    }
                },
                secondaryButton: .cancel(Text("取消"))
            )
        }
    }

    private func profileToolbar(profile: CodexProfile) -> some View {
        HStack(spacing: 10) {
            Button {
                isNameFieldFocused = true
            } label: {
                HStack(spacing: 0) {
                    TextField("配置名称", text: $editingProfileName)
                        .textFieldStyle(.plain)
                        .font(.system(size: 13, weight: .semibold))
                        .focused($isNameFieldFocused)
                        .frame(width: profileNameFieldWidth(for: editingProfileName), alignment: .leading)
                        .onChange(of: editingProfileName) { _, newValue in
                            let truncated = String(newValue.prefix(profileNameMaxLength))
                            if truncated != newValue {
                                editingProfileName = truncated
                            }
                            viewModel.updateSelected(name: truncated)
                        }
                        .onSubmit {
                            let truncated = String(editingProfileName.prefix(profileNameMaxLength))
                            if truncated != editingProfileName {
                                editingProfileName = truncated
                            }
                            viewModel.updateSelected(name: truncated)
                            dismissAllInputsFocus()
                        }

                    if !isNameFieldFocused {
                        Image(systemName: "square.and.pencil")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal, 14)
                .frame(minWidth: 50, alignment: .leading)
                .frame(height: 34)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(nameFieldBackgroundColor)
                )
                .contentShape(RoundedRectangle(cornerRadius: 10))
            }
            .buttonStyle(.plain)

            Spacer(minLength: 12)

            statusPill(for: profile)

            Button(role: .destructive) {
                pendingDeleteProfile = profile
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 18, height: 18)
                    .frame(width: 44, height: 34)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(deleteButtonBackgroundColor)
                    )
                    .contentShape(RoundedRectangle(cornerRadius: 10))
            }
            .buttonStyle(.plain)
            .disabled(viewModel.profiles.count <= 1)
            .opacity(viewModel.profiles.count <= 1 ? 0.45 : 1)
            .help("删除当前配置")

            Button {
                Task {
                    let success = await viewModel.applySelected()
                    showToast(success ? "已应用配置" : (viewModel.lastErrorMessage ?? "应用失败"))
                }
            } label: {
                Label("应用", systemImage: "checkmark.circle")
                    .labelStyle(.titleAndIcon)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 86, height: 34)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(applyButtonBackgroundColor)
                    )
                    .contentShape(RoundedRectangle(cornerRadius: 10))
            }
            .buttonStyle(.plain)
            .disabled(viewModel.validateSelected() != nil)
            .opacity(viewModel.validateSelected() != nil ? 0.55 : 1)
            .help("应用当前配置")
        }
        .padding(.horizontal, 12)
        .frame(height: 48)
        .background(Color(nsColor: .windowBackgroundColor))
        .overlay(Divider(), alignment: .bottom)
    }

    private func statusPill(for profile: CodexProfile) -> some View {
        HStack(spacing: 6) {
            Circle()
                .fill(profileStateColor(for: profile))
                .frame(width: 7, height: 7)

            Text(statusText(for: profile))
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .padding(.horizontal, 9)
        .frame(height: 24)
        .background(
            Capsule()
                .fill(Color(nsColor: .controlBackgroundColor))
        )
    }

    private func codeCard(
        title: String,
        language: String,
        icon: String,
        fileType: FileType,
        field: ProfileCodeField,
        textValue: String,
        text: Binding<String>
    ) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Text(title)
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .truncationMode(.middle)

                Text(language)
                    .font(.system(size: 9, weight: .semibold, design: .monospaced))
                    .foregroundStyle(languageTagStyle(for: field).foreground)
                    .padding(.horizontal, 8)
                    .frame(height: 18)
                    .background(
                        Capsule()
                            .fill(languageTagStyle(for: field).background)
                    )

                Text("\(lineCount(in: text.wrappedValue)) 行")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)

                Spacer(minLength: 8)

                Button("复制") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(text.wrappedValue, forType: .string)
                    showToast("已复制当前配置片段")
                }
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Color(red: 0.6, green: 0.6, blue: 0.6))
                .frame(height: 24)
                .buttonStyle(.plain)
                .help("复制")
            }
            .padding(.horizontal, 12)
            .frame(height: 32)
            .background(Color(nsColor: .windowBackgroundColor))

            Divider()

            HighlightedProfileCodeEditor(
                text: text,
                measuredHeight: measuredHeightBinding(for: field),
                fileType: fileType,
                isDarkMode: colorScheme == .dark,
                shouldMeasureHeight: customEditorHeights[field] == nil && !resizingFields.contains(field)
            )
            .frame(height: editorHeight(for: field))
            .background(Color(nsColor: .textBackgroundColor))
        }
        .background(Color(nsColor: .textBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(Color(nsColor: .separatorColor).opacity(0.75))
        )
        .overlay(alignment: .bottom) {
            resizeHitArea(for: field)
        }
        .onAppear {
            if measuredEditorHeights[field] == nil {
                measuredEditorHeights[field] = estimatedEditorHeight(for: textValue)
            }
        }
    }

    private func resizeHitArea(for field: ProfileCodeField) -> some View {
        ProfileResizeHandleView(
            currentHeight: editorHeight(for: field),
            onResizeStart: {
                resizingFields.insert(field)
            },
            onResize: { newHeight in
                var transaction = Transaction()
                transaction.disablesAnimations = true
                withTransaction(transaction) {
                    customEditorHeights[field] = ProfileEditorSizing.clampedCustomHeight(newHeight)
                }
            },
            onResizeEnd: {
                resizingFields.remove(field)
            }
        )
        .frame(height: ProfileEditorSizing.resizeHandleHeight)
        .help("拖动底部边缘调整高度")
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "rectangle.stack")
                .font(.system(size: 42))
                .foregroundStyle(.tertiary)
            Text("选择左侧配置")
                .font(.title3)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func nameBinding(for id: UUID) -> Binding<String> {
        Binding(
            get: {
                viewModel.profiles.first { $0.id == id }?.name ?? ""
            },
            set: { newValue in
                viewModel.updateSelected(name: String(newValue.prefix(profileNameMaxLength)))
            }
        )
    }

    private func profileNameFieldWidth(for name: String) -> CGFloat {
        let displayText = name.isEmpty ? "配置名称" : name
        let font = NSFont.systemFont(ofSize: 13, weight: .semibold)
        let measuredWidth = ceil((displayText as NSString).size(withAttributes: [.font: font]).width)
        return min(max(measuredWidth + 10, 50), 240)
    }

    private var nameFieldBackgroundColor: Color {
        return Color(nsColor: .controlBackgroundColor).opacity(0.65)
    }

    private var deleteButtonBackgroundColor: Color {
        Color(red: 0.84, green: 0.16, blue: 0.20)
    }

    private var applyButtonBackgroundColor: Color {
        Color.accentColor
    }

    private func configBinding(for id: UUID) -> Binding<String> {
        Binding(
            get: { viewModel.profiles.first { $0.id == id }?.configText ?? "" },
            set: { viewModel.updateSelected(configText: $0) }
        )
    }

    private func authBinding(for id: UUID) -> Binding<String> {
        Binding(
            get: { viewModel.profiles.first { $0.id == id }?.authText ?? "" },
            set: { viewModel.updateSelected(authText: $0) }
        )
    }

    private func zshrcBinding(for id: UUID) -> Binding<String> {
        Binding(
            get: { viewModel.profiles.first { $0.id == id }?.zshrcText ?? "" },
            set: { viewModel.updateSelected(zshrcText: $0) }
        )
    }

    private func measuredHeightBinding(for field: ProfileCodeField) -> Binding<CGFloat> {
        Binding(
            get: { measuredEditorHeights[field] ?? ProfileEditorSizing.fallbackHeight },
            set: { newHeight in
                guard customEditorHeights[field] == nil,
                      !resizingFields.contains(field) else { return }

                var transaction = Transaction()
                transaction.disablesAnimations = true
                withTransaction(transaction) {
                    measuredEditorHeights[field] = newHeight
                }
            }
        )
    }

    private func editorHeight(for field: ProfileCodeField) -> CGFloat {
        if let customHeight = customEditorHeights[field] {
            return ProfileEditorSizing.clampedCustomHeight(customHeight)
        }

        let measuredHeight = measuredEditorHeights[field] ?? ProfileEditorSizing.fallbackHeight
        return ProfileEditorSizing.clampedDefaultHeight(measuredHeight)
    }

    private func statusText(for profile: CodexProfile) -> String {
        if profile.isDirty {
            return "未应用修改"
        }
        if profile.isActive {
            return "当前生效"
        }
        return "可应用"
    }

    private func profileStateColor(for profile: CodexProfile) -> Color {
        if profile.isDirty {
            return .orange
        }
        if profile.isActive {
            return .green
        }
        return .secondary
    }

    private func languageTagStyle(for field: ProfileCodeField) -> (foreground: Color, background: Color) {
        switch field {
        case .config:
            let color = Color(red: 0.91, green: 0.49, blue: 0.18)
            return (color, color.opacity(0.16))
        case .auth:
            let color = Color(red: 0.18, green: 0.64, blue: 0.42)
            return (color, color.opacity(0.16))
        case .zshrc:
            let color = Color(red: 0.46, green: 0.40, blue: 0.90)
            return (color, color.opacity(0.16))
        }
    }

    private func lineCount(in text: String) -> Int {
        max(1, text.split(separator: "\n", omittingEmptySubsequences: false).count)
    }

    private func estimatedEditorHeight(for text: String) -> CGFloat {
        let lineHeight: CGFloat = 17
        let verticalPadding: CGFloat = 34
        let height = CGFloat(lineCount(in: text)) * lineHeight + verticalPadding
        return ProfileEditorSizing.clampedDefaultHeight(height)
    }

    private func dismissAllInputsFocus() {
        isNameFieldFocused = false
        NSApp.keyWindow?.makeFirstResponder(nil)
    }

    private func showToast(_ message: String) {
        toastTask?.cancel()
        withAnimation(.easeInOut(duration: 0.2)) {
            toastMessage = message
        }
        toastTask = Task {
            try? await Task.sleep(nanoseconds: 2_400_000_000)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                withAnimation(.easeInOut(duration: 0.2)) {
                    toastMessage = nil
                }
            }
        }
    }
}

private enum ProfileCodeField: Hashable {
    case config
    case auth
    case zshrc
}

private enum ProfileEditorSizing {
    static let minimumHeight: CGFloat = 118
    static let fallbackHeight: CGFloat = 180
    static let maximumDefaultHeight: CGFloat = 460
    static let maximumCustomHeight: CGFloat = 900
    static let resizeHandleHeight: CGFloat = 16

    static func clampedDefaultHeight(_ height: CGFloat) -> CGFloat {
        min(max(height, minimumHeight), maximumDefaultHeight)
    }

    static func clampedCustomHeight(_ height: CGFloat) -> CGFloat {
        min(max(height, minimumHeight), maximumCustomHeight)
    }
}

private struct ProfileResizeHandleView: NSViewRepresentable {
    let currentHeight: CGFloat
    let onResizeStart: () -> Void
    let onResize: (CGFloat) -> Void
    let onResizeEnd: () -> Void

    func makeNSView(context: Context) -> ResizeHandleNSView {
        let view = ResizeHandleNSView()
        view.currentHeight = currentHeight
        view.onResizeStart = onResizeStart
        view.onResize = onResize
        view.onResizeEnd = onResizeEnd
        return view
    }

    func updateNSView(_ nsView: ResizeHandleNSView, context: Context) {
        nsView.currentHeight = currentHeight
        nsView.onResizeStart = onResizeStart
        nsView.onResize = onResize
        nsView.onResizeEnd = onResizeEnd
    }

    final class ResizeHandleNSView: NSView {
        var currentHeight: CGFloat = ProfileEditorSizing.fallbackHeight
        var onResizeStart: (() -> Void)?
        var onResize: ((CGFloat) -> Void)?
        var onResizeEnd: (() -> Void)?

        private var trackingArea: NSTrackingArea?
        private var startHeight: CGFloat?
        private var startMouseY: CGFloat?

        override init(frame frameRect: NSRect) {
            super.init(frame: frameRect)
            wantsLayer = true
        }

        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        override var acceptsFirstResponder: Bool {
            true
        }

        override func hitTest(_ point: NSPoint) -> NSView? {
            bounds.contains(point) ? self : nil
        }

        override func updateTrackingAreas() {
            super.updateTrackingAreas()

            if let trackingArea {
                removeTrackingArea(trackingArea)
            }

            let area = NSTrackingArea(
                rect: bounds,
                options: [.mouseEnteredAndExited, .mouseMoved, .cursorUpdate, .activeInKeyWindow, .inVisibleRect],
                owner: self,
                userInfo: nil
            )
            addTrackingArea(area)
            trackingArea = area
        }

        override func resetCursorRects() {
            super.resetCursorRects()
            addCursorRect(bounds, cursor: .resizeUpDown)
        }

        override func cursorUpdate(with event: NSEvent) {
            NSCursor.resizeUpDown.set()
        }

        override func mouseEntered(with event: NSEvent) {
            NSCursor.resizeUpDown.set()
        }

        override func mouseMoved(with event: NSEvent) {
            NSCursor.resizeUpDown.set()
        }

        override func mouseDown(with event: NSEvent) {
            window?.makeFirstResponder(self)
            NSCursor.resizeUpDown.set()
            startHeight = currentHeight
            startMouseY = event.locationInWindow.y
            onResizeStart?()
        }

        override func mouseDragged(with event: NSEvent) {
            NSCursor.resizeUpDown.set()
            guard let startHeight, let startMouseY else { return }
            let delta = startMouseY - event.locationInWindow.y
            onResize?(ProfileEditorSizing.clampedCustomHeight(startHeight + delta))
        }

        override func mouseUp(with event: NSEvent) {
            startHeight = nil
            startMouseY = nil
            NSCursor.resizeUpDown.set()
            onResizeEnd?()
        }
    }
}

private struct HighlightedProfileCodeEditor: NSViewRepresentable {

    @Binding var text: String
    @Binding var measuredHeight: CGFloat
    let fileType: FileType
    let isDarkMode: Bool
    let shouldMeasureHeight: Bool

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: HighlightedProfileCodeEditor
        var highlighter: SyntaxHighlighter?
        var isUpdatingFromSwiftUI = false
        var isComposingMarkedText = false
        var lastHighlightedFileType: FileType?
        var lastHighlightedIsDarkMode: Bool?
        var lastMeasuredTextHash: Int?
        var pendingHighlightTask: Task<Void, Never>?

        init(_ parent: HighlightedProfileCodeEditor) {
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

            let finishedMarkedText = isComposingMarkedText
            isComposingMarkedText = false

            if parent.text != textView.string {
                parent.text = textView.string
            }

            if finishedMarkedText {
                scheduleHighlighting(for: textView)
            } else {
                scheduleHighlighting(for: textView)
            }
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
            let clampedHeight = ProfileEditorSizing.clampedDefaultHeight(naturalHeight)

            if abs(parent.measuredHeight - clampedHeight) > 1 {
                parent.measuredHeight = clampedHeight
            }
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

        let textView = NSTextView(frame: NSRect(x: 0, y: 0, width: 100, height: 100))
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
        guard let textView = scrollView.documentView as? NSTextView else { return }

        context.coordinator.parent = self

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
        isDarkMode ? NSColor(white: 0.12, alpha: 1) : NSColor(white: 0.985, alpha: 1)
    }

    private var editorTextColor: NSColor {
        isDarkMode ? NSColor(white: 0.92, alpha: 1) : NSColor(white: 0.10, alpha: 1)
    }
}
