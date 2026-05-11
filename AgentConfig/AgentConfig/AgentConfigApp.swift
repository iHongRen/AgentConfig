//
//  AgentConfigApp.swift
//  AgentConfig
//
//  Created by cxy on 2026/5/11.
//

import SwiftUI
import AppKit

// MARK: - AppDelegate

/// NSApplicationDelegate，处理应用前台/后台切换事件
final class AppDelegate: NSObject, NSApplicationDelegate {

    /// 当应用从后台切换到前台时，通知 EditorViewModel 检查文件变更
    func applicationDidBecomeActive(_ notification: Notification) {
        NotificationCenter.default.post(name: .appDidBecomeActive, object: nil)
    }
}

extension Notification.Name {
    static let appDidBecomeActive = Notification.Name("AgentConfig.appDidBecomeActive")
}

// MARK: - AgentConfigApp

@main
struct AgentConfigApp: App {

    // MARK: - App Delegate

    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    // MARK: - State Objects (shared across all windows)

    @StateObject private var appViewModel = AppViewModel()
    @StateObject private var editorViewModel = EditorViewModel()
    @StateObject private var gitViewModel = GitViewModel()

    // MARK: - Appearance

    /// 当前有效的 ColorScheme（由 AppSettings 驱动）
    @State private var preferredColorScheme: ColorScheme? = nil

    /// 用于触发 UI 重建的语言切换计数器
    @State private var languageChangeID: Int = 0

    // MARK: - Body

    var body: some Scene {
        // MARK: Main Window
        WindowGroup {
            MainContentView(
                appViewModel: appViewModel,
                editorViewModel: editorViewModel,
                gitViewModel: gitViewModel
            )
            .id(languageChangeID)  // 语言切换时强制重建整个视图树
            .preferredColorScheme(preferredColorScheme)
            .onAppear {
                applyAppearance(appViewModel.settings.appearanceMode)
                setupGitViewModelRestoreCallback()
                setupForegroundObserver()
            }
            .onReceive(NotificationCenter.default.publisher(for: .languageDidChange)) { _ in
                languageChangeID += 1
            }
            .onChange(of: appViewModel.settings.appearanceMode) { _, newMode in
                applyAppearance(newMode)
            }
            .onChange(of: appViewModel.settings.autoSource) { _, newValue in
                editorViewModel.autoSource = newValue
            }
        }
        .commands {
            // MARK: About Menu
            CommandGroup(replacing: .appInfo) {
                Button(NSLocalizedString("menu.about", value: "About AgentConfig", comment: "About menu item")) {
                    showAboutWindow()
                }
            }
        }

        // MARK: Settings Window
        Settings {
            SettingsView()
                .environmentObject(appViewModel)
                .preferredColorScheme(preferredColorScheme)
        }
    }

    // MARK: - Private Helpers

    /// 根据外观模式设置 preferredColorScheme
    private func applyAppearance(_ mode: AppearanceMode) {
        switch mode {
        case .light:
            preferredColorScheme = .light
        case .dark:
            preferredColorScheme = .dark
        case .system:
            preferredColorScheme = nil
        }
    }

    /// 设置 GitViewModel 的 onRestore 回调，将恢复内容写入 EditorViewModel
    private func setupGitViewModelRestoreCallback() {
        gitViewModel.onRestore = { [weak editorViewModel = editorViewModel] restoredContent in
            guard let vm = editorViewModel else { return }
            Task { @MainActor in
                vm.content = restoredContent
                vm.isModified = true
            }
        }
    }

    /// 监听应用前台切换事件，触发 EditorViewModel.onForeground()
    private func setupForegroundObserver() {
        NotificationCenter.default.addObserver(
            forName: .appDidBecomeActive,
            object: nil,
            queue: .main
        ) { _ in
            Task { await editorViewModel.onForeground() }
        }
    }

    /// 显示关于窗口
    private func showAboutWindow() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 620),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = NSLocalizedString("menu.about", value: "About AgentConfig", comment: "About window title")
        window.center()
        window.contentView = NSHostingView(rootView: AboutView())
        window.makeKeyAndOrderFront(nil)
    }
}

// MARK: - MainContentView

/// 应用主内容视图，实现三栏 NavigationSplitView 布局
struct MainContentView: View {

    @ObservedObject var appViewModel: AppViewModel
    @ObservedObject var editorViewModel: EditorViewModel
    @ObservedObject var gitViewModel: GitViewModel

    var body: some View {
        NavigationSplitView {
            // 左栏：分类列表
            SidebarView()
                .environmentObject(appViewModel)
        } content: {
            // 中栏：文件列表
            fileListContent
        } detail: {
            // 右栏：编辑器
            EditorView(
                editorViewModel: editorViewModel,
                gitViewModel: gitViewModel
            )
        }
        .navigationSplitViewStyle(.balanced)
        .frame(minWidth: 900, minHeight: 600)
        // 当选中文件变化时，加载文件到编辑器
        .onChange(of: appViewModel.selectedFile) { _, newFile in
            guard let file = newFile else { return }
            Task {
                try? await editorViewModel.load(file: file)
                await gitViewModel.loadHistory(for: file)
            }
        }
        // 同步 autoSource 设置
        .onAppear {
            editorViewModel.autoSource = appViewModel.settings.autoSource
        }
    }

    // MARK: - File List Content

    @ViewBuilder
    private var fileListContent: some View {
        if let selectedCategory = appViewModel.selectedCategory {
            switch selectedCategory {
            case .env:
                if let envCategory = appViewModel.envCategory {
                    FileListView(selection: .env(envCategory))
                        .environmentObject(appViewModel)
                } else {
                    emptyFileListPlaceholder
                }
            case .agent(let id):
                if let category = appViewModel.agentCategories.first(where: { $0.id == id }) {
                    FileListView(selection: .agent(category))
                        .environmentObject(appViewModel)
                } else {
                    emptyFileListPlaceholder
                }
            }
        } else {
            emptyFileListPlaceholder
        }
    }

    private var emptyFileListPlaceholder: some View {
        VStack(spacing: 12) {
            Image(systemName: "sidebar.left")
                .font(.system(size: 36))
                .foregroundStyle(.tertiary)
            Text(NSLocalizedString("filelist.selectCategory", value: "Select a category from the sidebar", comment: "File list empty placeholder"))
                .foregroundStyle(.secondary)
                .font(.callout)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
