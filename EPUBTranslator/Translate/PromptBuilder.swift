import Foundation

struct TranslationContext: Equatable {
    var bookID: String?
    var bookTitle: String?
    var bookAuthor: String?
    var chapterTitle: String?
    var paragraph: String?
    var previousParagraph: String?
    var nextParagraph: String?
    var glossary: [String: String] = [:]

    static let empty = TranslationContext()
}

enum TranslationTaskKind: String {
    case selection
    case paragraph
    case word
    case refine
}

struct PromptBuilder {
    var style: TranslationStyle
    var targetLanguage: TargetLanguage
    var customInstruction: String
    var includeContext: Bool

    // MARK: - 翻译

    func messages(text: String, context: TranslationContext, kind: TranslationTaskKind) -> [ChatMessage] {
        [
            ChatMessage.system(systemPrompt(for: kind)),
            ChatMessage.user(userPrompt(text: text, context: context, kind: kind)),
        ]
    }

    func refineMessages(draft: String, source: String, context: TranslationContext) -> [ChatMessage] {
        [
            ChatMessage.system(PromptBuilder.refineSystemPrompt),
            ChatMessage.user(refineUserPrompt(draft: draft, source: source, context: context)),
        ]
    }

    // MARK: - 提示词

    private func systemPrompt(for kind: TranslationTaskKind) -> String {
        var lines: [String] = []
        lines.append("你是「译读」的专属翻译引擎，专门把外语书籍翻译给中文读者。你的译文要像中文作者直接写出来的文字，而不是「译文」。")
        lines.append("")
        lines.append("翻译准则：")
        lines.append("1. 先理解整段语境（人物、语气、时间线、指代关系），再动笔翻译指定的片段。")
        lines.append("2. 只输出译文本身：不要输出原文、拼音、注释、解释，不要用代码块，也不要用引号把译文整体包起来。")
        lines.append("3. 拒绝翻译腔：不要逐词对应，不要保留外语句序，不要滥用「的」「被」「进行」「作为一个」这类结构；长句按中文习惯拆分、合并或重组。")
        lines.append("4. 保留文体：叙述用流畅的书面语，对白要像真人说话并体现说话人身份，动作描写要利落。原文的幽默、反讽、冷峻、温柔都要在中文里重新成立。")
        lines.append("5. 人名、地名使用中文通行译法；同一人物前后译名必须一致。")
        lines.append("6. 度量衡、货币、日期按中文习惯表达（例如 5 feet 写作 1.5 米，$20 写作 20 美元）。")
        lines.append("7. 对白使用中文引号「」，并列成分用顿号，破折号用——，省略号用……。")
        lines.append("8. 不要「补戏」：原文没说的事不要添加，原文语气弱就不要加强，不要替作者抒情。")
        lines.append("9. 自动判断原文语言并翻译成\(targetLanguage.title)。如果原文已经是\(targetLanguage.title)，就只做润色，让它更通顺自然。")
        lines.append("")
        lines.append("风格要求：\(style.instruction)")

        switch kind {
        case .selection:
            lines.append("")
            lines.append("注意：这次只翻译被 <<< 与 >>> 包围的片段。它可能只是整段中的一句话，请借助上下文判断指代和语气，但不要把上下文一并翻译出来。")
        case .paragraph:
            lines.append("")
            lines.append("这次翻译 <<< 与 >>> 之间的整个段落，保持原有的段落划分。")
        case .word:
            lines.append("")
            lines.append("这次是一个词或短语：请只给出一行中文释义，先给最贴合当前语境的译法，必要时用「/」补充 1~2 个替代译法，可用（名词）（动词）之类的极短标注。不要展开解释。")
        case .refine:
            break
        }

        if !customInstruction.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            lines.append("")
            lines.append("读者的额外要求（优先级最高）：\(customInstruction.trimmingCharacters(in: .whitespacesAndNewlines))")
        }
        return lines.joined(separator: "\n")
    }

    private func userPrompt(text: String, context: TranslationContext, kind: TranslationTaskKind) -> String {
        var blocks: [String] = []

        var bookLine = ""
        if let title = context.bookTitle, !title.isEmpty {
            bookLine = "《\(title)》"
            if let author = context.bookAuthor, !author.isEmpty {
                bookLine += " · \(author)"
            }
        }
        if !bookLine.isEmpty {
            blocks.append("【书籍】\(bookLine)")
        }
        if let chapter = context.chapterTitle, !chapter.isEmpty {
            blocks.append("【章节】\(chapter)")
        }
        blocks.append("【目标语言】\(targetLanguage.title)　【风格】\(style.title)")

        if includeContext {
            if let previous = context.previousParagraph, !previous.isEmpty {
                blocks.append("【上文】(仅用于理解语境，不要翻译)\n\(previous)")
            }
            if let paragraph = context.paragraph, !paragraph.isEmpty, kind != .word {
                blocks.append("【所在段落】(仅用于理解语境，不要翻译)\n\(paragraph)")
            }
            if let next = context.nextParagraph, !next.isEmpty {
                blocks.append("【下文】(仅用于理解语境，不要翻译)\n\(next)")
            }
        }

        if !context.glossary.isEmpty, includeContext {
            let terms = context.glossary
                .sorted { $0.key < $1.key }
                .prefix(60)
                .map { "\($0.key) = \($0.value)" }
                .joined(separator: "\n")
            blocks.append("【术语表】(必须沿用以下译名)\n\(terms)")
        }

        blocks.append("【待翻译】只翻译下面 <<< 与 >>> 之间的内容：\n<<<\n\(text)\n>>>")

        return blocks.joined(separator: "\n\n")
    }

    private static let refineSystemPrompt = """
    你是一位资深中文文学编辑，专门负责把「翻译腔」很重的初稿改写成地道、好读的中文。

    改写准则：
    1. 只输出改写后的译文。不要解释、不要对照原文、不要加任何前后缀说明。
    2. 可以调整语序、拆分或合并句子、替换用词、去掉多余的「的」「被」「进行」，但不能改变原意，不能增删信息。
    3. 保持原文的文体与语气：叙述、对白、内心独白要有区别。
    4. 专有名词、术语、已定的译名必须沿用初稿，不要另起译名。
    5. 如果初稿已经足够自然，就做最小的改动，不要为了改而改。
    """

    private func refineUserPrompt(draft: String, source: String, context: TranslationContext) -> String {
        var blocks: [String] = []
        if let title = context.bookTitle, !title.isEmpty {
            var line = "【书籍】《\(title)》"
            if let author = context.bookAuthor, !author.isEmpty { line += " · \(author)" }
            blocks.append(line)
        }
        blocks.append("【目标语言】\(targetLanguage.title)　【风格】\(style.title)")
        if includeContext, let previous = context.previousParagraph, !previous.isEmpty {
            blocks.append("【上文】(仅用于理解语境)\n\(previous)")
        }
        if includeContext, let next = context.nextParagraph, !next.isEmpty {
            blocks.append("【下文】(仅用于理解语境)\n\(next)")
        }
        blocks.append("【原文】\n\(source)")
        blocks.append("【初稿】\n\(draft)")
        blocks.append("请输出改写后的译文，直接给出结果。")
        return blocks.joined(separator: "\n\n")
    }
}
