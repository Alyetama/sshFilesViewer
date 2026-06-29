import SwiftUI
import AppKit

extension Color {
    init(hex: UInt32) {
        self = Color(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }
}

extension NSColor {
    convenience init(hex: UInt32) {
        self.init(
            srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1
        )
    }
}

// MARK: - Grammar

struct Grammar {
    var lineComments: [String] = []
    var blockComment: (open: String, close: String)? = nil
    var strings: [Character] = ["\"", "'"]
    var keywords: Set<String> = []
    var constants: Set<String> = Grammar.defaultConstants
    var caseInsensitiveKeywords = false
    var tripleQuotes = false

    static let defaultConstants: Set<String> = ["true", "false", "null", "nil", "none", "undefined", "nan"]

    static func words(_ s: String) -> Set<String> {
        Set(s.split(whereSeparator: { $0 == " " || $0 == "\n" }).map(String.init))
    }
}

// MARK: - Highlighter

enum SyntaxHighlighter {
    /// Soft cap — above this we skip tokenizing and render plain (still themed).
    /// NSTextView handles the actual display of large files cheaply; this only
    /// bounds how much we spend building colored runs.
    private static let maxHighlightChars = 120_000

    static func monospacedFont(_ size: CGFloat) -> NSFont {
        NSFont.monospacedSystemFont(ofSize: size, weight: .regular)
    }

    static func highlight(_ text: String, ext: String,
                          theme: HighlightTheme, fontSize: CGFloat) -> NSAttributedString {
        let font = monospacedFont(fontSize)
        if text.isEmpty { return segment("(empty file)", theme.nsComment, font: font, italic: true) }
        guard let grammar = grammar(for: ext), text.count <= maxHighlightChars else {
            return segment(text, theme.nsForeground, font: font)
        }
        var tokenizer = Tokenizer(text: text, grammar: grammar, theme: theme, font: font)
        return tokenizer.run()
    }

    static func segment(_ text: String, _ color: NSColor, font: NSFont, italic: Bool = false) -> NSAttributedString {
        var attrs: [NSAttributedString.Key: Any] = [.foregroundColor: color, .font: font]
        if italic { attrs[.obliqueness] = 0.18 } // slanted comments without needing an italic face
        return NSAttributedString(string: text, attributes: attrs)
    }

    // MARK: Grammar table

    static func grammar(for ext: String) -> Grammar? {
        switch ext {
        case "swift":
            return Grammar(lineComments: ["//"], blockComment: ("/*", "*/"),
                           keywords: Grammar.words("associatedtype class deinit enum extension fileprivate func import init inout internal let open operator private protocol public rethrows static struct subscript typealias var break case continue default defer do else fallthrough for guard if in repeat return switch where while as catch is throw throws try async await some any actor lazy weak unowned final override convenience required mutating nonmutating dynamic indirect self Self super get set willSet didSet"),
                           tripleQuotes: true)
        case "js", "jsx", "mjs", "cjs":
            return Grammar(lineComments: ["//"], blockComment: ("/*", "*/"), strings: ["\"", "'", "`"],
                           keywords: jsKeywords)
        case "ts", "tsx":
            return Grammar(lineComments: ["//"], blockComment: ("/*", "*/"), strings: ["\"", "'", "`"],
                           keywords: jsKeywords.union(Grammar.words("interface type enum namespace declare abstract implements private public protected readonly is keyof infer never unknown any number string boolean object symbol satisfies override")))
        case "py", "pyw":
            return Grammar(lineComments: ["#"], strings: ["\"", "'"],
                           keywords: Grammar.words("and as assert async await break class continue def del elif else except finally for from global if import in is lambda nonlocal not or pass raise return try while with yield match case self"),
                           tripleQuotes: true)
        case "go":
            return Grammar(lineComments: ["//"], blockComment: ("/*", "*/"), strings: ["\"", "'", "`"],
                           keywords: Grammar.words("break case chan const continue default defer else fallthrough for func go goto if import interface map package range return select struct switch type var"))
        case "rs":
            return Grammar(lineComments: ["//"], blockComment: ("/*", "*/"),
                           keywords: Grammar.words("as async await break const continue crate dyn else enum extern fn for if impl in let loop match mod move mut pub ref return self Self static struct super trait type unsafe use where while macro_rules union box"))
        case "rb":
            return Grammar(lineComments: ["#"], blockComment: ("=begin", "=end"),
                           keywords: Grammar.words("begin break case class def defined do else elsif end ensure for if in module next not or redo rescue retry return self super then unless until when while yield and require require_relative attr_accessor attr_reader attr_writer lambda proc puts new"))
        case "c", "h", "m":
            return Grammar(lineComments: ["//"], blockComment: ("/*", "*/"), keywords: cKeywords)
        case "cpp", "cc", "cxx", "hpp", "hh", "hxx", "mm":
            return Grammar(lineComments: ["//"], blockComment: ("/*", "*/"),
                           keywords: cKeywords.union(Grammar.words("class namespace template typename public private protected virtual override final new delete this operator friend using try catch throw nullptr constexpr noexcept explicit mutable decltype static_cast dynamic_cast reinterpret_cast const_cast")))
        case "java":
            return Grammar(lineComments: ["//"], blockComment: ("/*", "*/"),
                           keywords: Grammar.words("abstract assert boolean break byte case catch char class const continue default do double else enum extends final finally float for goto if implements import instanceof int interface long native new package private protected public return short static strictfp super switch synchronized this throw throws transient try void volatile while var record sealed yield"))
        case "kt", "kts":
            return Grammar(lineComments: ["//"], blockComment: ("/*", "*/"), strings: ["\"", "'"],
                           keywords: Grammar.words("as break class continue do else enum for fun if import in interface is object package return super this throw try typealias val var when while by catch constructor finally get init out override private protected public sealed set suspend companion data lateinit inline reified open internal abstract"),
                           tripleQuotes: true)
        case "cs":
            return Grammar(lineComments: ["//"], blockComment: ("/*", "*/"),
                           keywords: Grammar.words("abstract as base bool break byte case catch char checked class const continue decimal default delegate do double else enum event explicit extern finally fixed float for foreach goto if implicit in int interface internal is lock long namespace new object operator out override params private protected public readonly ref return sbyte sealed short sizeof stackalloc static string struct switch this throw try typeof uint ulong unchecked unsafe ushort using virtual void volatile while var async await get set record"))
        case "php":
            return Grammar(lineComments: ["//", "#"], blockComment: ("/*", "*/"),
                           keywords: Grammar.words("abstract and array as break callable case catch class clone const continue declare default do echo else elseif empty endif endfor endforeach endwhile extends final finally fn for foreach function global goto if implements include include_once instanceof insteadof interface isset list namespace new or print private protected public require require_once return static switch throw trait try unset use var while xor yield"))
        case "sh", "bash", "zsh", "fish":
            return Grammar(lineComments: ["#"],
                           keywords: Grammar.words("if then else elif fi case esac for while until do done function in select return local export readonly declare unset shift eval exec trap set source alias echo cd test"))
        case "lua":
            return Grammar(lineComments: ["--"], blockComment: ("--[[", "]]"),
                           keywords: Grammar.words("and break do else elseif end for function goto if in local not or repeat return then until while"))
        case "r":
            return Grammar(lineComments: ["#"],
                           keywords: Grammar.words("if else repeat while function for in next break"))
        case "pl", "pm":
            return Grammar(lineComments: ["#"],
                           keywords: Grammar.words("if elsif else unless while until for foreach do sub return my our local use require package print say next last redo and or not eq ne lt gt le ge"))
        case "sql":
            return Grammar(lineComments: ["--"], blockComment: ("/*", "*/"), strings: ["'"],
                           keywords: Grammar.words("select from where insert update delete into values create table drop alter add column index view join inner left right outer full on group by order having limit offset union all distinct as and or not is in like between exists case when then else end set primary key foreign references default constraint unique check cascade trigger procedure function begin commit rollback transaction grant revoke with returning desc asc count sum avg min max"),
                           caseInsensitiveKeywords: true)
        case "json":
            return Grammar(strings: ["\""], keywords: [])
        case "yaml", "yml":
            return Grammar(lineComments: ["#"], strings: ["\"", "'"], keywords: [],
                           constants: ["true", "false", "null", "yes", "no", "on", "off", "~"])
        case "toml", "ini", "cfg", "conf", "env":
            return Grammar(lineComments: ["#", ";"], keywords: [], constants: ["true", "false"])
        case "css", "scss", "sass", "less":
            return Grammar(blockComment: ("/*", "*/"), strings: ["\"", "'"], keywords: [])
        case "html", "htm", "xml", "svg", "vue", "xhtml":
            return Grammar(blockComment: ("<!--", "-->"), strings: ["\"", "'"], keywords: [])
        case "md", "markdown", "txt", "log", "rst":
            return nil // prose — leave unstyled
        default:
            return nil
        }
    }

    private static let jsKeywords = Grammar.words("break case catch class const continue debugger default delete do else export extends finally for function if import in instanceof new return super switch this throw try typeof var void while with yield let static get set async await of as from")
    private static let cKeywords = Grammar.words("auto break case char const continue default do double else enum extern float for goto if inline int long register restrict return short signed sizeof static struct switch typedef union unsigned void volatile while bool size_t")
}
