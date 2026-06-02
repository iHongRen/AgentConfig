//
//  AgentConfigApp.swift
//  AgentConfig
//
//  Created by cxy on 2026/5/11.
//

import SwiftUI
import AppKit
import Combine

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

// MARK: - CommandCoordinator

/// 桥接 EditorView 的回调到 app 级菜单命令
final class CommandCoordinator: ObservableObject {
    let objectWillChange = ObservableObjectPublisher()
    var onSave: () async -> Void = { }
    var onToggleSearch: () -> Void = { }
    func save() {
        Task { await onSave() }
    }
    func toggleSearch() {
        onToggleSearch()
    }
}

// MARK: - AgentConfigApp

@main
struct AgentConfigApp: App {

    // MARK: - App Delegate

    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    // MARK: - State Objects (shared across all windows)

    @StateObject private var appViewModel = AppViewModel()
    @StateObject private var editorViewModel = EditorViewModel()
    @StateObject private var codexProfileViewModel = CodexProfileViewModel()
    @StateObject private var saveCoordinator = CommandCoordinator()

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
                codexProfileViewModel: codexProfileViewModel,
                saveCoordinator: saveCoordinator
            )
            .id(languageChangeID)  // 语言切换时强制重建整个视图树
            .preferredColorScheme(preferredColorScheme)
            .onAppear {
                applyAppearance(appViewModel.settings.appearanceMode)
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
        .defaultSize(width: 800, height: 640)
        .commands {
            // MARK: About Menu
            CommandGroup(replacing: .appInfo) {
                Button(NSLocalizedString("menu.about", value: "About AgentConfig", comment: "About menu item")) {
                    showAboutWindow()
                }
            }
            // MARK: Save Menu
            CommandGroup(replacing: .saveItem) {
                Button("保存") {
                    saveCoordinator.save()
                }
                .keyboardShortcut("s", modifiers: .command)
            }
            // MARK: Find Menu
            CommandGroup(replacing: .newItem) {
                Button("查找") {
                    saveCoordinator.toggleSearch()
                }
                .keyboardShortcut("f", modifiers: .command)
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

    private let sidebarCollapseThreshold: CGFloat = 760

    @ObservedObject var appViewModel: AppViewModel
    @ObservedObject var editorViewModel: EditorViewModel
    @ObservedObject var codexProfileViewModel: CodexProfileViewModel
    @ObservedObject var saveCoordinator: CommandCoordinator
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @State private var windowWidth: CGFloat = .zero
    @State private var hasResolvedInitialPage = false

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            SidebarView(codexProfileViewModel: codexProfileViewModel)
                .environmentObject(appViewModel)
        } detail: {
            if codexProfileViewModel.selectedProfile != nil {
                CodexProfileEditorView(viewModel: codexProfileViewModel)
            } else {
                EditorView(
                    editorViewModel: editorViewModel,
                    saveCoordinator: saveCoordinator
                )
            }
        }
        .frame(minWidth: 600, minHeight: 640)
        .background(
            GeometryReader { proxy in
                Color.clear
                    .onAppear {
                        updateColumnVisibility(for: proxy.size.width)
                    }
                    .onChange(of: proxy.size.width) { _, newWidth in
                        updateColumnVisibility(for: newWidth)
                    }
            }
        )
        .onChange(of: appViewModel.selectedFile) { _, newFile in
            guard let file = newFile else { return }
            codexProfileViewModel.clearSelection()
            Task {
                try? await editorViewModel.load(file: file)
            }
        }
        .onChange(of: codexProfileViewModel.selectedProfileID) { _, newProfileID in
            guard hasResolvedInitialPage else { return }
            guard let newProfileID else { return }
            appViewModel.persistLastVisitedPage(.codexProfile(id: newProfileID))
        }
        .onChange(of: appViewModel.didFinishInitialRefresh) { _, _ in
            resolveInitialPageIfNeeded()
        }
        .onChange(of: codexProfileViewModel.didFinishInitialLoad) { _, _ in
            resolveInitialPageIfNeeded()
        }
        // 同步 autoSource 设置
        .onAppear {
            editorViewModel.autoSource = appViewModel.settings.autoSource
            resolveInitialPageIfNeeded()
        }
    }

    private func updateColumnVisibility(for width: CGFloat) {
        guard abs(windowWidth - width) > 1 else { return }
        windowWidth = width

        let nextVisibility: NavigationSplitViewVisibility = width < sidebarCollapseThreshold ? .detailOnly : .all
        guard columnVisibility != nextVisibility else { return }

        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            columnVisibility = nextVisibility
        }
    }

    private func resolveInitialPageIfNeeded() {
        guard !hasResolvedInitialPage else { return }
        guard appViewModel.didFinishInitialRefresh, codexProfileViewModel.didFinishInitialLoad else { return }

        hasResolvedInitialPage = true

        if codexProfileViewModel.restoreInitialSelectionIfNeeded(appViewModel: appViewModel) {
            appViewModel.selectFile(nil)
            return
        }

        if appViewModel.restoreInitialSelectionIfNeeded() != nil {
            return
        }

        if let defaultProfileID = codexProfileViewModel.defaultSelectedProfileID() {
            appViewModel.persistLastVisitedPage(.codexProfile(id: defaultProfileID))
        }
    }
}
