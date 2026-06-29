import AppKit

/// A small, generic, single-pass tokenizer that colors source text for the
/// One Dark scheme. It is deliberately language-agnostic: a `Grammar` supplies
/// comment/string delimiters and a keyword set, and the scanner handles
/// strings, numbers, comments, keywords, constants, function calls, and types.
struct Tokenizer {
    private let chars: [Character]
    private let n: Int
    private let grammar: Grammar

    // Precomputed delimiter character arrays for fast matching.
    private let lineComments: [[Character]]
    private let blockOpen: [Character]
    private let blockClose: [Character]
    private let hasBlock: Bool

    private let theme: HighlightTheme
    private let font: NSFont

    private let result = NSMutableAttributedString()
    private var pending = ""

    init(text: String, grammar: Grammar, theme: HighlightTheme, font: NSFont) {
        self.chars = Array(text)
        self.n = chars.count
        self.grammar = grammar
        self.theme = theme
        self.font = font
        self.lineComments = grammar.lineComments.map(Array.init)
        self.blockOpen = grammar.blockComment.map { Array($0.open) } ?? []
        self.blockClose = grammar.blockComment.map { Array($0.close) } ?? []
        self.hasBlock = grammar.blockComment != nil
    }

    mutating func run() -> NSAttributedString {
        var i = 0
        while i < n {
            let c = chars[i]

            // 1. Block comment
            if hasBlock, matches(blockOpen, at: i) {
                var j = i + blockOpen.count
                while j < n, !matches(blockClose, at: j) { j += 1 }
                let end = j < n ? j + blockClose.count : n
                emit(slice(i, end), theme.nsComment, italic: true)
                i = end
                continue
            }

            // 2. Line comment
            if let token = lineComment(at: i) {
                var j = i + token.count
                while j < n, chars[j] != "\n" { j += 1 }
                emit(slice(i, j), theme.nsComment, italic: true)
                i = j
                continue
            }

            // 3. String literal (with optional triple-quotes)
            if grammar.strings.contains(c) {
                let end = consumeString(from: i, delimiter: c)
                emit(slice(i, end), theme.nsString)
                i = end
                continue
            }

            // 4. Number
            let prevWord = i > 0 && isWordChar(chars[i - 1])
            if c.isNumber || (c == "." && i + 1 < n && chars[i + 1].isNumber && !prevWord) {
                let end = consumeNumber(from: i)
                emit(slice(i, end), theme.nsNumber)
                i = end
                continue
            }

            // 5. Identifier / keyword / constant / function / type
            if c.isLetter || c == "_" || c == "$" {
                var j = i
                while j < n, isWordChar(chars[j]) { j += 1 }
                // Defensive: a zero-width match would hang the scanner. The entry
                // chars above are all word chars so this can't happen today, but
                // it guarantees forward progress regardless of future edits.
                if j == i {
                    pending.append(c)
                    i += 1
                    continue
                }
                let word = String(chars[i..<j])
                style(identifier: word, endIndex: j)
                i = j
                continue
            }

            // 6. Anything else — accumulate as default-colored text.
            pending.append(c)
            i += 1
        }
        flush()
        return result
    }

    // MARK: Classification

    private mutating func style(identifier word: String, endIndex j: Int) {
        let keywordKey = grammar.caseInsensitiveKeywords ? word.lowercased() : word
        if grammar.keywords.contains(keywordKey) {
            emit(word, theme.nsKeyword)
        } else if grammar.constants.contains(word.lowercased()) {
            emit(word, theme.nsNumber)
        } else if isFunctionCall(after: j) {
            emit(word, theme.nsFunction)
        } else if let first = word.first, first.isUppercase {
            emit(word, theme.nsType)
        } else {
            pending += word // default color — coalesce
        }
    }

    private func isFunctionCall(after index: Int) -> Bool {
        var k = index
        while k < n, chars[k] == " " || chars[k] == "\t" { k += 1 }
        return k < n && chars[k] == "("
    }

    // MARK: Scanning helpers

    private func consumeString(from i: Int, delimiter: Character) -> Int {
        // Triple-quoted (e.g. Python/Swift """ … """).
        if grammar.tripleQuotes, i + 2 < n, chars[i + 1] == delimiter, chars[i + 2] == delimiter {
            var j = i + 3
            while j < n {
                if chars[j] == "\\" { j += 2; continue }
                if chars[j] == delimiter, j + 2 < n, chars[j + 1] == delimiter, chars[j + 2] == delimiter {
                    return j + 3
                }
                j += 1
            }
            return n
        }

        var j = i + 1
        let allowsEscape = delimiter != "`"
        while j < n {
            let ch = chars[j]
            if ch == "\\", allowsEscape { j += 2; continue }
            if ch == delimiter { return j + 1 }
            if ch == "\n", delimiter != "`" { return j } // unterminated single-line string
            j += 1
        }
        return n
    }

    private func consumeNumber(from i: Int) -> Int {
        var j = i
        if chars[j] == "0", j + 1 < n, chars[j + 1] == "x" || chars[j + 1] == "X" {
            j += 2
            while j < n, chars[j].isHexDigit || chars[j] == "_" { j += 1 }
            return j
        }
        if chars[j] == "0", j + 1 < n, chars[j + 1] == "b" || chars[j + 1] == "B" {
            j += 2
            while j < n, chars[j] == "0" || chars[j] == "1" || chars[j] == "_" { j += 1 }
            return j
        }
        while j < n {
            let ch = chars[j]
            if ch.isNumber || ch == "." || ch == "_" || ch == "e" || ch == "E" {
                j += 1
            } else if (ch == "+" || ch == "-"), j > i, chars[j - 1] == "e" || chars[j - 1] == "E" {
                j += 1 // exponent sign
            } else {
                break
            }
        }
        return j
    }

    private func lineComment(at i: Int) -> [Character]? {
        for token in lineComments where matches(token, at: i) { return token }
        return nil
    }

    private func matches(_ token: [Character], at i: Int) -> Bool {
        guard !token.isEmpty, i + token.count <= n else { return false }
        for k in 0..<token.count where chars[i + k] != token[k] { return false }
        return true
    }

    private func isWordChar(_ c: Character) -> Bool {
        c.isLetter || c.isNumber || c == "_" || c == "$"
    }

    private func slice(_ a: Int, _ b: Int) -> String {
        String(chars[a..<min(b, n)])
    }

    // MARK: Emission (coalesces default-colored runs)

    private mutating func flush() {
        if !pending.isEmpty {
            result.append(SyntaxHighlighter.segment(pending, theme.nsForeground, font: font))
            pending = ""
        }
    }

    private mutating func emit(_ text: String, _ color: NSColor, italic: Bool = false) {
        flush()
        result.append(SyntaxHighlighter.segment(text, color, font: font, italic: italic))
    }
}
