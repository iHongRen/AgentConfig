//
//  EditorToolbarView.swift
//  AgentConfig
//
//  Created by cxy on 2026/5/11.
//

import SwiftUI

// MARK: - EditorToolbarView

/// 编辑器顶部工具栏
///
/// 功能：
/// - 显示当前文件名（有未保存修改时显示"● 文件名"）
/// - JSON/JSONC 文件显示"格式化"按钮
/// - Git 仓库文件显示"历史记录"按钮
/// - 格式化失败时在工具栏下方内联显示错误位置信息
///
/// _Requirements: 3.4, 3.5, 7.1_
struct EditorToolbarView: View {

    // MARK: - Dependencies

    /// 编辑器 ViewModel，提供文件状态、格式化功能
    @ObservedObject var editorViewModel: EditorViewModel

    /// Git ViewModel，提供 Git 仓库状态
    @ObservedObject var gitViewModel: GitViewModel

    // MARK: - Callbacks

    /// 点击"历史记录"按钮时的回调
    var onShowHistory: (() -> Void)?

    // MARK: - Private State

    /// 格式化错误信息（格式化失败时显示）
    @State private var formatError: FormatErrorInfo? = nil

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            // 主工具栏行
            HStack(spacing: 8) {
                // 文件名（有未保存修改时显示"●"标记）
                fileNameLabel

                Spacer()

                // 格式化按钮（仅 JSON/JSONC 文件显示）
                if isJSONFile {
                    formatButton
                }

                // 历史记录按钮（仅 Git 仓库文件显示）
                if gitViewModel.isGitRepo {
                    historyButton
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Color(NSColor.windowBackgroundColor))

            // 分隔线
            Divider()

            // 格式化错误提示（格式化失败时内联显示）
            if let error = formatError {
                formatErrorBanner(error: error)
            }
        }
    }

    // MARK: - Subviews

    /// 文件名标签，有未保存修改时前缀"●"
    private var fileNameLabel: some View {
        HStack(spacing: 4) {
            if editorViewModel.isModified {
                Text("●")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }
            Text(currentFileName)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.primary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }

    /// 格式化按钮
    private var formatButton: some View {
        Button {
            performFormat()
        } label: {
            Label(
                NSLocalizedString("toolbar.format", value: "格式化", comment: "Format JSON button"),
                systemImage: "text.alignleft"
            )
            .font(.system(size: 12))
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .help(NSLocalizedString("toolbar.format.help", value: "将 JSON 内容格式化为 2 空格缩进", comment: "Format button tooltip"))
    }

    /// 历史记录按钮
    private var historyButton: some View {
        Button {
            onShowHistory?()
        } label: {
            Label(
                NSLocalizedString("toolbar.history", value: "历史记录", comment: "Git history button"),
                systemImage: "clock.arrow.circlepath"
            )
            .font(.system(size: 12))
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .help(NSLocalizedString("toolbar.history.help", value: "查看 Git 提交历史", comment: "History button tooltip"))
    }

    /// 格式化错误横幅（内联显示错误行列位置）
    @ViewBuilder
    private func formatErrorBanner(error: FormatErrorInfo) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.yellow)
                .font(.system(size: 12))

            Text(error.displayMessage)
                .font(.system(size: 12))
                .foregroundColor(.primary)
                .lineLimit(2)

            Spacer()

            // 关闭按钮
            Button {
                withAnimation(.easeOut(duration: 0.15)) {
                    formatError = nil
                }
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
            .help(NSLocalizedString("toolbar.dismissError", value: "关闭错误提示", comment: "Dismiss error button tooltip"))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color.yellow.opacity(0.12))
        .transition(.move(edge: .top).combined(with: .opacity))
    }

    // MARK: - Computed Properties

    /// 当前文件名，无文件时显示占位符
    private var currentFileName: String {
        editorViewModel.currentFile?.url.lastPathComponent
            ?? NSLocalizedString("toolbar.noFile", value: "未打开文件", comment: "Placeholder when no file is open")
    }

    /// 当前文件是否为 JSON 或 JSONC 类型
    private var isJSONFile: Bool {
        guard let file = editorViewModel.currentFile else { return false }
        return file.fileType == .json || file.fileType == .jsonc
    }

    // MARK: - Actions

    /// 执行 JSON 格式化，失败时显示内联错误
    private func performFormat() {
        // 清除上一次的错误
        formatError = nil

        do {
            try editorViewModel.formatJSON()
        } catch let appError as AppError {
            if case .jsonFormatError(let line, let column, let message) = appError {
                withAnimation(.easeIn(duration: 0.15)) {
                    formatError = FormatErrorInfo(line: line, column: column, message: message)
                }
            }
        } catch {
            // 其他未预期错误，显示通用提示
            withAnimation(.easeIn(duration: 0.15)) {
                formatError = FormatErrorInfo(
                    line: 0,
                    column: 0,
                    message: error.localizedDescription
                )
            }
        }
    }
}

// MARK: - FormatErrorInfo

/// 格式化错误信息，用于工具栏内联显示
private struct FormatErrorInfo: Equatable {
    let line: Int
    let column: Int
    let message: String

    /// 用于 UI 展示的格式化错误描述
    var displayMessage: String {
        if line > 0 {
            let template = NSLocalizedString(
                "toolbar.formatError.withLocation",
                value: "JSON 格式错误（第 %d 行，第 %d 列）：%@",
                comment: "JSON format error with line and column info"
            )
            return String(format: template, line, column, message)
        } else {
            let template = NSLocalizedString(
                "toolbar.formatError.generic",
                value: "JSON 格式错误：%@",
                comment: "Generic JSON format error"
            )
            return String(format: template, message)
        }
    }
}

// MARK: - Preview

#Preview("有文件 - JSON") {
    let editorVM = EditorViewModel()
    let gitVM = GitViewModel()

    return EditorToolbarView(
        editorViewModel: editorVM,
        gitViewModel: gitVM,
        onShowHistory: { print("Show history") }
    )
    .frame(width: 600)
}
