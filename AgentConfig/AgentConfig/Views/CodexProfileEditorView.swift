//
//  CodexProfileEditorView.swift
//  AgentConfig
//

import SwiftUI
import AppKit

struct CodexProfileEditorView: View {

    @ObservedObject var viewModel: CodexProfileViewModel

    @State private var isShowingPreview = false
    @State private var toastMessage: String?
    @State private var toastTask: Task<Void, Never>?

    var body: some View {
        VStack(spacing: 0) {
            header

            if let profile = viewModel.selectedProfile {
                ScrollView {
                    VStack(spacing: 14) {
                        codeCard(title: "~/.codex/config.toml", text: configBinding(for: profile.id))
                        codeCard(title: "~/.codex/auth.json", text: authBinding(for: profile.id))
                        codeCard(title: "~/.zshrc", text: zshrcBinding(for: profile.id))
                    }
                    .padding(16)
                }
                footer(profile: profile)
            } else {
                emptyState
            }
        }
        .background(Color(nsColor: .textBackgroundColor))
        .sheet(isPresented: $isShowingPreview) {
            previewSheet
        }
        .overlay(alignment: .bottom) {
            if let toastMessage {
                Text(toastMessage)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(Capsule().fill(Color(nsColor: .labelColor).opacity(0.78)))
                    .padding(.bottom, 48)
            }
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Codex Profile")
                    .font(.system(size: 18, weight: .semibold))
                Text("先预览配置，再应用到 Codex 文件和 .zshrc 托管区块。")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if let profile = viewModel.selectedProfile {
                TextField("配置名称", text: nameBinding(for: profile.id))
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 240)
            }
        }
        .padding(.horizontal, 16)
        .frame(height: 64)
        .background(Color(nsColor: .windowBackgroundColor))
        .overlay(Divider(), alignment: .bottom)
    }

    private func codeCard(title: String, text: Binding<String>) -> some View {
        VStack(spacing: 0) {
            HStack {
                Text(title)
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Color(nsColor: .secondaryLabelColor))
                    .lineLimit(1)
                    .truncationMode(.middle)

                Spacer()

                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(text.wrappedValue, forType: .string)
                    showToast("已复制当前配置片段")
                } label: {
                    Image(systemName: "doc.on.doc")
                        .frame(width: 26, height: 26)
                }
                .buttonStyle(.plain)
                .help("复制")
            }
            .padding(.horizontal, 12)
            .frame(height: 36)
            .background(Color(nsColor: .windowBackgroundColor))

            TextEditor(text: text)
                .font(.system(size: 13, design: .monospaced))
                .scrollContentBackground(.hidden)
                .background(Color(nsColor: .textBackgroundColor))
                .frame(minHeight: 150)
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
        }
        .background(Color(nsColor: .textBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(Color(nsColor: .separatorColor).opacity(0.8))
        )
    }

    private func footer(profile: CodexProfile) -> some View {
        HStack(spacing: 10) {
            Circle()
                .fill(profile.isDirty ? Color.orange : (profile.isActive ? Color.green : Color.secondary))
                .frame(width: 9, height: 9)

            Text(statusText(for: profile))
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)

            Spacer()

            Button("Preview Changes") {
                isShowingPreview = true
            }

            Button("Apply Profile") {
                isShowingPreview = true
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(.horizontal, 16)
        .frame(height: 48)
        .background(Color(nsColor: .windowBackgroundColor))
        .overlay(Divider(), alignment: .top)
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "rectangle.stack")
                .font(.system(size: 42))
                .foregroundStyle(.tertiary)
            Text("选择左侧 Codex Profile")
                .font(.title3)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var previewSheet: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                Text("预览将要应用的配置")
                    .font(.title3)
                    .fontWeight(.semibold)
                Text("会写入 Codex 配置文件，并替换 .zshrc 中 AgentConfig 管理的区块。")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(18)

            List(viewModel.previewItems) { item in
                HStack(spacing: 10) {
                    Image(systemName: "doc.text")
                        .foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(item.path)
                            .font(.system(size: 12, weight: .semibold, design: .monospaced))
                        Text("\(item.lineCount) 行，\(item.action)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
            }
            .frame(minHeight: 180)

            if let error = viewModel.validateSelected() {
                Text(error)
                    .font(.callout)
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 18)
                    .padding(.bottom, 8)
            }

            HStack {
                Button("取消") {
                    isShowingPreview = false
                }

                Spacer()

                Button("确认应用") {
                    Task {
                        let success = await viewModel.applySelected()
                        isShowingPreview = false
                        showToast(success ? "已应用 Codex Profile" : (viewModel.lastErrorMessage ?? "应用失败"))
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(viewModel.validateSelected() != nil)
            }
            .padding(18)
        }
        .frame(width: 560, height: 420)
    }

    private func nameBinding(for id: UUID) -> Binding<String> {
        Binding(
            get: {
                viewModel.profiles.first { $0.id == id }?.name ?? ""
            },
            set: { newValue in
                viewModel.updateSelected(name: newValue)
            }
        )
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

    private func statusText(for profile: CodexProfile) -> String {
        if profile.isDirty {
            return "「\(profile.name)」有未应用修改。"
        }
        if profile.isActive {
            return "「\(profile.name)」是当前已应用 Profile。"
        }
        return "正在预览「\(profile.name)」。"
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
