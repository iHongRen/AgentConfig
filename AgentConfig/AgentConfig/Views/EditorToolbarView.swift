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

    var isExamplesVisible: Bool = false
    var hasExamples: Bool = false

    // MARK: - Callbacks

    /// 点击搜索按钮时的回调
    var onShowSearch: (() -> Void)?

    var onToggleExamples: (() -> Void)?

    /// 点击"历史记录"按钮时的回调
    var onShowHistory: (() -> Void)?

    // MARK: - Private State

    /// 格式化错误信息（格式化失败时显示）
    @State private var formatError: FormatErrorInfo? = nil

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                tabView
                    .layoutPriority(0)

                Spacer(minLength: 8)

                HStack(spacing: 8) {
                    searchButton
                    examplesButton

                    if isJSONFile {
                        formatButton
                    }

                    if gitViewModel.isGitRepo {
                        historyButton
                    }
                }
                .fixedSize(horizontal: true, vertical: false)
                .layoutPriority(2)
            }
            .frame(height: 39)
            .padding(.horizontal, 10)
            .background(Color.editorToolbarBackground)

            Divider()

            if let error = formatError {
                formatErrorBanner(error: error)
            }
        }
    }

    // MARK: - Subviews

    private var tabView: some View {
        HStack(spacing: 8) {
            Image(systemName: "doc.text")
                .font(.system(size: 14))
                .foregroundStyle(.secondary)

            Text(currentFileName)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .truncationMode(.middle)

            if editorViewModel.isModified {
                Circle()
                    .fill(Color(nsColor: .secondaryLabelColor))
                    .frame(width: 8, height: 8)
            }
        }
        .padding(.horizontal, 13)
        .frame(height: 39)
        .frame(minWidth: 0, idealWidth: 180, maxWidth: 280, alignment: .leading)
        .clipped()
        .background(
            Rectangle()
                .fill(Color.editorTabBackground)
        )
        .overlay(Divider(), alignment: .trailing)
    }

    private var searchButton: some View {
        toolbarIconButton(systemName: "magnifyingglass", isActive: false) {
            onShowSearch?()
        }
        .help("搜索")
    }

    private var examplesButton: some View {
        toolbarIconButton(systemName: "sidebar.right", isActive: isExamplesVisible) {
            onToggleExamples?()
        }
        .disabled(!hasExamples)
        .opacity(hasExamples ? 1 : 0.45)
        .help(hasExamples ? "显示配置示例" : "当前文件暂无示例")
    }

    private func toolbarIconButton(systemName: String, isActive: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(isActive ? Color.white : Color.primary)
                .frame(width: 28, height: 28)
                .background(
                    RoundedRectangle(cornerRadius: 7)
                        .fill(isActive ? Color.accentColor : Color(nsColor: .controlBackgroundColor))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 7)
                        .strokeBorder(Color(nsColor: .separatorColor).opacity(isActive ? 0 : 0.8))
                )
        }
        .buttonStyle(.plain)
    }

    /// 格式化按钮
    private var formatButton: some View {
        toolbarIconButton(systemName: "text.alignleft", isActive: false) {
            performFormat()
        }
        .help(NSLocalizedString("toolbar.format.help", value: "将 JSON 内容格式化为 4 空格缩进", comment: "Format button tooltip"))
    }

    /// 历史记录按钮
    private var historyButton: some View {
        toolbarIconButton(systemName: "clock.arrow.circlepath", isActive: false) {
            onShowHistory?()
        }
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

    /// 当前文件是否为 JSON 系列类型
    private var isJSONFile: Bool {
        guard let file = editorViewModel.currentFile else { return false }
        switch file.fileType {
        case .json, .jsonc, .json5, .jsonl:
            return true
        default:
            return false
        }
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
        hasExamples: true,
        onShowSearch: {},
        onToggleExamples: {},
        onShowHistory: { print("Show history") }
    )
    .frame(width: 600)
}

private extension Color {
    static var editorToolbarBackground: Color {
        Color(nsColor: .windowBackgroundColor)
    }

    static var editorTabBackground: Color {
        Color(nsColor: .textBackgroundColor)
    }
}
