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
    /// 开始监控指定文件列表，当任意文件发生写入变更时回调
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
/// 使用 `DispatchSource.makeFileSystemObjectSource` 监控每个文件的 `write` 事件。
/// 内置 500ms 防抖（debounce），避免短时间内多次写入触发频繁回调。
final class FileWatcher: FileWatcherProtocol {

    // MARK: - Private Types

    /// 单个文件的监控上下文，持有 DispatchSource 和文件描述符
    private struct WatchEntry {
        let url: URL
        let fileDescriptor: Int32
        let source: DispatchSourceFileSystemObject
    }

    // MARK: - Private Properties

    /// 当前所有活跃的监控条目，key 为文件 URL
    private var entries: [URL: WatchEntry] = [:]

    /// 防抖计时器，key 为文件 URL
    private var debounceTimers: [URL: DispatchWorkItem] = [:]

    /// 用于执行 DispatchSource 事件处理的串行队列
    private let watchQueue = DispatchQueue(
        label: "com.agentconfig.filewatcher",
        qos: .utility
    )

    /// 防抖延迟（500ms）
    private let debounceDelay: TimeInterval = 0.5

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

        // 取消并释放所有 DispatchSource，关闭文件描述符
        for (_, entry) in entries {
            entry.source.cancel()
            // DispatchSource cancel 后，文件描述符由 cancelHandler 关闭
        }
        entries.removeAll()
    }

    // MARK: - Private Helpers

    /// 为单个文件创建 DispatchSource 监控
    private func startWatching(url: URL, onChange: @escaping (URL) -> Void) {
        // 以只读方式打开文件，获取文件描述符
        let fd = open(url.path, O_EVTONLY)
        guard fd >= 0 else {
            // 文件无法打开（不存在或无权限），跳过
            return
        }

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: .write,
            queue: watchQueue
        )

        // 事件处理：触发防抖回调
        source.setEventHandler { [weak self] in
            self?.scheduleDebounce(for: url, onChange: onChange)
        }

        // 取消处理：关闭文件描述符，防止资源泄漏
        source.setCancelHandler {
            close(fd)
        }

        source.resume()

        entries[url] = WatchEntry(url: url, fileDescriptor: fd, source: source)
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
