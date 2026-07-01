//
//  AgentProfileEditorView.swift
//  AgentConfig
//

import SwiftUI
import AppKit

struct AgentProfileEditorView: View {

    let profile: AgentProfileEditorProfile?

    @Environment(\.colorScheme) private var colorScheme
    @FocusState private var isNameFieldFocused: Bool

    @State private var toastMessage: String?
    @State private var toastTask: Task<Void, Never>?
    @State private var measuredEditorHeights: [String: CGFloat] = [:]
    @State private var customEditorHeights: [String: CGFloat] = [:]
    @State private var resizingFields: Set<String> = []
    @State private var isDeleteConfirmationPresented = false
    @State private var editingProfileName: String = ""

    var body: some View {
        VStack(spacing: 0) {
            if let profile {
                profileToolbar(profile: profile)

                ScrollView {
                    VStack(spacing: 12) {
                        ForEach(profile.fields) { field in
                            codeCard(field)
                        }
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
        .onChange(of: profile?.id) { _, _ in
            syncState(with: profile)
        }
        .onChange(of: profile?.name) { _, newName in
            editingProfileName = newName ?? ""
        }
        .onAppear {
            syncState(with: profile)
        }
        .onDisappear {
            toastTask?.cancel()
        }
        .alert(isPresented: $isDeleteConfirmationPresented) {
            let confirmation = profile?.deleteConfirmation
                ?? AgentProfileEditorDeleteConfirmation(title: "", message: "")
            return Alert(
                title: Text(confirmation.title),
                message: Text(confirmation.message),
                primaryButton: .destructive(Text(L10n.tr("profile.delete", value: "Delete"))) {
                    guard let profile else { return }
                    showToast(profile.delete().message)
                },
                secondaryButton: .cancel(Text(L10n.tr("profile.cancel", value: "Cancel")))
            )
        }
    }

    private func profileToolbar(profile: AgentProfileEditorProfile) -> some View {
        HStack(spacing: 10) {
            Button {
                isNameFieldFocused = true
            } label: {
                HStack(spacing: 0) {
                    TextField(L10n.tr("profile.namePlaceholder", value: "Profile Name"), text: $editingProfileName)
                        .textFieldStyle(.plain)
                        .font(.system(size: 13, weight: .semibold))
                        .focused($isNameFieldFocused)
                        .frame(width: profileNameFieldWidth(for: editingProfileName), alignment: .leading)
                        .onChange(of: editingProfileName) { _, newValue in
                            let truncated = String(newValue.prefix(profile.nameMaxLength))
                            if truncated != newValue {
                                editingProfileName = truncated
                            }
                            profile.updateName(truncated)
                        }
                        .onSubmit {
                            let truncated = String(editingProfileName.prefix(profile.nameMaxLength))
                            if truncated != editingProfileName {
                                editingProfileName = truncated
                            }
                            profile.updateName(truncated)
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

            statusPill(for: profile.status)

            Button(role: .destructive) {
                isDeleteConfirmationPresented = true
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
            .disabled(!profile.canDelete)
            .help(L10n.tr("profile.deleteCurrent", value: "Delete current profile"))

            Button {
                Task {
                    showToast((await profile.apply()).message)
                }
            } label: {
                Label(L10n.tr("profile.apply", value: "Apply"), systemImage: "checkmark.circle")
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
            .help(L10n.tr("profile.applyCurrent", value: "Apply current profile"))
        }
        .padding(.horizontal, 12)
        .frame(height: 48)
        .background(Color(nsColor: .windowBackgroundColor))
        .overlay(Divider(), alignment: .bottom)
    }

    private func statusPill(for status: AgentProfileEditorStatus) -> some View {
        HStack(spacing: 6) {
            Circle()
                .fill(status.color)
                .frame(width: 7, height: 7)

            Text(status.text)
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

    private func codeCard(_ field: AgentProfileEditorField) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Text(field.title)
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .truncationMode(.middle)

                Text(field.language)
                    .font(.system(size: 9, weight: .semibold, design: .monospaced))
                    .foregroundStyle(field.accentColor)
                    .padding(.horizontal, 8)
                    .frame(height: 18)
                    .background(
                        Capsule()
                            .fill(field.accentColor.opacity(0.16))
                    )

                Text(L10n.format("profile.lineCount", value: "%d lines", lineCount(in: field.text.wrappedValue)))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                if let helpText = field.helpText {
                    ProfileFieldHelpButton(title: field.title, message: helpText)
                }

                Spacer(minLength: 8)

                Button(L10n.tr("profile.copy", value: "Copy")) {
                    if !field.text.wrappedValue.isEmpty {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(field.text.wrappedValue, forType: .string)
                        showToast(L10n.tr("profile.copyToast", value: "Copied current configuration snippet"))
                    }
                }
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Color(red: 0.6, green: 0.6, blue: 0.6))
                .frame(height: 24)
                .buttonStyle(.plain)
                .help(L10n.tr("profile.copyHelp", value: "Copy"))
            }
            .padding(.horizontal, 12)
            .frame(height: 32)
            .background(Color(nsColor: .windowBackgroundColor))

            Divider()

            AgentProfileCodeEditor(
                text: field.text,
                measuredHeight: measuredHeightBinding(for: field),
                fileType: field.fileType,
                isDarkMode: colorScheme == .dark,
                shouldMeasureHeight: customEditorHeights[field.id] == nil && !resizingFields.contains(field.id),
                currentHeight: editorHeight(for: field),
                onResizeStart: {
                    resizingFields.insert(field.id)
                },
                onResize: { newHeight in
                    let clampedHeight = AgentProfileEditorSizing.clampedCustomHeight(newHeight)
                    var transaction = Transaction()
                    transaction.disablesAnimations = true
                    withTransaction(transaction) {
                        customEditorHeights[field.id] = clampedHeight
                    }
                    field.onPersistHeight(Double(clampedHeight))
                },
                onResizeEnd: {
                    resizingFields.remove(field.id)
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
            if measuredEditorHeights[field.id] == nil {
                measuredEditorHeights[field.id] = estimatedEditorHeight(for: field)
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "rectangle.stack")
                .font(.system(size: 42))
                .foregroundStyle(.tertiary)
            Text(L10n.tr("profile.empty", value: "Select a profile"))
                .font(.title3)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func measuredHeightBinding(for field: AgentProfileEditorField) -> Binding<CGFloat> {
        Binding(
            get: { measuredEditorHeights[field.id] ?? AgentProfileEditorSizing.defaultHeight(for: field) },
            set: { newHeight in
                guard customEditorHeights[field.id] == nil,
                      !resizingFields.contains(field.id) else { return }

                var transaction = Transaction()
                transaction.disablesAnimations = true
                withTransaction(transaction) {
                    measuredEditorHeights[field.id] = newHeight
                }
            }
        )
    }

    private func editorHeight(for field: AgentProfileEditorField) -> CGFloat {
        if let customHeight = customEditorHeights[field.id] {
            return AgentProfileEditorSizing.clampedCustomHeight(customHeight)
        }

        let measuredHeight = measuredEditorHeights[field.id] ?? AgentProfileEditorSizing.defaultHeight(for: field)
        return AgentProfileEditorSizing.defaultHeight(for: field, measuredHeight: measuredHeight)
    }

    private func profileNameFieldWidth(for name: String) -> CGFloat {
        let displayText = name.isEmpty ? L10n.tr("profile.namePlaceholder", value: "Profile Name") : name
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

    private func lineCount(in text: String) -> Int {
        max(1, text.split(separator: "\n", omittingEmptySubsequences: false).count)
    }

    private func estimatedEditorHeight(for field: AgentProfileEditorField) -> CGFloat {
        let lineHeight: CGFloat = 17
        let verticalPadding: CGFloat = 34
        let height = CGFloat(lineCount(in: field.text.wrappedValue)) * lineHeight + verticalPadding
        return AgentProfileEditorSizing.defaultHeight(for: field, measuredHeight: height)
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

    private func savedEditorHeights(for profile: AgentProfileEditorProfile?) -> [String: CGFloat] {
        guard let profile else { return [:] }

        var heights: [String: CGFloat] = [:]
        for field in profile.fields {
            if let persistedHeight = field.persistedHeight {
                heights[field.id] = AgentProfileEditorSizing.clampedCustomHeight(CGFloat(persistedHeight))
            }
        }
        return heights
    }

    private func syncState(with profile: AgentProfileEditorProfile?) {
        measuredEditorHeights = [:]
        customEditorHeights = savedEditorHeights(for: profile)
        resizingFields = []
        editingProfileName = profile?.name ?? ""
        isDeleteConfirmationPresented = false
    }
}

struct AgentProfileEditorProfile {
    let id: UUID
    let name: String
    let nameMaxLength: Int
    let status: AgentProfileEditorStatus
    let canDelete: Bool
    let deleteConfirmation: AgentProfileEditorDeleteConfirmation
    let fields: [AgentProfileEditorField]
    let updateName: (String) -> Void
    let delete: () -> AgentProfileEditorActionResult
    let apply: () async -> AgentProfileEditorActionResult
}

struct AgentProfileEditorField: Identifiable {
    let id: String
    let title: String
    let language: String
    let helpText: String?
    let fileType: FileType
    let accentColor: Color
    let defaultHeight: CGFloat
    let text: Binding<String>
    let persistedHeight: Double?
    let onPersistHeight: (Double) -> Void
}

struct AgentProfileEditorStatus {
    let text: String
    let color: Color
}

struct AgentProfileEditorDeleteConfirmation {
    let title: String
    let message: String
}

struct AgentProfileEditorActionResult {
    let isSuccess: Bool
    let message: String

    static func success(_ message: String) -> AgentProfileEditorActionResult {
        AgentProfileEditorActionResult(isSuccess: true, message: message)
    }

    static func failure(_ message: String) -> AgentProfileEditorActionResult {
        AgentProfileEditorActionResult(isSuccess: false, message: message)
    }
}
