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
/// - 格式化失败时在工具栏下方内联显示错误位置信息
///
/// _Requirements: 3.4, 3.5, 7.1_
struct EditorToolbarView: View {

    // MARK: - Dependencies

    /// 编辑器 ViewModel，提供文件状态、格式化功能
    @ObservedObject var editorViewModel: EditorViewModel

    // MARK: - Callbacks

    /// 点击搜索按钮时的回调
    var onShowSearch: (() -> Void)?
    var isSearchBarVisible: Bool = false
    var onCloseSearch: (() -> Void)?

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
                    if isSearchBarVisible {
                        SearchBarView(
                            isVisible: .constant(true),
                            viewModel: editorViewModel,
                            onClose: { onCloseSearch?() },
                            style: .toolbar
                        )
                        .frame(maxWidth: 430, alignment: .trailing)
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                    } else {
                        searchButton
                            .transition(.opacity)
                    }

                    if isJSONFile {
                        formatButton
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
        toolbarIconButton(systemName: "magnifyingglass", isActive: isSearchBarVisible) {
            onShowSearch?()
        }
        .help(L10n.tr("toolbar.search", value: "Search"))
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
        toolbarIconButton(systemName: "curlybraces", isActive: false) {
            performFormat()
        }
        .help(L10n.tr("toolbar.format.help", value: "Format JSON with 4-space indentation"))
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
            .help(L10n.tr("toolbar.dismissError", value: "Dismiss error"))
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
            ?? L10n.tr("toolbar.noFile", value: "No file open")
    }

    /// 当前文件是否为 JSON 系列类型
    private var isJSONFile: Bool {
        editorViewModel.currentFile?.fileType.supportsStrictJSONFormatting ?? false
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
            return L10n.format(
                "toolbar.formatError.withLocation",
                value: "JSON format error (line %d, column %d): %@",
                line,
                column,
                message
            )
        } else {
            return L10n.format(
                "toolbar.formatError.generic",
                value: "JSON format error: %@",
                message
            )
        }
    }
}


private extension Color {
    static var editorToolbarBackground: Color {
        Color(nsColor: .windowBackgroundColor)
    }

    static var editorTabBackground: Color {
        Color(nsColor: .textBackgroundColor)
    }
}
