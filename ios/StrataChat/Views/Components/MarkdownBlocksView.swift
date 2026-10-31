import SwiftUI

/// Block level markdown for chat replies.
///
/// The previous renderer handed each non code chunk straight to Text, so headings, bullets and
/// tables kept their markdown characters and the phone showed something different from the desktop.
/// This splits a reply into blocks first, then styles each kind: headings, lists, quotes, rules,
/// tables as aligned monospace, and paragraphs with inline emphasis.
enum MarkdownBlockKind {
    case heading(Int)
    case listItem
    case quote
    case rule
    case table
    case paragraph
    // `::: title` ... `:::` folds. The summary stays in the transcript and the depth sits
    // collapsed underneath, which is what makes a long answer short by default.
    case details(String)
}

struct MarkdownBlock: Identifiable {
    let id: Int
    let kind: MarkdownBlockKind
    let lines: [String]
    var marker: String = ""
}

private let bulletPattern = "^\\s*([-*•]|[0-9]{1,2}[.)])\\s+"
private let headingPattern = "^\\s*#{1,6}\\s"
private let tableSeparatorPattern = "^[|:\\-+\\s]+$"

private final class MarkdownBlocksBox: NSObject {
    let value: [MarkdownBlock]
    init(_ value: [MarkdownBlock]) { self.value = value }
}

private final class AttributedMarkdownBox: NSObject {
    let value: AttributedString
    init(_ value: AttributedString) { self.value = value }
}

/// A reply is re-rendered on every stream publish, on every keystroke in the composer and on
/// every 12s transcript refresh. Parsing and inline markdown are pure functions of the text,
/// so they are cached by the text itself: only the row that actually changed pays for them.
final class MarkdownRenderCache {
    static let shared = MarkdownRenderCache()
    
    private let blocks = NSCache<NSString, MarkdownBlocksBox>()
    private let inline = NSCache<NSString, AttributedMarkdownBox>()
    
    init() {
        blocks.countLimit = 140
        inline.countLimit = 4000
    }
    
    func parse(_ text: String) -> [MarkdownBlock] {
        let key = text as NSString
        if let hit = blocks.object(forKey: key) { return hit.value }
        let parsed = parseMarkdownBlocks(text)
        blocks.setObject(MarkdownBlocksBox(parsed), forKey: key)
        return parsed
    }
    
    func inlineText(_ text: String) -> AttributedString {
        let key = text as NSString
        if let hit = inline.object(forKey: key) { return hit.value }
        let built: AttributedString
        // Model output is not always valid markdown, so an unparseable span degrades to plain
        // text rather than rendering nothing.
        if let parsed = try? AttributedString(markdown: text) {
            built = parsed
        } else {
            built = AttributedString(text)
        }
        inline.setObject(AttributedMarkdownBox(built), forKey: key)
        return built
    }
}

func parseMarkdownBlocks(_ content: String) -> [MarkdownBlock] {
    var blocks: [MarkdownBlock] = []
    var paragraph: [String] = []
    var table: [String] = []
    var fold: [String] = []
    var foldTitle = "Details"
    var nextId = 0

    func flushFold() {
        guard !fold.isEmpty else { return }
        blocks.append(MarkdownBlock(id: nextId, kind: .details(foldTitle), lines: fold))
        nextId += 1
        fold = []
        foldTitle = "Details"
    }

    func flushParagraph() {
        guard !paragraph.isEmpty else { return }
        blocks.append(MarkdownBlock(id: nextId, kind: .paragraph, lines: paragraph))
        nextId += 1
        paragraph = []
    }

    func flushTable() {
        guard table.count >= 2 else {
            table.forEach { paragraph.append($0) }
            table = []
            return
        }
        blocks.append(MarkdownBlock(id: nextId, kind: .table, lines: table))
        nextId += 1
        table = []
    }

    for raw in content.components(separatedBy: "\n") {
        let line = raw.trimmingCharacters(in: .whitespaces)

        if line.hasPrefix("|") && line.count > 1 {
            flushParagraph()
            table.append(line)
            continue
        }

        if line.isEmpty {
            flushTable()
            flushParagraph()
            continue
        }

        if line.range(of: headingPattern, options: .regularExpression) != nil {
            flushTable()
            flushParagraph()
            let depth = min(max(line.prefix(while: { $0 == "#" }).count, 1), 4)
            let body = line.drop(while: { $0 == "#" }).trimmingCharacters(in: .whitespaces)
            blocks.append(MarkdownBlock(id: nextId, kind: .heading(depth), lines: [body]))
            nextId += 1
            continue
        }

        if line == "---" || line == "***" || line == "___" {
            flushTable()
            flushParagraph()
            blocks.append(MarkdownBlock(id: nextId, kind: .rule, lines: []))
            nextId += 1
            continue
        }

        if line.hasPrefix(">") {
            flushTable()
            flushParagraph()
            let body = line.drop(while: { $0 == ">" }).trimmingCharacters(in: .whitespaces)
            blocks.append(MarkdownBlock(id: nextId, kind: .quote, lines: [body]))
            nextId += 1
            continue
        }

        if let markerRange = line.range(of: bulletPattern, options: .regularExpression) {
            flushTable()
            flushParagraph()
            let marker = String(line[markerRange]).trimmingCharacters(in: .whitespaces)
            let glyph = ["-", "*", "\u{2022}"].contains(marker) ? "\u{2022}" : marker
            let body = line.replacingOccurrences(of: bulletPattern, with: "", options: .regularExpression)
            blocks.append(MarkdownBlock(id: nextId, kind: .listItem, lines: [body], marker: glyph))
            nextId += 1
            continue
        }

        if line.trimmingCharacters(in: .whitespaces).hasPrefix(":::") {
            if fold.isEmpty {
                flushParagraph()
                flushTable()
                let title = line.trimmingCharacters(in: .whitespaces)
                    .dropFirst(3).trimmingCharacters(in: .whitespaces)
                foldTitle = title.isEmpty ? "Details" : title
            } else {
                flushFold()
            }
            continue
        }

        flushTable()
        paragraph.append(line)
    }

    flushFold()
    flushTable()
    flushParagraph()
    return blocks
}

private func inlineMarkdown(_ text: String) -> AttributedString {
    MarkdownRenderCache.shared.inlineText(text)
}

private func isTableSeparator(_ cells: [String]) -> Bool {
    guard !cells.isEmpty else { return false }
    return cells.allSatisfy { cell in
        !cell.isEmpty && cell.range(of: tableSeparatorPattern, options: .regularExpression) != nil
    }
}

/// Flip a wide pipe table into per-row "column : value" cards.
/// Returns nil when the table is narrow enough to keep its normal wide layout.
/// Transposed (one card per row) is the default for 3+ column tables because the wide layout
/// needs sideways panning. Settings can flip it back to the wide monospace table per user.
private func transposedAllowed() -> Bool {
    UserDefaults.standard.object(forKey: "transposed_tables_enabled") as? Bool ?? true
}

/// `::: title` stores the title in the block kind, so the fold body is everything after it.
private func foldBody(_ lines: [String]) -> String {
    lines.joined(separator: "\n")
}

private func transposedTable(_ lines: [String]) -> [[String]]? {
    let rows: [[String]] = lines.map { line in
        line.trimmingCharacters(in: CharacterSet(charactersIn: " |"))
            .components(separatedBy: "|")
            .map { $0.trimmingCharacters(in: .whitespaces) }
    }.filter { !$0.isEmpty }

    guard rows.count >= 2 else { return nil }
    let columnCount = rows.map { $0.count }.max() ?? 0
    guard columnCount >= 3 else { return nil }

    let headers = rows[0]
    var cards: [[String]] = []
    for row in rows.dropFirst() where !isTableSeparator(row) {
        var lines: [String] = []
        for column in 0..<columnCount {
            let label = column < headers.count && !headers[column].isEmpty ? headers[column] : "Column \(column + 1)"
            let value = column < row.count ? row[column] : ""
            if value.isEmpty { continue }
            lines.append("\(label): \(value)")
        }
        if !lines.isEmpty { cards.append(lines) }
    }
    return cards.isEmpty ? nil : cards
}

/// Align a pipe table into monospace text so the column structure survives a narrow screen.
private func renderTable(_ lines: [String]) -> String {
    let rows: [[String]] = lines.map { line in
        line.trimmingCharacters(in: CharacterSet(charactersIn: " |"))
            .components(separatedBy: "|")
            .map { $0.trimmingCharacters(in: .whitespaces) }
    }
    guard !rows.isEmpty else { return "" }
    let columnCount = rows.map { $0.count }.max() ?? 0
    guard columnCount > 0 else { return lines.joined(separator: "\n") }

    var widths = Array(repeating: 3, count: columnCount)
    for row in rows {
        for (index, cell) in row.enumerated() where index < columnCount {
            widths[index] = min(max(widths[index], cell.count), 48)
        }
    }

    func pad(_ cell: String, _ width: Int) -> String {
        if cell.count > width {
            return String(cell.prefix(max(width - 1, 1))) + "…"
        }
        return cell.padding(toLength: width, withPad: " ", startingAt: 0)
    }

    var output: [String] = []
    for row in rows {
        if isTableSeparator(row) {
            output.append(widths.map { String(repeating: "-", count: $0) }.joined(separator: "-+-"))
            continue
        }
        let cells = (0..<columnCount).map { column -> String in
            pad(column < row.count ? row[column] : "", widths[column])
        }
        output.append(cells.joined(separator: " | "))
    }
    return output.joined(separator: "\n")
}

/// Body of a `:::` fold. A separate View type rather than a call back into `blockView`,
/// because Swift cannot infer a return type that is defined in terms of itself.
struct FoldBodyView: View {
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(MarkdownRenderCache.shared.parse(text)) { block in
                MarkdownBlocksView.blockView(block)
            }
        }
    }
}

public struct MarkdownBlocksView: View {
    let text: String

    public init(text: String) {
        self.text = text
    }

    public var body: some View {
        // Flat 8pt between every block is why a reply reads as one wall: a heading needs more air
        // than the line above it, and a list item needs less than the paragraph after it.
        VStack(alignment: .leading, spacing: 8) {
            ForEach(MarkdownRenderCache.shared.parse(text)) { block in
                Self.blockView(block)
                    .padding(.top, topGap(before: block))
            }
        }
    }

    private func topGap(before block: MarkdownBlock) -> CGFloat {
        if block.id == 0 { return 0 }
        if case .heading = block.kind { return 8 }
        return 0
    }

    @ViewBuilder
    static func blockView(_ block: MarkdownBlock) -> some View {
        switch block.kind {
        case .heading(let depth):
            Text(inlineMarkdown(block.lines.joined(separator: " ")))
                .font(.system(size: headingSize(depth), weight: .bold))
                .foregroundColor(depth <= 2 ? Color(hex: "c9b8ff") : .white)
                .fixedSize(horizontal: false, vertical: true)

        case .listItem:
            HStack(alignment: .top, spacing: 8) {
                Text(block.marker.isEmpty ? "•" : block.marker)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(Color(hex: "7c5cff"))
                    .frame(width: 12, alignment: .leading)
                Text(inlineMarkdown(block.lines.joined(separator: " ")))
                    .font(.system(size: 15.5))
                    .foregroundColor(.white)
                    .fixedSize(horizontal: false, vertical: true)
            }

        case .quote:
            HStack(alignment: .top, spacing: 8) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color(hex: "7c5cff").opacity(0.6))
                    .frame(width: 3)
                Text(inlineMarkdown(block.lines.joined(separator: " ")))
                    .font(.system(size: 15))
                    .italic()
                    .foregroundColor(.white.opacity(0.85))
                    .fixedSize(horizontal: false, vertical: true)
            }

        case .rule:
            Divider()
                .overlay(Color.white.opacity(0.12))

        case .table:
            // Wide tables become tall ones on a phone: a 5-column table needs sideways panning
            // that fights the transcript, so 3+ column tables render as one card per row with
            // "column : value" lines instead. Two-column tables already fit without scrolling.
            if let transposed = transposedTable(block.lines), transposedAllowed() {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(transposed.enumerated()), id: \.offset) { _, lines in
                        Text(lines.joined(separator: "\n"))
                            .font(.system(size: 13.5, design: .monospaced))
                            .foregroundColor(.white.opacity(0.92))
                            .multilineTextAlignment(.leading)
                            .textSelection(.enabled)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 7)
                    }
                }
                .background(Color.black.opacity(0.35))
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.white.opacity(0.10), lineWidth: 1))
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    Text(renderTable(block.lines))
                        .font(.system(size: 12.5, design: .monospaced))
                        .foregroundColor(.white.opacity(0.92))
                        .multilineTextAlignment(.leading)
                        .textSelection(.enabled)
                        .padding(10)
                }
                .background(Color.black.opacity(0.35))
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.white.opacity(0.10), lineWidth: 1))
            }

        case .paragraph:
            Text(inlineMarkdown(block.lines.joined(separator: "\n")))
                .font(.system(size: 15.5))
                .foregroundColor(.white)
                .lineSpacing(3)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)

        case .details(let title):
            DisclosureGroup {
                FoldBodyView(text: foldBody(block.lines))
                    .padding(.top, 4)
            } label: {
                Text(title)
                    .font(.system(size: 13.5, weight: .semibold))
                    .foregroundColor(Color(hex: "c9b8ff"))
            }
            .tint(Color(hex: "c9b8ff"))
            .padding(10)
            .background(Color.white.opacity(0.04))
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
    }

    static func headingSize(_ depth: Int) -> CGFloat {
        switch depth {
        case 1: return 20
        case 2: return 18
        case 3: return 16.5
        default: return 15.5
        }
    }
}
