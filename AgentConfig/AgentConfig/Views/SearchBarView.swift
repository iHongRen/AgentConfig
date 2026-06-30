//
//  SearchBarView.swift
//  AgentConfig
//
//  Created by cxy on 2026/5/11.
//

import SwiftUI

// MARK: - SearchBarView

/// VSCode 风格搜索栏：关键词高亮、上下导航、大小写开关
struct SearchBarView: View {

    enum Style {
        case editorPanel
        case toolbar
    }

    @Binding var isVisible: Bool
    @ObservedObject var viewModel: EditorViewModel
    let onClose: () -> Void
    var style: Style = .editorPanel

    @FocusState private var isSearchFieldFocused: Bool

    // MARK: - Computed

    private var hasNoMatch: Bool {
        !viewModel.searchQuery.isEmpty && viewModel.searchResults.isEmpty
    }

    private var matchCountText: String {
        guard !viewModel.searchQuery.isEmpty else { return "" }
        guard !viewModel.searchResults.isEmpty else { return L10n.tr("search.noResults", value: "No Results") }
        return "\(viewModel.currentSearchIndex + 1)/\(viewModel.searchResults.count)"
    }

    private var searchFieldWidth: CGFloat {
        style == .toolbar ? 220 : 260
    }

    private var matchCountMinWidth: CGFloat {
        style == .toolbar ? 38 : 44
    }

    private var outerHorizontalPadding: CGFloat {
        style == .toolbar ? 8 : 12
    }

    private var outerHeight: CGFloat {
        style == .toolbar ? 39 : 40
    }

    private var spacerMinLength: CGFloat {
        style == .toolbar ? 4 : 8
    }

    // MARK: - Body

    var body: some View {
        HStack(spacing: 6) {

            // ── 搜索输入框 ──────────────────────────────────────────
            HStack(spacing: 0) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .frame(width: 30)

                TextField(L10n.tr("search.placeholder", value: "Search"), text: $viewModel.searchQuery)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                    .focused($isSearchFieldFocused)
                    .onSubmit { viewModel.nextMatch() }
                    .onExitCommand {
                        closeSearchBar()
                    }
                    .onChange(of: viewModel.searchQuery) { _, q in
                        viewModel.search(query: q, caseSensitive: viewModel.isCaseSensitive)
                    }

                // 匹配计数
                if !viewModel.searchQuery.isEmpty {
                    Text(matchCountText)
                        .font(.system(size: 12, weight: .medium).monospacedDigit())
                        .foregroundStyle(hasNoMatch ? Color(nsColor: .systemRed) : .secondary)
                        .frame(minWidth: matchCountMinWidth, alignment: .trailing)
                        .padding(.trailing, 4)
                }

                // 清除按钮
                if !viewModel.searchQuery.isEmpty {
                    Button {
                        viewModel.searchQuery = ""
                        viewModel.search(query: "", caseSensitive: viewModel.isCaseSensitive)
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 13))
                            .foregroundStyle(.tertiary)
                    }
                    .buttonStyle(.plain)
                    .frame(width: 26)
                }
            }
            .frame(height: 26)
            .padding(.trailing, 2)
            .background(
                RoundedRectangle(cornerRadius: 5)
                    .fill(Color(nsColor: .textBackgroundColor))
                    .overlay(
                        RoundedRectangle(cornerRadius: 5)
                            .strokeBorder(
                                hasNoMatch
                                    ? Color(nsColor: .systemRed).opacity(0.8)
                                    : Color(nsColor: .separatorColor),
                                lineWidth: hasNoMatch ? 1.5 : 1
                            )
                    )
            )
            .frame(width: searchFieldWidth)

            // ── 选项按钮 ────────────────────────────────────────────
            optionToggle(
                icon: "textformat",
                label: "Aa",
                isOn: $viewModel.isCaseSensitive,
                tooltip: L10n.tr("search.caseSensitive", value: "Match Case (⌥⌘C)")
            )
            .onChange(of: viewModel.isCaseSensitive) { _, v in
                viewModel.search(query: viewModel.searchQuery, caseSensitive: v)
            }

            optionToggle(
                icon: "chevron.left.forwardslash.chevron.right",
                label: ".*",
                isOn: .constant(false),
                tooltip: L10n.tr("search.regexDisabled", value: "Use Regular Expression (Not Yet Supported)"),
                disabled: true
            )

            Spacer(minLength: spacerMinLength)

            // ── 导航按钮 ────────────────────────────────────────────
            HStack(spacing: 2) {
                navButton(icon: "chevron.up", action: { viewModel.previousMatch() }, tooltip: L10n.tr("search.previous", value: "Previous (⇧F3)"))
                    .disabled(viewModel.searchResults.isEmpty)
                    .keyboardShortcut("g", modifiers: [.command, .shift])

                navButton(icon: "chevron.down", action: { viewModel.nextMatch() }, tooltip: L10n.tr("search.next", value: "Next (F3)"))
                    .disabled(viewModel.searchResults.isEmpty)
                    .keyboardShortcut("g", modifiers: .command)
            }

            // ── 关闭按钮 ────────────────────────────────────────────
            Button { closeSearchBar() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 22, height: 22)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(L10n.tr("search.close", value: "Close (Esc)"))
        }
        .padding(.horizontal, outerHorizontalPadding)
        .frame(height: outerHeight)
        .background {
            if style == .editorPanel {
                Color(nsColor: .windowBackgroundColor)
            }
        }
        .overlay(alignment: .bottom) {
            if style == .editorPanel {
                Divider()
            }
        }
        .onAppear {
            focusSearchField()
        }
        .onChange(of: isVisible) { _, visible in
            if visible {
                focusSearchField()
            } else {
                isSearchFieldFocused = false
            }
        }
        .onKeyPress(.escape) {
            closeSearchBar()
            return .handled
        }
        .onExitCommand {
            closeSearchBar()
        }
    }

    // MARK: - Sub-views

    /// 选项切换按钮（Aa / .*）
    @ViewBuilder
    private func optionToggle(
        icon: String,
        label: String,
        isOn: Binding<Bool>,
        tooltip: String,
        disabled: Bool = false
    ) -> some View {
        Button {
            if !disabled { isOn.wrappedValue.toggle() }
        } label: {
            Text(label)
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .foregroundStyle(
                    disabled
                        ? Color.secondary.opacity(0.4)
                        : (isOn.wrappedValue ? Color.accentColor : Color.secondary)
                )
                .frame(width: 26, height: 22)
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(isOn.wrappedValue && !disabled
                              ? Color.accentColor.opacity(0.15)
                              : Color.clear)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .strokeBorder(
                            isOn.wrappedValue && !disabled
                                ? Color.accentColor.opacity(0.4)
                                : Color.clear,
                            lineWidth: 1
                        )
                )
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .help(tooltip)
    }

    /// 上/下导航按钮
    private func navButton(icon: String, action: @escaping () -> Void, tooltip: String) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 26, height: 26)
                .contentShape(Rectangle())
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color(nsColor: .quaternaryLabelColor).opacity(0.01))
                )
        }
        .buttonStyle(.plain)
        .help(tooltip)
    }

    // MARK: - Actions

    private func closeSearchBar() {
        onClose()
        isSearchFieldFocused = false
    }

    private func focusSearchField() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            guard isVisible else { return }
            isSearchFieldFocused = true
        }
    }
}
