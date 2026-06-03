//
//  CommentingTextView.swift
//  AgentConfig
//

import AppKit

class CommentingTextView: NSTextView {
    var commentFileType: FileType = .plainText

    override func keyDown(with event: NSEvent) {
        if handleCommentToggleShortcut(event) {
            return
        }
        super.keyDown(with: event)
    }

    private func handleCommentToggleShortcut(_ event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard flags.contains(.command),
              !flags.contains(.control),
              !flags.contains(.option),
              event.charactersIgnoringModifiers == "/" else {
            return false
        }

        toggleLineComments()
        return true
    }

    private func toggleLineComments() {
        guard let commentPrefix = commentFileType.lineCommentPrefix else { return }

        let source = string as NSString
        let selection = selectedRange()
        let targetRange = source.commentableLineRange(for: selection)
        let relativeCaretOffset = max(0, selection.location - targetRange.location)
        let transformed = source.toggledLineComments(
            in: targetRange,
            prefix: commentPrefix,
            relativeCaretOffset: relativeCaretOffset,
            keepsSelection: selection.length > 0
        )

        guard transformed.replacement != source.substring(with: targetRange) else { return }
        guard shouldChangeText(in: targetRange, replacementString: transformed.replacement) else { return }

        textStorage?.beginEditing()
        textStorage?.replaceCharacters(in: targetRange, with: transformed.replacement)
        textStorage?.endEditing()
        didChangeText()

        setSelectedRange(transformed.selectedRange.offsettingLocation(by: targetRange.location))
    }
}

private extension FileType {
    var lineCommentPrefix: String? {
        switch self {
        case .json, .jsonc, .json5, .jsonl:
            return "//"
        case .yaml, .toml, .shell, .plainText:
            return "#"
        }
    }
}

private extension NSString {
    struct CommentToggleResult {
        let replacement: String
        let selectedRange: NSRange
    }

    func commentableLineRange(for selection: NSRange) -> NSRange {
        let safeLocation = min(max(selection.location, 0), length)
        let safeEnd = min(max(NSMaxRange(selection), safeLocation), length)

        guard length > 0 else {
            return NSRange(location: safeLocation, length: 0)
        }

        if selection.length == 0 {
            return lineRange(for: NSRange(location: safeLocation, length: 0))
        }

        let adjustedEnd = safeEnd > safeLocation && character(at: safeEnd - 1) == 10
            ? safeEnd - 1
            : safeEnd

        return lineRange(for: NSRange(location: safeLocation, length: adjustedEnd - safeLocation))
    }

    func toggledLineComments(
        in targetRange: NSRange,
        prefix: String,
        relativeCaretOffset: Int,
        keepsSelection: Bool
    ) -> CommentToggleResult {
        guard targetRange.location <= length,
              NSMaxRange(targetRange) <= length else {
            return CommentToggleResult(replacement: "", selectedRange: NSRange(location: 0, length: 0))
        }

        let lines = lineInfos(in: targetRange, prefix: prefix)
        let nonBlankLines = lines.filter { !$0.isBlank }
        let shouldUncomment = !nonBlankLines.isEmpty && nonBlankLines.allSatisfy(\.isCommented)
        let insertion = prefix + " "

        var replacement = ""
        replacement.reserveCapacity(targetRange.length + lines.count * insertion.utf16.count)

        var updatedCaretOffset = min(relativeCaretOffset, targetRange.length)
        var didMapCaret = false

        for line in lines {
            if shouldUncomment {
                let rebuiltLine = line.rebuiltLine(uncommentingWith: prefix)
                replacement += rebuiltLine

                if !didMapCaret, relativeCaretOffset >= line.relativeLocation, relativeCaretOffset <= line.relativeEnd {
                    updatedCaretOffset = line.relativeLocation + mappedOffsetWhenUncommenting(
                        originalOffset: relativeCaretOffset - line.relativeLocation,
                        indentLength: line.indentUTF16Length,
                        removedLength: line.removedPrefixUTF16Length
                    )
                    didMapCaret = true
                }
            } else {
                let rebuiltLine = line.rebuiltLine(commentingWith: insertion)
                replacement += rebuiltLine

                if !didMapCaret, relativeCaretOffset >= line.relativeLocation, relativeCaretOffset <= line.relativeEnd {
                    updatedCaretOffset = line.relativeLocation + mappedOffsetWhenCommenting(
                        originalOffset: relativeCaretOffset - line.relativeLocation,
                        indentLength: line.indentUTF16Length,
                        insertedLength: insertion.utf16.count
                    )
                    didMapCaret = true
                }
            }
        }

        let replacementLength = replacement.utf16.count
        return CommentToggleResult(
            replacement: replacement,
            selectedRange: keepsSelection
                ? NSRange(location: 0, length: replacementLength)
                : NSRange(location: min(updatedCaretOffset, replacementLength), length: 0)
        )
    }

    private func mappedOffsetWhenCommenting(
        originalOffset: Int,
        indentLength: Int,
        insertedLength: Int
    ) -> Int {
        if originalOffset < indentLength {
            return originalOffset
        }
        return originalOffset + insertedLength
    }

    private func mappedOffsetWhenUncommenting(
        originalOffset: Int,
        indentLength: Int,
        removedLength: Int
    ) -> Int {
        let removalStart = indentLength
        let removalEnd = indentLength + removedLength

        if originalOffset < removalStart {
            return originalOffset
        }
        if originalOffset <= removalEnd {
            return removalStart
        }
        return originalOffset - removedLength
    }

    private func lineInfos(in targetRange: NSRange, prefix: String) -> [LineInfo] {
        guard targetRange.length > 0 || length == 0 else { return [] }

        var lines: [LineInfo] = []
        let segment = substring(with: targetRange) as NSString
        var lineLocation = 0

        while lineLocation < segment.length {
            let fullLineRange = segment.lineRange(for: NSRange(location: lineLocation, length: 0))
            let clampedEnd = min(NSMaxRange(fullLineRange), segment.length)
            let effectiveLineRange = NSRange(location: lineLocation, length: clampedEnd - lineLocation)
            let lineString = segment.substring(with: effectiveLineRange)
            lines.append(LineInfo(line: lineString, prefix: prefix, relativeLocation: lineLocation))
            lineLocation = clampedEnd
        }

        if lines.isEmpty {
            lines.append(LineInfo(line: "", prefix: prefix, relativeLocation: 0))
        }

        return lines
    }

    struct LineInfo {
        let rawLine: String
        let indent: String
        let contentAfterIndent: String
        let contentAfterPrefix: String
        let lineEnding: String
        let isCommented: Bool
        let isBlank: Bool
        let indentUTF16Length: Int
        let removedPrefixUTF16Length: Int
        let relativeLocation: Int
        let relativeEnd: Int

        init(line: String, prefix: String, relativeLocation: Int) {
            rawLine = line
            let components = line.decomposedLine()

            indent = components.indent
            contentAfterIndent = components.contentAfterIndent
            lineEnding = components.lineEnding
            self.relativeLocation = relativeLocation
            relativeEnd = relativeLocation + line.utf16.count

            let commentInfo = components.contentAfterIndent.commentInfo(prefix: prefix)
            isCommented = commentInfo.isCommented
            contentAfterPrefix = commentInfo.contentAfterPrefix
            removedPrefixUTF16Length = commentInfo.removedPrefixUTF16Length
            indentUTF16Length = indent.utf16.count
            isBlank = contentAfterIndent.isEmpty
        }

        func rebuiltLine(commentingWith insertion: String) -> String {
            indent + insertion + contentAfterIndent + lineEnding
        }

        func rebuiltLine(uncommentingWith prefix: String) -> String {
            guard isCommented else { return rawLine }
            return indent + contentAfterPrefix + lineEnding
        }
    }
}

private extension String {
    struct DecomposedLine {
        let indent: String
        let contentAfterIndent: String
        let lineEnding: String
    }

    struct CommentInfo {
        let isCommented: Bool
        let contentAfterPrefix: String
        let removedPrefixUTF16Length: Int
    }

    func decomposedLine() -> DecomposedLine {
        let lineEnding: String
        let body: String

        if hasSuffix("\r\n") {
            lineEnding = "\r\n"
            body = String(dropLast(2))
        } else if hasSuffix("\n") {
            lineEnding = "\n"
            body = String(dropLast())
        } else {
            lineEnding = ""
            body = self
        }

        let indentEnd = body.firstIndex { !$0.isWhitespace || $0.isNewline } ?? body.endIndex
        let indent = String(body[..<indentEnd])
        let contentAfterIndent = String(body[indentEnd...])

        return DecomposedLine(indent: indent, contentAfterIndent: contentAfterIndent, lineEnding: lineEnding)
    }

    func commentInfo(prefix: String) -> CommentInfo {
        guard hasPrefix(prefix) else {
            return CommentInfo(isCommented: false, contentAfterPrefix: self, removedPrefixUTF16Length: 0)
        }

        var remainder = String(dropFirst(prefix.count))
        var removed = prefix.utf16.count
        if remainder.hasPrefix(" ") {
            remainder.removeFirst()
            removed += 1
        }
        return CommentInfo(isCommented: true, contentAfterPrefix: remainder, removedPrefixUTF16Length: removed)
    }
}

private extension NSRange {
    func offsettingLocation(by offset: Int) -> NSRange {
        NSRange(location: location + offset, length: length)
    }
}
