import Foundation

// Escape y validaciones para lo que viene del .md (#5). El renderer mete todo texto con
// `escapeText` y todo valor de atributo con `escapeAttribute`, siempre entre comillas
// dobles; los href y src pasan además por `isSafeURL`.
//
// Se recorren unicode scalars y no Characters: una comilla seguida de un acento
// combinante (U+0301) es un solo Character, distinto de "\"", y no se escaparía; pero
// para el parser de HTML sigue siendo una comilla que cierra el atributo.
enum HTMLSafety {

    /// Texto entre etiquetas: & < >
    static func escapeText(_ text: String) -> String {
        escape(text, quotes: false)
    }

    /// Valor de un atributo: & < > " '
    static func escapeAttribute(_ value: String) -> String {
        escape(value, quotes: true)
    }

    private static func escape(_ text: String, quotes: Bool) -> String {
        var out = String.UnicodeScalarView()
        for u in text.unicodeScalars {
            switch u {
            case "&":             out.append(contentsOf: "&amp;".unicodeScalars)
            case "<":             out.append(contentsOf: "&lt;".unicodeScalars)
            case ">":             out.append(contentsOf: "&gt;".unicodeScalars)
            case "\"" where quotes: out.append(contentsOf: "&quot;".unicodeScalars)
            case "'" where quotes:  out.append(contentsOf: "&#39;".unicodeScalars)
            default:              out.append(u)
            }
        }
        return String(out)
    }

    // MARK: - URLs

    /// false si el esquema puede ejecutar código: javascript:, vbscript: y data: (salvo
    /// data:image/… en una imagen). Las relativas y las #anclas pasan.
    static func isSafeURL(_ url: String, allowDataImage: Bool = false) -> Bool {
        // El navegador ignora espacios y controles al principio, y tabs y saltos de línea
        // en el medio ("java\tscript:" es javascript:). Acá se sacan en todos lados: más
        // estricto que el navegador, nunca menos.
        let cleaned = String(String.UnicodeScalarView(
            url.unicodeScalars.filter { $0.value > 0x20 && $0.value != 0x7F }))
        guard let colon = cleaned.unicodeScalars.firstIndex(of: ":") else { return true }
        // Esquema válido: una letra ASCII y después letras, dígitos, + - . Si no, el
        // navegador la toma como relativa
        let scheme = cleaned.unicodeScalars[..<colon]
        guard let first = scheme.first, isASCIILetter(first),
              scheme.allSatisfy({ isASCIILetter($0) || ("0"..."9").contains($0) || "+-.".unicodeScalars.contains($0) })
        else { return true }
        switch String(String.UnicodeScalarView(scheme)).lowercased() {
        case "javascript", "vbscript": return false
        case "data": return allowDataImage && cleaned.lowercased().hasPrefix("data:image/")
        default: return true
        }
    }

    private static func isASCIILetter(_ u: Unicode.Scalar) -> Bool {
        ("a"..."z").contains(u) || ("A"..."Z").contains(u)
    }

    // MARK: - SVG del puente diagramClick

    static let maxDiagramSVGBytes = 5_000_000

    // Nada de esto aparece en un diagrama de Mermaid, y puede ejecutar código, cargar
    // otra página o cambiar cómo se parsea lo que sigue (<! y <? son comentarios, CDATA,
    // etc.). Se busca en todo el string, sin importar si cae dentro de un atributo: así
    // no hay forma de esconderlo.
    private static let forbiddenTagPattern = try! NSRegularExpression(
        pattern: #"<(?:script|iframe|frame|frameset|object|embed|applet|portal|meta|base|link|form|"#
            + #"template|set|animate|handler|textarea|xmp|noscript|noembed|noframes|plaintext)[\s/>]|<[!?]"#,
        options: [.caseInsensitive])

    // Un on…= en cualquier cosa que parezca una etiqueta, aunque esté "dentro" de otro
    // atributo: si el parser del navegador lo ve distinto que el escaneo de abajo, lo
    // agarra esto
    private static let handlerPattern = try! NSRegularExpression(
        pattern: #"<[a-z][^<>]*[\s/"']on[a-z]+\s*="#, options: [.caseInsensitive])

    private static let urlAttributes: Set<String> = ["href", "src", "action", "formaction"]

    /// El puente solo acepta un <svg> razonable: hasta 5 MB, sin <script> ni otras
    /// etiquetas que ejecuten o carguen algo, sin atributos on* y sin URLs peligrosas.
    /// Es una capa extra, no un parser de HTML: lo que asegura que nada se ejecute en la
    /// ventana del diagrama es su CSP (`HTMLTemplate.diagramPage`).
    static func isSafeDiagramSVG(_ svg: String) -> Bool {
        let bytes = Array(svg.utf8)
        guard bytes.count <= maxDiagramSVGBytes else { return false }
        let lower = svg.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard lower.hasPrefix("<svg"), lower.hasSuffix("</svg>"),
              let afterName = lower.unicodeScalars.dropFirst(4).first,
              afterName == ">" || afterName == "/" || isHTMLSpace(afterName)
        else { return false }
        let all = NSRange(svg.startIndex..., in: svg)
        if forbiddenTagPattern.firstMatch(in: svg, range: all) != nil { return false }
        if handlerPattern.firstMatch(in: svg, range: all) != nil { return false }
        return attributesAreSafe(bytes)
    }

    // Recorre las etiquetas respetando comillas, como el tokenizer de HTML, y mira cada
    // atributo: ningún on*, y los href/src con un esquema seguro
    private static func attributesAreSafe(_ b: [UInt8]) -> Bool {
        let lt = UInt8(ascii: "<"), gt = UInt8(ascii: ">"), slash = UInt8(ascii: "/"), eq = UInt8(ascii: "=")
        let dq = UInt8(ascii: "\""), sq = UInt8(ascii: "'")
        func isSpace(_ c: UInt8) -> Bool { c == 0x20 || c == 0x09 || c == 0x0A || c == 0x0C || c == 0x0D }
        func isLetter(_ c: UInt8) -> Bool { (c | 0x20) >= 0x61 && (c | 0x20) <= 0x7A }
        func text(_ r: Range<Int>) -> String { String(decoding: b[r], as: UTF8.self) }

        var i = 0
        let n = b.count
        while i < n {
            guard b[i] == lt else { i += 1; continue }
            i += 1
            var isEndTag = false
            if i < n, b[i] == slash {
                isEndTag = true
                i += 1
                // "</" y algo que no es letra: el tokenizer lo toma como comentario hasta el ">"
                guard i < n, isLetter(b[i]) else { return false }
            }
            guard i < n, isLetter(b[i]) else { continue }   // un "<" suelto es texto
            let tagStart = i
            while i < n, !isSpace(b[i]), b[i] != slash, b[i] != gt { i += 1 }
            let tag = text(tagStart..<i).lowercased()
            while true {
                while i < n, isSpace(b[i]) || b[i] == slash { i += 1 }
                guard i < n else { return false }            // etiqueta sin cerrar
                if b[i] == gt { i += 1; break }
                let nameStart = i
                i += 1                                       // puede empezar con "="
                while i < n, !isSpace(b[i]), b[i] != slash, b[i] != gt, b[i] != eq { i += 1 }
                let name = text(nameStart..<i).lowercased()
                while i < n, isSpace(b[i]) { i += 1 }
                var value = ""
                if i < n, b[i] == eq {
                    i += 1
                    while i < n, isSpace(b[i]) { i += 1 }
                    guard i < n else { return false }
                    if b[i] == dq || b[i] == sq {
                        let quote = b[i]
                        i += 1
                        let start = i
                        while i < n, b[i] != quote { i += 1 }
                        guard i < n else { return false }
                        value = text(start..<i)
                        i += 1
                    } else {
                        let start = i
                        while i < n, !isSpace(b[i]), b[i] != gt { i += 1 }
                        value = text(start..<i)
                    }
                }
                if name.hasPrefix("on") { return false }
                if urlAttributes.contains(name) || name.hasSuffix(":href") {
                    // Mermaid solo escapa & en una URL (&amp;). Cualquier otra referencia
                    // (&#106;avascript:, &colon;…) se rechaza en vez de decodificarla
                    if value.replacingOccurrences(of: "&amp;", with: "").contains("&") { return false }
                    if !isSafeURL(value.replacingOccurrences(of: "&amp;", with: "&"), allowDataImage: true) { return false }
                }
            }
            // <style> y <title> son texto crudo si el navegador los lee como HTML (p. ej.
            // dentro de un foreignObject) y no lo son en SVG. Si su contenido no tiene "<",
            // se lee igual de las dos formas: el primer "<" tiene que ser su cierre
            if !isEndTag, tag == "style" || tag == "title" {
                let close = Array("</\(tag)".utf8)
                guard let at = b[i...].firstIndex(of: lt), at + close.count < n,
                      zip(b[at..<at + close.count], close).allSatisfy({ ($0 | 0x20) == $1 }),
                      isSpace(b[at + close.count]) || b[at + close.count] == slash || b[at + close.count] == gt
                else { return false }
                i = at
            }
        }
        return true
    }

    private static func isHTMLSpace(_ u: Unicode.Scalar) -> Bool {
        u == " " || u == "\t" || u == "\n" || u == "\u{0C}" || u == "\r"
    }
}
