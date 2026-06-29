//
//  ClaudeProfileEditorView.swift
//  AgentConfig
//

import SwiftUI
import AppKit

struct ClaudeProfileEditorView: View {

    @ObservedObject var viewModel: ClaudeProfileViewModel
    @Environment(\.colorScheme) private var colorScheme
    @FocusState private var isNameFieldFocused: Bool

    @State private var toastMessage: String?
    @State private var toastTask: Task<Void, Never>?
    @State private var measuredEditorHeights: [ClaudeProfileCodeField: CGFloat] = [:]
    @State private var customEditorHeights: [ClaudeProfileCodeField: CGFloat] = [:]
    @State private var resizingFields: Set<ClaudeProfileCodeField> = []
    @State private var pendingDeleteProfile: ClaudeProfile?
    @State private var editingProfileName: String = ""

    private let profileNameMaxLength = 15

    var body: some View {
        VStack(spacing: 0) {
            if let profile = viewModel.selectedProfile {
                profileToolbar(profile: profile)

                ScrollView {
                    VStack(spacing: 12) {
                        codeCard(
                            title: "~/.claude/settings.json",
                            language: "JSON",
                            subtitle: nil,
                            fileType: .json,
                            field: .settings,
                            textValue: profile.settingsText,
                            text: settingsBinding(for: profile.id)
                        )

                        codeCard(
                            title: "~/.claude.json",
                            language: "JSON",
                            subtitle: "应用时仅覆盖真实文件中的对应字段",
                            fileType: .json,
                            field: .claudeJSON,
                            textValue: profile.claudeJSONText,
                            text: claudeJSONBinding(for: profile.id)
                        )

                        codeCard(
                            title: "~/.zshrc",
                            language: "Shell",
                            subtitle: "仅管理 AgentConfig Claude Profile 标记块",
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
            customEditorHeights = savedEditorHeights(for: viewModel.selectedProfile)
            resizingFields = []
            editingProfileName = viewModel.selectedProfile?.name ?? ""
        }
        .onAppear {
            editingProfileName = viewModel.selectedProfile?.name ?? ""
            customEditorHeights = savedEditorHeights(for: viewModel.selectedProfile)
        }
        .alert(item: $pendingDeleteProfile) { profile in
            Alert(
                title: Text("删除 Claude Profile？"),
                message: Text("将删除“\(profile.name.isEmpty ? "未命名配置" : profile.name)”。此操作不会修改已经写入磁盘的 Claude 配置文件。"),
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

    private func profileToolbar(profile: ClaudeProfile) -> some View {
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
            .help("应用当前配置")
        }
        .padding(.horizontal, 12)
        .frame(height: 48)
        .background(Color(nsColor: .windowBackgroundColor))
        .overlay(Divider(), alignment: .bottom)
    }

    private func statusPill(for profile: ClaudeProfile) -> some View {
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
        subtitle: String?,
        fileType: FileType,
        field: ClaudeProfileCodeField,
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

                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }

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

            ClaudeProfileCodeEditor(
                text: text,
                measuredHeight: measuredHeightBinding(for: field),
                fileType: fileType,
                isDarkMode: colorScheme == .dark,
                shouldMeasureHeight: customEditorHeights[field] == nil && !resizingFields.contains(field),
                currentHeight: editorHeight(for: field),
                onResizeStart: {
                    resizingFields.insert(field)
                },
                onResize: { newHeight in
                    let clampedHeight = ClaudeProfileEditorSizing.clampedCustomHeight(newHeight)
                    var transaction = Transaction()
                    transaction.disablesAnimations = true
                    withTransaction(transaction) {
                        customEditorHeights[field] = clampedHeight
                    }
                    saveEditorHeight(clampedHeight, for: field)
                },
                onResizeEnd: {
                    resizingFields.remove(field)
                }
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
        .onAppear {
            if measuredEditorHeights[field] == nil {
                measuredEditorHeights[field] = estimatedEditorHeight(for: field, text: textValue)
            }
        }
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

    private func profileNameFieldWidth(for name: String) -> CGFloat {
        let displayText = name.isEmpty ? "配置名称" : name
        let font = NSFont.systemFont(ofSize: 13, weight: .semibold)
        let measuredWidth = ceil((displayText as NSString).size(withAttributes: [.font: font]).width)
        return min(max(measuredWidth + 10, 50), 240)
    }

    private var nameFieldBackgroundColor: Color {
        Color(nsColor: .controlBackgroundColor).opacity(0.65)
    }

    private var deleteButtonBackgroundColor: Color {
        Color(red: 0.84, green: 0.16, blue: 0.20)
    }

    private var applyButtonBackgroundColor: Color {
        Color.accentColor
    }

    private func settingsBinding(for id: UUID) -> Binding<String> {
        Binding(
            get: { viewModel.profiles.first { $0.id == id }?.settingsText ?? "" },
            set: { viewModel.updateSelected(settingsText: $0) }
        )
    }

    private func claudeJSONBinding(for id: UUID) -> Binding<String> {
        Binding(
            get: { viewModel.profiles.first { $0.id == id }?.claudeJSONText ?? "" },
            set: { viewModel.updateSelected(claudeJSONText: $0) }
        )
    }

    private func zshrcBinding(for id: UUID) -> Binding<String> {
        Binding(
            get: { viewModel.profiles.first { $0.id == id }?.zshrcText ?? "" },
            set: { viewModel.updateSelected(zshrcText: $0) }
        )
    }

    private func measuredHeightBinding(for field: ClaudeProfileCodeField) -> Binding<CGFloat> {
        Binding(
            get: { measuredEditorHeights[field] ?? ClaudeProfileEditorSizing.defaultHeight(for: field) },
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

    private func editorHeight(for field: ClaudeProfileCodeField) -> CGFloat {
        if let customHeight = customEditorHeights[field] {
            return ClaudeProfileEditorSizing.clampedCustomHeight(customHeight)
        }

        let measuredHeight = measuredEditorHeights[field] ?? ClaudeProfileEditorSizing.defaultHeight(for: field)
        return ClaudeProfileEditorSizing.defaultHeight(for: field, measuredHeight: measuredHeight)
    }

    private func savedEditorHeights(for profile: ClaudeProfile?) -> [ClaudeProfileCodeField: CGFloat] {
        guard let profile else { return [:] }

        var heights: [ClaudeProfileCodeField: CGFloat] = [:]
        if let height = profile.settingsEditorHeight {
            heights[.settings] = ClaudeProfileEditorSizing.clampedCustomHeight(CGFloat(height))
        }
        if let height = profile.claudeJSONEditorHeight {
            heights[.claudeJSON] = ClaudeProfileEditorSizing.clampedCustomHeight(CGFloat(height))
        }
        if let height = profile.zshrcEditorHeight {
            heights[.zshrc] = ClaudeProfileEditorSizing.clampedCustomHeight(CGFloat(height))
        }
        return heights
    }

    private func saveEditorHeight(_ height: CGFloat, for field: ClaudeProfileCodeField) {
        let storedHeight = Double(height)
        switch field {
        case .settings:
            viewModel.updateSelectedEditorHeight(settingsEditorHeight: storedHeight)
        case .claudeJSON:
            viewModel.updateSelectedEditorHeight(claudeJSONEditorHeight: storedHeight)
        case .zshrc:
            viewModel.updateSelectedEditorHeight(zshrcEditorHeight: storedHeight)
        }
    }

    private func statusText(for profile: ClaudeProfile) -> String {
        if profile.isDirty {
            return "未应用修改"
        }
        if profile.isActive {
            return "当前生效"
        }
        return "可应用"
    }

    private func profileStateColor(for profile: ClaudeProfile) -> Color {
        if profile.isDirty {
            return .orange
        }
        if profile.isActive {
            return .green
        }
        return .secondary
    }

    private func languageTagStyle(for field: ClaudeProfileCodeField) -> (foreground: Color, background: Color) {
        switch field {
        case .settings, .claudeJSON:
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

    private func estimatedEditorHeight(for field: ClaudeProfileCodeField, text: String) -> CGFloat {
        let lineHeight: CGFloat = 17
        let verticalPadding: CGFloat = 34
        let height = CGFloat(lineCount(in: text)) * lineHeight + verticalPadding
        return ClaudeProfileEditorSizing.defaultHeight(for: field, measuredHeight: height)
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

private enum ClaudeProfileCodeField: Hashable {
    case settings
    case claudeJSON
    case zshrc

    var defaultHeight: CGFloat {
        switch self {
        case .settings:
            return 220
        case .claudeJSON:
            return 220
        case .zshrc:
            return 150
        }
    }
}

private enum ClaudeProfileEditorSizing {
    static let minimumHeight: CGFloat = 118
    static let fallbackHeight: CGFloat = ClaudeProfileCodeField.settings.defaultHeight
    static let maximumDefaultHeight: CGFloat = 460
    static let maximumCustomHeight: CGFloat = 900
    static let resizeCursorHotZoneHeight: CGFloat = 14

    static func clampedDefaultHeight(_ height: CGFloat) -> CGFloat {
        min(max(height, minimumHeight), maximumDefaultHeight)
    }

    static func clampedCustomHeight(_ height: CGFloat) -> CGFloat {
        min(max(height, minimumHeight), maximumCustomHeight)
    }

    static func defaultHeight(for field: ClaudeProfileCodeField) -> CGFloat {
        clampedDefaultHeight(field.defaultHeight)
    }

    static func defaultHeight(for field: ClaudeProfileCodeField, measuredHeight: CGFloat) -> CGFloat {
        max(defaultHeight(for: field), clampedDefaultHeight(measuredHeight))
    }
}

private struct ClaudeProfileCodeEditor: NSViewRepresentable {

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
        var parent: ClaudeProfileCodeEditor
        var highlighter: SyntaxHighlighter?
        var isUpdatingFromSwiftUI = false
        var isComposingMarkedText = false
        var lastHighlightedFileType: FileType?
        var lastHighlightedIsDarkMode: Bool?
        var lastMeasuredTextHash: Int?
        var pendingHighlightTask: Task<Void, Never>?

        init(_ parent: ClaudeProfileCodeEditor) {
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
            let clampedHeight = ClaudeProfileEditorSizing.clampedDefaultHeight(naturalHeight)

            if abs(parent.measuredHeight - clampedHeight) > 1 {
                parent.measuredHeight = clampedHeight
            }
        }
    }

    final class ResizableTextView: CommentingTextView {
        var currentHeight: CGFloat = ClaudeProfileEditorSizing.fallbackHeight
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
            onResize?(ClaudeProfileEditorSizing.clampedCustomHeight(startHeight + delta))
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
            let hotZoneHeight = min(ClaudeProfileEditorSizing.resizeCursorHotZoneHeight, visibleRect.height)
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
        isDarkMode ? NSColor(white: 0.12, alpha: 1) : NSColor(white: 0.985, alpha: 1)
    }

    private var editorTextColor: NSColor {
        isDarkMode ? NSColor(white: 0.92, alpha: 1) : NSColor(white: 0.10, alpha: 1)
    }
}
