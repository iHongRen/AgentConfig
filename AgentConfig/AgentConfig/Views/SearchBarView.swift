//
//  SearchBarView.swift
//  AgentConfig
//
//  Created by cxy on 2026/5/11.
//

import SwiftUI

// MARK: - SearchBarView

/// 搜索栏视图，支持关键词搜索、上一个/下一个导航、大小写敏感开关
///
/// - 通过 `isVisible` 绑定控制显示/隐藏
/// - 绑定 `EditorViewModel` 的搜索相关属性
/// - 支持 Escape 键关闭搜索栏
/// - 无匹配时显示"未找到"提示（红色背景）
struct SearchBarView: View {

    // MARK: - Bindings

    /// 控制搜索栏是否可见
    @Binding var isVisible: Bool

    /// 绑定的 EditorViewModel
    @ObservedObject var viewModel: EditorViewModel

    // MARK: - Private State

    /// 搜索输入框焦点状态
    @FocusState private var isSearchFieldFocused: Bool
    @State private var isRegexEnabled = false

    // MARK: - Computed Properties

    /// 是否有搜索词但无匹配结果
    private var hasNoMatch: Bool {
        !viewModel.searchQuery.isEmpty && viewModel.searchResults.isEmpty
    }

    /// 匹配数量显示文字，如 "3/10" 或 "未找到"
    private var matchCountText: String {
        if viewModel.searchQuery.isEmpty {
            return ""
        }
        if viewModel.searchResults.isEmpty {
            return NSLocalizedString("search.no_match", comment: "未找到")
        }
        let current = viewModel.searchResults.isEmpty ? 0 : viewModel.currentSearchIndex + 1
        let total = viewModel.searchResults.count
        return "\(current)/\(total)"
    }

    // MARK: - Body

    var body: some View {
        if isVisible {
            HStack(spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.secondary)
                        .font(.system(size: 15))

                    TextField(
                        NSLocalizedString("search.placeholder", comment: "搜索"),
                        text: $viewModel.searchQuery
                    )
                    .textFieldStyle(.plain)
                    .font(.system(size: 15, weight: .medium))
                    .focused($isSearchFieldFocused)
                    .onSubmit {
                        viewModel.nextMatch()
                    }
                    .onChange(of: viewModel.searchQuery) { _, newValue in
                        viewModel.search(query: newValue, caseSensitive: viewModel.isCaseSensitive)
                    }

                    if !viewModel.searchQuery.isEmpty {
                        Button {
                            viewModel.searchQuery = ""
                            viewModel.search(query: "", caseSensitive: viewModel.isCaseSensitive)
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.secondary)
                                .font(.system(size: 15))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 10)
                .background(
                    RoundedRectangle(cornerRadius: 7)
                        .fill(Color(NSColor.textBackgroundColor))
                        .overlay(
                            RoundedRectangle(cornerRadius: 7)
                                .stroke(
                                    hasNoMatch ? Color.red : Color(NSColor.separatorColor),
                                    lineWidth: hasNoMatch ? 1.5 : 1
                                )
                        )
                )
                .frame(width: 268, height: 34)

                Toggle(isOn: $viewModel.isCaseSensitive) {
                    Text("区分大小写")
                        .font(.system(size: 13, weight: .medium))
                }
                .toggleStyle(.checkbox)
                .controlSize(.small)
                .help(NSLocalizedString("search.case_sensitive_tooltip", comment: "区分大小写"))
                .onChange(of: viewModel.isCaseSensitive) { _, newValue in
                    viewModel.search(query: viewModel.searchQuery, caseSensitive: newValue)
                }

                Toggle(isOn: $isRegexEnabled) {
                    Text("正则表达式")
                        .font(.system(size: 13, weight: .medium))
                }
                .toggleStyle(.checkbox)
                .controlSize(.small)
                .disabled(true)
                .help("当前搜索使用普通文本匹配")

                Spacer()

                Text(matchCountText)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(hasNoMatch ? .white : .primary)
                    .monospacedDigit()
                    .padding(.horizontal, hasNoMatch ? 8 : 0)
                    .padding(.vertical, hasNoMatch ? 3 : 0)
                    .background(
                        RoundedRectangle(cornerRadius: 4)
                            .fill(hasNoMatch ? Color.red : Color.clear)
                    )
                    .frame(minWidth: 58)
                    .animation(.easeInOut(duration: 0.15), value: hasNoMatch)

                Button {
                    viewModel.previousMatch()
                } label: {
                    Image(systemName: "chevron.up")
                        .font(.system(size: 17, weight: .semibold))
                        .frame(width: 34, height: 30)
                }
                .buttonStyle(.bordered)
                .disabled(viewModel.searchResults.isEmpty)
                .help(NSLocalizedString("search.previous", comment: "上一个匹配项"))
                .keyboardShortcut("g", modifiers: [.command, .shift])

                Button {
                    viewModel.nextMatch()
                } label: {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 17, weight: .semibold))
                        .frame(width: 34, height: 30)
                }
                .buttonStyle(.bordered)
                .disabled(viewModel.searchResults.isEmpty)
                .help(NSLocalizedString("search.next", comment: "下一个匹配项"))
                .keyboardShortcut("g", modifiers: .command)

                Button {
                    closeSearchBar()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 18, weight: .medium))
                        .frame(width: 30, height: 30)
                }
                .buttonStyle(.plain)
                .foregroundColor(.secondary)
                .help(NSLocalizedString("search.close", comment: "关闭搜索栏"))
            }
            .frame(height: 60)
            .padding(.horizontal, 16)
            .background(Color(NSColor.windowBackgroundColor))
            .overlay(
                Divider(),
                alignment: .bottom
            )
            .onAppear {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                    isSearchFieldFocused = true
                }
            }
            .onKeyPress(.escape) {
                closeSearchBar()
                return .handled
            }
            .transition(.move(edge: .top).combined(with: .opacity))
        }
    }

    // MARK: - Private Methods

    /// 关闭搜索栏并清空搜索状态
    private func closeSearchBar() {
        withAnimation(.easeInOut(duration: 0.2)) {
            isVisible = false
        }
        viewModel.searchQuery = ""
        viewModel.search(query: "", caseSensitive: viewModel.isCaseSensitive)
        isSearchFieldFocused = false
    }
}

// MARK: - Preview

#Preview {
    struct PreviewWrapper: View {
        @State private var isVisible = true
        @StateObject private var viewModel = EditorViewModel()

        var body: some View {
            VStack(spacing: 0) {
                SearchBarView(isVisible: $isVisible, viewModel: viewModel)
                Spacer()
                Button("Toggle Search Bar") {
                    withAnimation {
                        isVisible.toggle()
                    }
                }
                .padding()
            }
            .frame(width: 600, height: 300)
            .onAppear {
                viewModel.content = "Hello World\nhello swift\nHELLO MACOS"
            }
        }
    }

    return PreviewWrapper()
}
