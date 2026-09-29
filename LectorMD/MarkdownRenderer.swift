import Foundation

struct MarkdownRenderer {

    func render(_ markdown: String) -> String {
        let normalized = markdown
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        return renderBlocks(normalized)
    }

    // MARK: - Block rendering

    private func renderBlocks(_ text: String) -> String {
        var out = ""
        let lines = text.components(separatedBy: "\n")
        var i = 0

        while i < lines.count {
            let line = lines[i]
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed.isEmpty { i += 1; continue }

            // Fenced code block
            if trimmed.hasPrefix("```") || trimmed.hasPrefix("~~~") {
                let fence = String(trimmed.prefix(3))
                let lang = String(trimmed.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                i += 1
                var codeLines: [String] = []
                while i < lines.count && !lines[i].trimmingCharacters(in: .whitespaces).hasPrefix(fence) {
                    codeLines.append(lines[i]); i += 1
                }
                if i < lines.count { i += 1 }
                if lang.lowercased() == "mermaid" {
                    // Escapado como texto: mermaid lee el textContent, que queda igual al original
                    let safe = HTMLSafety.escapeText(codeLines.joined(separator: "\n"))
                    out += "<div class=\"mermaid\">\(safe)</div>\n"
                } else {
                    let code = HTMLSafety.escapeText(codeLines.joined(separator: "\n"))
                    // Como en CommonMark, el lenguaje es la primera palabra de la línea
                    let name = lang.split(whereSeparator: { $0 == " " || $0 == "\t" }).first.map(String.init) ?? ""
                    let cls = name.isEmpty ? "" : " class=\"language-\(HTMLSafety.escapeAttribute(name))\""
                    out += "<pre><code\(cls)>\(code)</code></pre>\n"
                }
                continue
            }

            // ATX heading
            if let h = parseATXHeading(trimmed) {
                let id = HTMLSafety.escapeAttribute(Self.slugify(h.text))
                out += "<h\(h.level) id=\"\(id)\">\(renderInline(h.text))</h\(h.level)>\n"
                i += 1; continue
            }

            // Setext heading
            if i + 1 < lines.count {
                let next = lines[i + 1].trimmingCharacters(in: .whitespaces)
                if !trimmed.isEmpty && next.count >= 2 && next.allSatisfy({ $0 == "=" }) {
                    let id = HTMLSafety.escapeAttribute(Self.slugify(trimmed))
                    out += "<h1 id=\"\(id)\">\(renderInline(trimmed))</h1>\n"
                    i += 2; continue
                }
                if !trimmed.isEmpty && next.count >= 2 && next.allSatisfy({ $0 == "-" }) && !isHRule(trimmed) {
                    let id = HTMLSafety.escapeAttribute(Self.slugify(trimmed))
                    out += "<h2 id=\"\(id)\">\(renderInline(trimmed))</h2>\n"
                    i += 2; continue
                }
            }

            // Horizontal rule
            if isHRule(trimmed) {
                out += "<hr>\n"; i += 1; continue
            }

            // Blockquote
            if trimmed.hasPrefix(">") {
                var quoteLines: [String] = []
                while i < lines.count {
                    let t = lines[i].trimmingCharacters(in: .whitespaces)
                    if t.hasPrefix("> ") { quoteLines.append(String(t.dropFirst(2))); i += 1 }
                    else if t == ">" { quoteLines.append(""); i += 1 }
                    else if t.isEmpty && i + 1 < lines.count && lines[i + 1].trimmingCharacters(in: .whitespaces).hasPrefix(">") {
                        quoteLines.append(""); i += 1
                    } else { break }
                }
                out += "<blockquote>\n\(renderBlocks(quoteLines.joined(separator: "\n")))</blockquote>\n"
                continue
            }

            // Unordered list
            if isUnorderedItem(trimmed) {
                out += "<ul>\n"
                while i < lines.count {
                    let t = lines[i].trimmingCharacters(in: .whitespaces)
                    guard isUnorderedItem(t) else { break }
                    let item = stripUnorderedPrefix(t)
                    out += "<li>\(renderTaskOrInline(item))</li>\n"
                    i += 1
                }
                out += "</ul>\n"; continue
            }

            // Ordered list
            if isOrderedItem(trimmed) {
                out += "<ol>\n"
                while i < lines.count {
                    let t = lines[i].trimmingCharacters(in: .whitespaces)
                    guard isOrderedItem(t) else { break }
                    out += "<li>\(renderInline(stripOrderedPrefix(t)))</li>\n"
                    i += 1
                }
                out += "</ol>\n"; continue
            }

            // Table (GFM): header line + separator line
            if i + 1 < lines.count {
                let sepLine = lines[i + 1].trimmingCharacters(in: .whitespaces)
                if isTableSeparator(sepLine) && trimmed.contains("|") {
                    var tableLines: [String] = [line]
                    i += 2
                    while i < lines.count && lines[i].trimmingCharacters(in: .whitespaces).contains("|") {
                        tableLines.append(lines[i]); i += 1
                    }
                    out += renderTable(tableLines); continue
                }
            }

            // Paragraph
            var paraLines: [String] = []
            while i < lines.count {
                let t = lines[i].trimmingCharacters(in: .whitespaces)
                if t.isEmpty { break }
                if t.hasPrefix("```") || t.hasPrefix("~~~") { break }
                if parseATXHeading(t) != nil { break }
                if isHRule(t) { break }
                if t.hasPrefix(">") { break }
                if isUnorderedItem(t) { break }
                if isOrderedItem(t) { break }
                if i + 1 < lines.count {
                    let next = lines[i + 1].trimmingCharacters(in: .whitespaces)
                    if next.count >= 2 && (next.allSatisfy({ $0 == "=" }) || next.allSatisfy({ $0 == "-" })) { break }
                }
                // Hard break: two trailing spaces
                let raw = lines[i]
                if raw.hasSuffix("  ") {
                    paraLines.append(renderInline(raw.trimmingCharacters(in: .whitespaces)) + "<br>")
                } else {
                    paraLines.append(renderInline(t))
                }
                i += 1
            }
            if !paraLines.isEmpty {
                out += "<p>\(paraLines.joined(separator: "\n"))</p>\n"
            }
        }

        return out
    }

    // MARK: - Inline rendering

    func renderInline(_ input: String) -> String {
        // Sentinels from Unicode private-use area. Si el .md los trae, se reemplazan: si no,
        // un .md armado podría hacer que un fragmento se restaure dentro de un atributo
        let S: Character = "\u{E000}"
        let E: Character = "\u{E001}"
        var clean = String.UnicodeScalarView()
        for u in input.unicodeScalars { clean.append(u == "\u{E000}" || u == "\u{E001}" ? "\u{FFFD}" : u) }
        let input = String(clean)

        // Fragmentos ya armados (HTML seguro) que el texto referencia con un sentinel, y su
        // texto plano, para usarlo en un alt o un title
        var spans: [String] = []
        var plainText: [String] = []
        func hold(_ html: String, plain: String = "") -> String {
            spans.append(html)
            plainText.append(plain)
            return "\(S)\(spans.count - 1)\(E)"
        }
        func plain(_ s: String) -> String {
            sub(s, Self.sentinelPattern) { g in Int(g[1]).map { plainText[$0] } ?? "" }
        }
        func attr(_ s: String) -> String { HTMLSafety.escapeAttribute(s) }

        // Pass 1 – extract inline code spans with manual scan
        var scanned = ""
        var idx = input.startIndex
        while idx < input.endIndex {
            let ch = input[idx]
            if ch == "`" {
                let j = input.index(after: idx)
                if j < input.endIndex, let closeIdx = input[j...].firstIndex(of: "`") {
                    let code = String(input[j..<closeIdx])
                    scanned += hold("<code>\(HTMLSafety.escapeText(code))</code>", plain: code)
                    idx = input.index(after: closeIdx)
                    continue
                }
            }
            scanned.append(ch)
            idx = input.index(after: idx)
        }

        // Pass 2 – images and links, sobre el texto sin escapar: cada valor se escapa una
        // sola vez, al armar el atributo. Quedan como sentinels, así los patrones de énfasis
        // no tocan sus atributos (un _ en una URL ya no se vuelve <em>). Si el esquema es
        // peligroso, el Markdown queda como texto. Images before links.
        var text = sub(scanned, Self.imagePattern) { g in
            guard HTMLSafety.isSafeURL(g[2], allowDataImage: true) else { return g[0] }
            let title = g[3] + g[4]
            var tag = "<img src=\"\(attr(g[2]))\" alt=\"\(attr(plain(g[1])))\""
            if !title.isEmpty { tag += " title=\"\(attr(plain(title)))\"" }
            return hold(tag + ">", plain: plain(g[1]))
        }
        text = sub(text, Self.linkPattern) { g in
            guard HTMLSafety.isSafeURL(g[2]) else { return g[0] }
            let title = g[3] + g[4]
            var open = "<a href=\"\(attr(g[2]))\""
            if !title.isEmpty { open += " title=\"\(attr(plain(title)))\"" }
            // El texto del link sigue en el flujo: se escapa y le aplican los énfasis
            return hold(open + ">") + g[1] + hold("</a>")
        }

        // Pass 3 – HTML-escape (los sentinels son solo dígitos: no cambian)
        text = HTMLSafety.escapeText(text)

        // Pass 4 – emphasis (rebuild-based replace, no offset bugs)
        // Bold+italic before bold/italic
        text = sub(text, #"\*\*\*(.+?)\*\*\*"#) { "<strong><em>\($0[1])</em></strong>" }
        text = sub(text, #"___(.+?)___"#)         { "<strong><em>\($0[1])</em></strong>" }
        text = sub(text, #"\*\*(.+?)\*\*"#)       { "<strong>\($0[1])</strong>" }
        text = sub(text, #"__(.+?)__"#)           { "<strong>\($0[1])</strong>" }
        text = sub(text, #"(?<!\*)\*(?!\*)([^*\n]+?)(?<!\*)\*(?!\*)"#) { "<em>\($0[1])</em>" }
        text = sub(text, #"(?<!_)_(?!_)([^_\n]+?)(?<!_)_(?!_)"#)      { "<em>\($0[1])</em>" }
        text = sub(text, #"~~(.+?)~~"#)           { "<del>\($0[1])</del>" }

        // Pass 5 – restore spans, en una sola pasada (lo restaurado no se vuelve a mirar)
        return sub(text, Self.sentinelPattern) { g in Int(g[1]).map { spans[$0] } ?? "" }
    }

    private static let sentinelPattern = "\u{E000}([0-9]+)\u{E001}"
    // ![alt](src "title") y [texto](href 'title'). El destino no puede tener " ni ) ni un
    // sentinel (un code span no forma parte de una URL); el title va entre " o '
    private static let imagePattern =
        #"!\[([^\]]*)\]\(\s*([^\s)"\x{E000}][^)"\x{E000}]*?)(?:\s+(?:"([^"]*)"|'([^']*)'))?\s*\)"#
    private static let linkPattern =
        #"\[([^\]]+)\]\(\s*([^\s)"\x{E000}][^)"\x{E000}]*?)(?:\s+(?:"([^"]*)"|'([^']*)'))?\s*\)"#

    // MARK: - Table rendering

    private func renderTable(_ lines: [String]) -> String {
        guard lines.count >= 1 else { return "" }
        let headers = splitTableRow(lines[0])
        let dataRows = lines.dropFirst()

        var html = "<table>\n<thead>\n<tr>\n"
        for h in headers { html += "<th>\(renderInline(h))</th>\n" }
        html += "</tr>\n</thead>\n<tbody>\n"
        for row in dataRows {
            let cells = splitTableRow(row)
            html += "<tr>\n"
            for (i, _) in headers.enumerated() {
                let cell = i < cells.count ? cells[i] : ""
                html += "<td>\(renderInline(cell))</td>\n"
            }
            html += "</tr>\n"
        }
        html += "</tbody>\n</table>\n"
        return html
    }

    private func splitTableRow(_ line: String) -> [String] {
        var s = line.trimmingCharacters(in: .whitespaces)
        if s.hasPrefix("|") { s = String(s.dropFirst()) }
        if s.hasSuffix("|") { s = String(s.dropLast()) }
        return s.components(separatedBy: "|").map { $0.trimmingCharacters(in: .whitespaces) }
    }

    private func isTableSeparator(_ line: String) -> Bool {
        let clean = line.replacingOccurrences(of: " ", with: "")
        guard clean.contains("|") || clean.contains("-") else { return false }
        return clean.allSatisfy { $0 == "|" || $0 == "-" || $0 == ":" }
    }

    // MARK: - Task list

    private func renderTaskOrInline(_ text: String) -> String {
        if text.hasPrefix("[ ] ") {
            return "<input type=\"checkbox\" disabled> \(renderInline(String(text.dropFirst(4))))"
        }
        if text.lowercased().hasPrefix("[x] ") {
            return "<input type=\"checkbox\" checked disabled> \(renderInline(String(text.dropFirst(4))))"
        }
        return renderInline(text)
    }

    // MARK: - Helpers

    static func slugify(_ text: String) -> String {
        var slug = text.lowercased().replacingOccurrences(of: " ", with: "-")
        slug = String(slug.filter { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" })
        while slug.hasPrefix("-") { slug.removeFirst() }
        while slug.hasSuffix("-") { slug.removeLast() }
        return slug.isEmpty ? "heading" : slug
    }

    private func parseATXHeading(_ line: String) -> (level: Int, text: String)? {
        var level = 0
        for ch in line {
            if ch == "#" { level += 1 } else { break }
        }
        guard level >= 1, level <= 6 else { return nil }
        let rest = String(line.dropFirst(level))
        guard rest.hasPrefix(" ") || rest.isEmpty else { return nil }
        let text = rest.trimmingCharacters(in: .whitespaces)
        let stripped = sub(text, #"#+\s*$"#) { _ in "" }.trimmingCharacters(in: .whitespaces)
        return (level, stripped)
    }

    private func isHRule(_ line: String) -> Bool {
        let clean = line.filter { !$0.isWhitespace }
        guard clean.count >= 3 else { return false }
        return clean.allSatisfy { $0 == "-" } || clean.allSatisfy { $0 == "*" } || clean.allSatisfy { $0 == "_" }
    }

    private func isUnorderedItem(_ line: String) -> Bool {
        guard line.count >= 2 else { return false }
        let p = String(line.prefix(2))
        return p == "- " || p == "* " || p == "+ "
    }

    private func stripUnorderedPrefix(_ line: String) -> String {
        guard line.count >= 2 else { return line }
        return String(line.dropFirst(2))
    }

    private func isOrderedItem(_ line: String) -> Bool {
        guard let dotIdx = line.firstIndex(of: ".") else { return false }
        let prefix = line[line.startIndex..<dotIdx]
        guard !prefix.isEmpty, prefix.allSatisfy({ $0.isNumber }) else { return false }
        let after = line.index(after: dotIdx)
        return after < line.endIndex && line[after] == " "
    }

    private func stripOrderedPrefix(_ line: String) -> String {
        guard let dotIdx = line.firstIndex(of: ".") else { return line }
        let after = line.index(dotIdx, offsetBy: 2)
        guard after <= line.endIndex else { return line }
        return String(line[after...])
    }

    // Rebuild-based regex replace: no offset arithmetic, no bugs
    private func sub(_ input: String, _ pattern: String, _ replace: ([String]) -> String) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return input }
        let ns = input as NSString
        let len = ns.length
        var out = ""
        var cursor = input.startIndex

        for match in regex.matches(in: input, range: NSRange(location: 0, length: len)) {
            guard let matchRange = Range(match.range, in: input) else { continue }
            out += input[cursor..<matchRange.lowerBound]
            var groups: [String] = []
            for g in 0..<match.numberOfRanges {
                groups.append(Range(match.range(at: g), in: input).map { String(input[$0]) } ?? "")
            }
            out += replace(groups)
            cursor = matchRange.upperBound
        }
        out += input[cursor...]
        return out
    }
}
