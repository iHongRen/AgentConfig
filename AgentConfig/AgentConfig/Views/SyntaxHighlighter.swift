//
//  SyntaxHighlighter.swift
//  AgentConfig
//
//  Created by cxy on 2026/5/11.
//

import AppKit

// MARK: - HighlightRule

/// 单条高亮规则：正则表达式 + 对应颜色
private struct HighlightRule {
    let pattern: NSRegularExpression
    let color: NSColor
}

// MARK: - SyntaxHighlighter

/// 语法高亮器，实现 `NSTextStorageDelegate`
///
/// 通过 `NSTextStorage` + `NSLayoutManager` 对编辑器内容进行语法高亮。
/// 支持 JSON/JSONC、YAML/TOML、Shell 三种文件类型，并根据浅色/深色模式使用不同配色方案。
///
/// 使用方式：
/// ```swift
/// let highlighter = SyntaxHighlighter(fileType: .json)
/// textStorage.delegate = highlighter
/// ```
final class SyntaxHighlighter: NSObject, NSTextStorageDelegate {

    // MARK: - Properties

    /// 当前文件类型，决定使用哪套高亮规则
    var fileType: FileType {
        didSet {
            if fileType != oldValue {
                rebuildRules()
            }
        }
    }

    /// 当前是否为深色模式
    var isDarkMode: Bool {
        didSet {
            if isDarkMode != oldValue {
                rebuildRules()
            }
        }
    }

    /// 编译好的高亮规则列表
    private var rules: [HighlightRule] = []

    /// 防止递归触发高亮的标志
    private var isHighlighting = false

    /// 默认文字颜色（用于重置）
    private var defaultTextColor: NSColor {
        // 直接根据 isDarkMode 返回固定颜色，避免 NSColor.textColor 在
        // NSViewRepresentable 上下文中因 appearance 不匹配而解析成错误颜色
        isDarkMode ? NSColor(white: 0.92, alpha: 1) : NSColor(white: 0.10, alpha: 1)
    }

    // MARK: - Init

    /// 初始化语法高亮器
    /// - Parameters:
    ///   - fileType: 文件类型，决定高亮规则
    ///   - isDarkMode: 是否深色模式，决定配色方案
    init(fileType: FileType, isDarkMode: Bool = false) {
        self.fileType = fileType
        self.isDarkMode = isDarkMode
        super.init()
        rebuildRules()
    }

    // MARK: - NSTextStorageDelegate

    func textStorage(
        _ textStorage: NSTextStorage,
        willProcessEditing editedMask: NSTextStorageEditActions,
        range editedRange: NSRange,
        changeInLength delta: Int
    ) {
        // 高亮由 NSTextViewDelegate 在文本变更完成后触发，避免在编辑事务中
        // 修改属性导致光标位置被 AppKit 重置。
        return
    }

    // MARK: - Public Methods

    /// 手动触发高亮。调用方必须在 beginEditing/endEditing 事务内调用此方法。
    func applyHighlighting(to textStorage: NSTextStorage) {
        guard !isHighlighting else { return }

        let fullRange = NSRange(location: 0, length: textStorage.length)
        guard fullRange.length > 0 else { return }

        isHighlighting = true

        textStorage.addAttribute(.foregroundColor, value: defaultTextColor, range: fullRange)
        textStorage.addAttribute(
            .font,
            value: NSFont.monospacedSystemFont(ofSize: 13, weight: .regular),
            range: fullRange
        )

        // JSON 类文件需要避免字符串中的数字再次被数字规则覆盖。
        if !rules.isEmpty {
            if isJSONLikeFileType {
                applyJSONLikeHighlighting(to: textStorage, range: fullRange)
            } else {
                applyStandardHighlighting(to: textStorage, range: fullRange)
            }
        }

        isHighlighting = false
    }

    // MARK: - Private: Rule Building

    /// 根据当前 fileType 和 isDarkMode 重新构建高亮规则
    private func rebuildRules() {
        switch fileType {
        case .json, .jsonc, .json5, .jsonl:
            rules = buildJSONRules()
        case .yaml:
            rules = buildYAMLRules()
        case .toml:
            rules = buildTOMLRules()
        case .shell:
            rules = buildShellRules()
        case .plainText:
            rules = []
        }
    }

    // MARK: - JSON / JSONC Rules

    /// 构建 JSON/JSONC 高亮规则
    ///
    /// 高亮顺序（后者覆盖前者）：
    /// 1. 字符串值（绿色）
    /// 2. 数字（蓝色）
    /// 3. 布尔值 / null（紫色）
    /// 4. 键名（橙色，覆盖字符串颜色）
    /// 5. JSONC 注释（灰色，最高优先级）
    private func buildJSONRules() -> [HighlightRule] {
        var rules: [HighlightRule] = []

        // 1. 字符串值（绿色）— 匹配所有双引号字符串
        if let pattern = try? NSRegularExpression(pattern: #""(?:[^"\\]|\\.)*""#) {
            rules.append(HighlightRule(pattern: pattern, color: stringColor))
        }

        // 2. 数字（蓝色）— 整数、浮点数、科学计数法
        if let pattern = try? NSRegularExpression(
            pattern: #"(?<!["\w])-?(?:0|[1-9]\d*)(?:\.\d+)?(?:[eE][+-]?\d+)?(?!["\w])"#
        ) {
            rules.append(HighlightRule(pattern: pattern, color: numberColor))
        }

        // 3. 布尔值 / null（紫色）
        if let pattern = try? NSRegularExpression(pattern: #"\b(?:true|false|null)\b"#) {
            rules.append(HighlightRule(pattern: pattern, color: keywordColor))
        }

        // 4. 键名（橙色）— "key": 模式，捕获组 1 为键名字符串（含引号）
        if let pattern = try? NSRegularExpression(
            pattern: #"("(?:[^"\\]|\\.)*")\s*:"#
        ) {
            rules.append(HighlightRule(pattern: pattern, color: keyNameColor))
        }

        // 5. JSONC/JSON5 注释（灰色）— // ... 或 /* ... */
        if fileType == .jsonc || fileType == .json5 {
            if let pattern = try? NSRegularExpression(pattern: #"//[^\n]*"#) {
                rules.append(HighlightRule(pattern: pattern, color: commentColor))
            }
            // JSONC 块注释（灰色）— /* ... */
            if let pattern = try? NSRegularExpression(
                pattern: #"/\*[\s\S]*?\*/"#,
                options: [.dotMatchesLineSeparators]
            ) {
                rules.append(HighlightRule(pattern: pattern, color: commentColor))
            }
        }

        return rules
    }

    private var isJSONLikeFileType: Bool {
        switch fileType {
        case .json, .jsonc, .json5, .jsonl:
            return true
        default:
            return false
        }
    }

    private func applyStandardHighlighting(to textStorage: NSTextStorage, range fullRange: NSRange) {
        let str = textStorage.string as NSString

        for rule in rules {
            let matches = rule.pattern.matches(
                in: textStorage.string, options: [], range: fullRange
            )
            for match in matches {
                let highlightRange = match.numberOfRanges > 1
                    ? match.range(at: 1)
                    : match.range
                guard highlightRange.location != NSNotFound,
                      NSMaxRange(highlightRange) <= str.length else { continue }
                textStorage.addAttribute(
                    .foregroundColor, value: rule.color, range: highlightRange
                )
            }
        }
    }

    private func applyJSONLikeHighlighting(to textStorage: NSTextStorage, range fullRange: NSRange) {
        let source = textStorage.string as NSString
        guard let stringRule = rules.first else { return }

        let stringMatches = stringRule.pattern.matches(
            in: textStorage.string, options: [], range: fullRange
        )
        let stringRanges = stringMatches.map(\.range)
        let nonStringRanges = invertedRanges(from: stringRanges, within: fullRange)

        for stringRange in stringRanges where isValid(stringRange, in: source) {
            textStorage.addAttribute(.foregroundColor, value: stringColor, range: stringRange)
        }

        for rule in rules.dropFirst() {
            let isKeyName = rule.color == keyNameColor
            let isComment = rule.color == commentColor

            let candidateRanges: [NSRange]
            if isKeyName || isComment {
                candidateRanges = [fullRange]
            } else {
                candidateRanges = nonStringRanges
            }

            for candidateRange in candidateRanges where candidateRange.length > 0 {
                let matches = rule.pattern.matches(
                    in: textStorage.string,
                    options: [],
                    range: candidateRange
                )
                for match in matches {
                    let highlightRange = match.numberOfRanges > 1 ? match.range(at: 1) : match.range
                    guard isValid(highlightRange, in: source) else { continue }
                    textStorage.addAttribute(
                        .foregroundColor,
                        value: rule.color,
                        range: highlightRange
                    )
                }
            }
        }
    }

    private func isValid(_ range: NSRange, in source: NSString) -> Bool {
        range.location != NSNotFound && NSMaxRange(range) <= source.length
    }

    private func invertedRanges(from ranges: [NSRange], within fullRange: NSRange) -> [NSRange] {
        guard !ranges.isEmpty else { return [fullRange] }

        var results: [NSRange] = []
        var currentLocation = fullRange.location
        let fullRangeEnd = NSMaxRange(fullRange)

        for range in ranges {
            guard range.location != NSNotFound else { continue }

            let clampedStart = max(range.location, fullRange.location)
            let clampedEnd = min(NSMaxRange(range), fullRangeEnd)
            guard clampedStart < clampedEnd else { continue }

            if currentLocation < clampedStart {
                results.append(NSRange(location: currentLocation, length: clampedStart - currentLocation))
            }

            currentLocation = max(currentLocation, clampedEnd)
        }

        if currentLocation < fullRangeEnd {
            results.append(NSRange(location: currentLocation, length: fullRangeEnd - currentLocation))
        }

        return results
    }

    // MARK: - YAML Rules

    /// 构建 YAML 高亮规则
    ///
    /// 高亮顺序：
    /// 1. 字符串（绿色）
    /// 2. 键名（橙色）
    /// 3. 注释（灰色，最高优先级）
    private func buildYAMLRules() -> [HighlightRule] {
        var rules: [HighlightRule] = []

        // 1. 带引号的字符串（绿色）
        if let pattern = try? NSRegularExpression(pattern: #"(?:"(?:[^"\\]|\\.)*"|'(?:[^'\\]|\\.)*')"#) {
            rules.append(HighlightRule(pattern: pattern, color: stringColor))
        }

        // 2. 布尔值 / null（紫色）
        if let pattern = try? NSRegularExpression(
            pattern: #"\b(?:true|false|yes|no|null|~)\b"#,
            options: [.caseInsensitive]
        ) {
            rules.append(HighlightRule(pattern: pattern, color: keywordColor))
        }

        // 3. 数字（蓝色）
        if let pattern = try? NSRegularExpression(
            pattern: #"(?:^|\s)-?(?:0|[1-9]\d*)(?:\.\d+)?(?:[eE][+-]?\d+)?(?=\s|$)"#,
            options: [.anchorsMatchLines]
        ) {
            rules.append(HighlightRule(pattern: pattern, color: numberColor))
        }

        // 4. 键名（橙色）— 行首的 key: 模式，捕获组 1 为键名
        if let pattern = try? NSRegularExpression(
            pattern: #"^(\s*[\w\-\.]+)\s*:"#,
            options: [.anchorsMatchLines]
        ) {
            rules.append(HighlightRule(pattern: pattern, color: keyNameColor))
        }

        // 5. 注释（灰色）— # ...
        if let pattern = try? NSRegularExpression(pattern: #"#[^\n]*"#) {
            rules.append(HighlightRule(pattern: pattern, color: commentColor))
        }

        return rules
    }

    // MARK: - TOML Rules

    /// 构建 TOML 高亮规则
    ///
    /// 高亮顺序：
    /// 1. 字符串（绿色）
    /// 2. 数字（蓝色）
    /// 3. 布尔值（紫色）
    /// 4. 节标题（橙色）
    /// 5. 键名（橙色）
    /// 6. 注释（灰色）
    private func buildTOMLRules() -> [HighlightRule] {
        var rules: [HighlightRule] = []

        // 1. 多行字符串（绿色）— """ ... """
        if let pattern = try? NSRegularExpression(
            pattern: #""{3}[\s\S]*?"{3}"#,
            options: [.dotMatchesLineSeparators]
        ) {
            rules.append(HighlightRule(pattern: pattern, color: stringColor))
        }

        // 2. 单行字符串（绿色）— "..." 或 '...'
        if let pattern = try? NSRegularExpression(pattern: #"(?:"(?:[^"\\]|\\.)*"|'[^']*')"#) {
            rules.append(HighlightRule(pattern: pattern, color: stringColor))
        }

        // 3. 数字（蓝色）— 整数、浮点数、十六进制、日期时间
        if let pattern = try? NSRegularExpression(
            pattern: #"(?<!["\w])-?(?:0x[\da-fA-F_]+|0o[0-7_]+|0b[01_]+|(?:0|[1-9][\d_]*)(?:\.[\d_]+)?(?:[eE][+-]?[\d_]+)?)(?!["\w])"#
        ) {
            rules.append(HighlightRule(pattern: pattern, color: numberColor))
        }

        // 4. 布尔值（紫色）
        if let pattern = try? NSRegularExpression(pattern: #"\b(?:true|false)\b"#) {
            rules.append(HighlightRule(pattern: pattern, color: keywordColor))
        }

        // 5. 节标题（橙色）— [section] 或 [[array]]
        if let pattern = try? NSRegularExpression(pattern: #"^\[{1,2}[^\]]+\]{1,2}"#, options: [.anchorsMatchLines]) {
            rules.append(HighlightRule(pattern: pattern, color: keyNameColor))
        }

        // 6. 键名（橙色）— key = 模式，捕获组 1 为键名
        if let pattern = try? NSRegularExpression(
            pattern: #"^(\s*[\w\-\.]+)\s*="#,
            options: [.anchorsMatchLines]
        ) {
            rules.append(HighlightRule(pattern: pattern, color: keyNameColor))
        }

        // 7. 注释（灰色）— # ...
        if let pattern = try? NSRegularExpression(pattern: #"#[^\n]*"#) {
            rules.append(HighlightRule(pattern: pattern, color: commentColor))
        }

        return rules
    }

    // MARK: - Shell Rules

    /// 构建 Shell 脚本高亮规则
    ///
    /// 高亮顺序：
    /// 1. 字符串（绿色）
    /// 2. 变量（蓝色）
    /// 3. 关键字（紫色）
    /// 4. 注释（灰色，最高优先级）
    private func buildShellRules() -> [HighlightRule] {
        var rules: [HighlightRule] = []

        // 1. 双引号字符串（绿色）
        if let pattern = try? NSRegularExpression(pattern: #""(?:[^"\\]|\\.)*""#) {
            rules.append(HighlightRule(pattern: pattern, color: stringColor))
        }

        // 2. 单引号字符串（绿色）
        if let pattern = try? NSRegularExpression(pattern: #"'[^']*'"#) {
            rules.append(HighlightRule(pattern: pattern, color: stringColor))
        }

        // 3. 变量（蓝色）— $VAR、${VAR}、$1 等
        if let pattern = try? NSRegularExpression(pattern: #"\$\{?[\w@#\*\?!\-0-9]+\}?"#) {
            rules.append(HighlightRule(pattern: pattern, color: variableColor))
        }

        // 4. Shell 关键字（紫色）
        let keywords = [
            "if", "then", "else", "elif", "fi",
            "for", "while", "do", "done",
            "case", "esac", "in",
            "function", "return", "local",
            "export", "source", "alias", "unset",
            "echo", "printf", "read",
            "exit", "break", "continue",
            "true", "false"
        ]
        let keywordPattern = "\\b(?:" + keywords.joined(separator: "|") + ")\\b"
        if let pattern = try? NSRegularExpression(pattern: keywordPattern) {
            rules.append(HighlightRule(pattern: pattern, color: keywordColor))
        }

        // 5. 注释（灰色）— # ...（排除 shebang 行首的 #! 也高亮为注释）
        if let pattern = try? NSRegularExpression(pattern: #"#[^\n]*"#) {
            rules.append(HighlightRule(pattern: pattern, color: commentColor))
        }

        return rules
    }

    // MARK: - Color Palette

    // 字符串颜色（绿色）
    private var stringColor: NSColor {
        isDarkMode
            ? NSColor(red: 0.40, green: 0.85, blue: 0.40, alpha: 1.0)   // 深色：亮绿
            : NSColor(red: 0.10, green: 0.55, blue: 0.10, alpha: 1.0)   // 浅色：深绿
    }

    // 数字颜色（蓝色）
    private var numberColor: NSColor {
        isDarkMode
            ? NSColor(red: 0.40, green: 0.70, blue: 1.00, alpha: 1.0)   // 深色：亮蓝
            : NSColor(red: 0.00, green: 0.30, blue: 0.80, alpha: 1.0)   // 浅色：深蓝
    }

    // 关键字 / 布尔值 / null 颜色（紫色）
    private var keywordColor: NSColor {
        isDarkMode
            ? NSColor(red: 0.80, green: 0.55, blue: 1.00, alpha: 1.0)   // 深色：亮紫
            : NSColor(red: 0.55, green: 0.10, blue: 0.75, alpha: 1.0)   // 浅色：深紫
    }

    // 键名颜色（橙色）
    private var keyNameColor: NSColor {
        isDarkMode
            ? NSColor(red: 1.00, green: 0.75, blue: 0.30, alpha: 1.0)   // 深色：亮橙
            : NSColor(red: 0.75, green: 0.35, blue: 0.00, alpha: 1.0)   // 浅色：深橙
    }

    // 注释颜色（灰色）
    private var commentColor: NSColor {
        isDarkMode
            ? NSColor(white: 0.55, alpha: 1.0)   // 深色：中灰
            : NSColor(white: 0.50, alpha: 1.0)   // 浅色：中灰
    }

    // Shell 变量颜色（蓝色，与数字蓝略有区分）
    private var variableColor: NSColor {
        isDarkMode
            ? NSColor(red: 0.30, green: 0.80, blue: 1.00, alpha: 1.0)   // 深色：青蓝
            : NSColor(red: 0.00, green: 0.45, blue: 0.75, alpha: 1.0)   // 浅色：深青蓝
    }
}
