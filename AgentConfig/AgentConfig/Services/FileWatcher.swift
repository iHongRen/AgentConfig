//
//  FileWatcher.swift
//  AgentConfig
//
//  Created by cxy on 2026/5/11.
//

import Foundation

// MARK: - FileWatcherProtocol

/// 文件监控服务协议
protocol FileWatcherProtocol {
    /// 开始监控指定文件列表，当任意文件发生写入、替换等变更时回调
    /// - Parameters:
    ///   - urls: 要监控的文件 URL 列表
    ///   - onChange: 文件发生变更时的回调，参数为发生变更的文件 URL
    func watch(urls: [URL], onChange: @escaping (URL) -> Void)

    /// 停止所有文件监控并释放相关资源
    func stopWatching()
}

// MARK: - FileWatcher

/// `FileWatcherProtocol` 的默认实现
///
/// 使用 `DispatchSource.makeFileSystemObjectSource` 监控每个文件的写入、替换与属性变更事件。
/// 内置 500ms 防抖（debounce），避免短时间内多次写入触发频繁回调。
/// 当外部编辑器采用“写临时文件再原子替换”的保存方式时，会自动重新挂载监听。
final class FileWatcher: FileWatcherProtocol {

    // MARK: - Private Types

    /// 单个文件的监控上下文，持有 DispatchSource 和文件描述符
    private struct WatchEntry {
        let url: URL
        let source: DispatchSourceFileSystemObject
    }

    // MARK: - Private Properties

    /// 当前所有活跃的监控条目，key 为文件 URL
    private var entries: [URL: WatchEntry] = [:]

    /// 防抖计时器，key 为文件 URL
    private var debounceTimers: [URL: DispatchWorkItem] = [:]

    /// 重新挂载监听的重试任务，key 为文件 URL
    private var reopenTasks: [URL: DispatchWorkItem] = [:]

    /// 用于执行 DispatchSource 事件处理的串行队列
    private let watchQueue = DispatchQueue(
        label: "com.agentconfig.filewatcher",
        qos: .utility
    )

    /// 防抖延迟（500ms）
    private let debounceDelay: TimeInterval = 0.5

    /// 监听重试间隔（100ms）
    private let reopenRetryDelay: TimeInterval = 0.1

    /// 监听重试次数
    private let maxReopenAttempts = 5

    /// 监听的文件系统事件。
    /// 除了常规写入外，还覆盖外部编辑器常见的“原子替换保存”场景。
    private let watchedEvents: DispatchSource.FileSystemEvent = [
        .write, .delete, .rename, .revoke, .attrib, .extend
    ]

    /// 这些事件意味着原来的 inode 可能已失效，需要重新打开并挂载监听。
    private let reopenTriggerEvents: DispatchSource.FileSystemEvent = [
        .delete, .rename, .revoke
    ]

    // MARK: - FileWatcherProtocol

    func watch(urls: [URL], onChange: @escaping (URL) -> Void) {
        // 先停止现有监控，确保状态干净
        stopWatching()

        for url in urls {
            startWatching(url: url, onChange: onChange)
        }
    }

    func stopWatching() {
        // 取消所有防抖计时器
        for (_, timer) in debounceTimers {
            timer.cancel()
        }
        debounceTimers.removeAll()

        // 取消所有重试任务
        for (_, task) in reopenTasks {
            task.cancel()
        }
        reopenTasks.removeAll()

        // 取消并释放所有 DispatchSource，关闭文件描述符
        for (_, entry) in entries {
            entry.source.cancel()
            // DispatchSource cancel 后，文件描述符由 cancelHandler 关闭
        }
        entries.removeAll()
    }

    // MARK: - Private Helpers

    /// 为单个文件创建 DispatchSource 监控
    @discardableResult
    private func startWatching(url: URL, onChange: @escaping (URL) -> Void) -> Bool {
        // 以只读方式打开文件，获取文件描述符
        let fd = open(url.path, O_EVTONLY)
        guard fd >= 0 else {
            // 文件无法打开（不存在或无权限），跳过
            return false
        }

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: watchedEvents,
            queue: watchQueue
        )

        // 事件处理：触发防抖回调
        source.setEventHandler { [weak self] in
            guard let self else { return }
            let event = self.entries[url]?.source.data ?? []
            self.handleEvent(event, for: url, onChange: onChange)
        }

        // 取消处理：关闭文件描述符，防止资源泄漏
        source.setCancelHandler {
            close(fd)
        }

        source.resume()

        entries[url] = WatchEntry(url: url, source: source)
        return true
    }

    /// 处理文件系统事件。
    ///
    /// 对于原子替换保存，旧文件句柄会收到 delete / rename / revoke 等事件，
    /// 需要在回调后重新打开目标路径，继续监听新的 inode。
    private func handleEvent(
        _ event: DispatchSource.FileSystemEvent,
        for url: URL,
        onChange: @escaping (URL) -> Void
    ) {
        if !event.intersection(reopenTriggerEvents).isEmpty {
            scheduleReopen(for: url, onChange: onChange)
        }
        scheduleDebounce(for: url, onChange: onChange)
    }

    /// 重新打开并挂载文件监听。
    ///
    /// 某些外部编辑器会先删除旧文件，再将临时文件 rename 到原路径。
    /// 这里对这种短暂窗口进行有限重试，确保监听能够恢复到新文件上。
    private func scheduleReopen(
        for url: URL,
        onChange: @escaping (URL) -> Void,
        attemptsRemaining: Int? = nil
    ) {
        let remainingAttempts = attemptsRemaining ?? maxReopenAttempts

        reopenTasks[url]?.cancel()
        if let entry = entries.removeValue(forKey: url) {
            entry.source.cancel()
        }

        let reopenTask = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.reopenTasks.removeValue(forKey: url)

            if self.startWatching(url: url, onChange: onChange) {
                return
            }

            guard remainingAttempts > 0 else { return }

            self.scheduleReopen(
                for: url,
                onChange: onChange,
                attemptsRemaining: remainingAttempts - 1
            )
        }

        reopenTasks[url] = reopenTask
        let delay = remainingAttempts == maxReopenAttempts ? 0 : reopenRetryDelay
        watchQueue.asyncAfter(deadline: .now() + delay, execute: reopenTask)
    }

    /// 为指定 URL 安排防抖回调
    ///
    /// 若在 500ms 内再次触发，则取消上一次计划，重新计时。
    private func scheduleDebounce(for url: URL, onChange: @escaping (URL) -> Void) {
        // 取消上一次尚未执行的计时器
        debounceTimers[url]?.cancel()

        let workItem = DispatchWorkItem { [weak self] in
            self?.debounceTimers.removeValue(forKey: url)
            // 回调切换到主队列，方便 UI 层直接更新
            DispatchQueue.main.async {
                onChange(url)
            }
        }

        debounceTimers[url] = workItem
        watchQueue.asyncAfter(deadline: .now() + debounceDelay, execute: workItem)
    }

    // MARK: - Deinit

    deinit {
        stopWatching()
    }
}
