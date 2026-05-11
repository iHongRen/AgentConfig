//
//  SidebarView.swift
//  AgentConfig
//
//  Created by cxy on 2026/5/11.
//

import SwiftUI
import AppKit

// MARK: - SidebarView

/// 三栏布局的左侧栏，显示分类列表
///
/// - 顶部显示"环境变量"分类（来自 `AppViewModel.envCategory`）
/// - 下方显示各 Agent 分类（来自 `AppViewModel.agentCategories`）
/// - 每个分类行显示分类名称和文件数量 badge
/// - 工具栏提供"刷新"和"添加自定义路径"按钮
struct SidebarView: View {

    @EnvironmentObject var appViewModel: AppViewModel

    var body: some View {
        List(selection: $appViewModel.selectedCategory) {
            // 环境变量分类（置顶）
            if let envCategory = appViewModel.envCategory {
                CategoryRow(
                    name: "环境变量",
                    systemImage: "terminal",
                    fileCount: envCategory.files.count
                )
                .tag(CategorySelection.env)
            }

            // Agent 分类列表
            if !appViewModel.agentCategories.isEmpty {
                Section("Code Agents") {
                    ForEach(appViewModel.agentCategories) { category in
                        CategoryRow(
                            name: category.displayName,
                            systemImage: "doc.text",
                            fileCount: category.files.count
                        )
                        .tag(CategorySelection.agent(id: category.id))
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .toolbar {
            ToolbarItemGroup {
                // 刷新按钮
                Button {
                    Task { await appViewModel.refresh() }
                } label: {
                    if appViewModel.isScanning {
                        ProgressView()
                            .scaleEffect(0.6)
                            .frame(width: 16, height: 16)
                    } else {
                        Image(systemName: "arrow.clockwise")
                    }
                }
                .disabled(appViewModel.isScanning)
                .help("刷新")

                // 添加自定义路径按钮
                Button {
                    openFilePicker()
                } label: {
                    Image(systemName: "plus")
                }
                .help("添加自定义路径")
            }
        }
        .navigationTitle("AgentConfig")
    }

    // MARK: - Private Methods

    /// 打开文件选择器，让用户选择自定义配置文件路径
    private func openFilePicker() {
        let panel = NSOpenPanel()
        panel.title = "选择配置文件或目录"
        panel.message = "选择要添加的配置文件或目录"
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = false

        panel.begin { response in
            if response == .OK, let url = panel.url {
                appViewModel.addCustomPath(url)
            }
        }
    }
}

// MARK: - CategoryRow

/// 分类列表行，显示分类名称、图标和文件数量 badge
private struct CategoryRow: View {

    let name: String
    let systemImage: String
    let fileCount: Int

    var body: some View {
        HStack {
            Label(name, systemImage: systemImage)
            Spacer()
            // 文件数量 badge
            if fileCount > 0 {
                Text("\(fileCount)")
                    .font(.caption2)
                    .fontWeight(.semibold)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(
                        Capsule()
                            .fill(Color(nsColor: .quaternaryLabelColor))
                    )
            }
        }
    }
}

// MARK: - Preview

#Preview {
    let viewModel = AppViewModel()
    NavigationSplitView {
        SidebarView()
            .environmentObject(viewModel)
    } content: {
        Text("文件列表")
    } detail: {
        Text("编辑器")
    }
}
