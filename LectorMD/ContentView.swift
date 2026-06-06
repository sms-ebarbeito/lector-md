import SwiftUI
import AppKit
import WebKit

// MARK: - Search model

final class SearchModel: ObservableObject {
    @Published var isVisible = false
    @Published var query = ""
    @Published var matchCount: Int? = nil
    @Published var currentMatch: Int = 0
    @Published var headings: [Heading] = []

    weak var webView: WKWebView?

    var matchDisplay: String? {
        guard let count = matchCount else { return nil }
        if count == 0 { return "Sin resultados" }
        return "\(currentMatch) / \(count)"
    }

    struct Heading: Identifiable {
        let id: String
        let level: Int
        let text: String
    }

    func toggle() {
        isVisible.toggle()
        if !isVisible { clear() }
    }

    func performSearch() {
        guard let webView else { return }
        guard !query.isEmpty else { clear(); return }
        let escaped = query
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        webView.evaluateJavaScript("lectorSearch(\"\(escaped)\")") { [weak self] result, _ in
            DispatchQueue.main.async {
                let count = result as? Int ?? 0
                self?.matchCount = count
                self?.currentMatch = count > 0 ? 1 : 0
            }
        }
    }

    func next() {
        webView?.evaluateJavaScript("lectorSearchNext()") { [weak self] result, _ in
            DispatchQueue.main.async { self?.applyNavResult(result) }
        }
    }

    func prev() {
        webView?.evaluateJavaScript("lectorSearchPrev()") { [weak self] result, _ in
            DispatchQueue.main.async { self?.applyNavResult(result) }
        }
    }

    private func applyNavResult(_ result: Any?) {
        guard let arr = result as? [Any], arr.count == 2,
              let cur = arr[0] as? Int, let total = arr[1] as? Int else { return }
        currentMatch = cur
        matchCount = total
    }

    func navigateTo(_ headingId: String) {
        guard let webView else { return }
        let safe = headingId.replacingOccurrences(of: "\"", with: "\\\"")
        webView.evaluateJavaScript(
            "document.getElementById(\"\(safe)\")?.scrollIntoView({behavior:'smooth',block:'start'})",
            completionHandler: nil
        )
    }

    func loadHeadings(from markdown: String) {
        var result: [Heading] = []
        let lines = markdown.components(separatedBy: .newlines)
        var i = 0
        while i < lines.count {
            let trimmed = lines[i].trimmingCharacters(in: .whitespaces)
            // ATX heading
            if trimmed.hasPrefix("#") {
                var level = 0
                for ch in trimmed { if ch == "#" { level += 1 } else { break } }
                if level >= 1, level <= 6 {
                    let rest = String(trimmed.dropFirst(level))
                    if rest.hasPrefix(" ") || rest.isEmpty {
                        let text = rest.trimmingCharacters(in: .whitespaces)
                        if !text.isEmpty {
                            result.append(Heading(id: MarkdownRenderer.slugify(text), level: level, text: text))
                        }
                    }
                }
                i += 1; continue
            }
            // Setext heading
            if !trimmed.isEmpty, i + 1 < lines.count {
                let next = lines[i + 1].trimmingCharacters(in: .whitespaces)
                if next.count >= 2 && next.allSatisfy({ $0 == "=" }) {
                    result.append(Heading(id: MarkdownRenderer.slugify(trimmed), level: 1, text: trimmed))
                    i += 2; continue
                }
                let isHRule = { (s: String) -> Bool in
                    let c = s.filter { !$0.isWhitespace }
                    return c.count >= 3 && (c.allSatisfy { $0 == "-" } || c.allSatisfy { $0 == "*" } || c.allSatisfy { $0 == "_" })
                }
                if next.count >= 2 && next.allSatisfy({ $0 == "-" }) && !isHRule(trimmed) {
                    result.append(Heading(id: MarkdownRenderer.slugify(trimmed), level: 2, text: trimmed))
                    i += 2; continue
                }
            }
            i += 1
        }
        headings = result
    }

    func clear() {
        query = ""
        matchCount = nil
        currentMatch = 0
        webView?.evaluateJavaScript("lectorSearch('')", completionHandler: nil)
    }

    func clearHighlights() {
        matchCount = nil
        currentMatch = 0
        webView?.evaluateJavaScript("lectorSearch('')", completionHandler: nil)
    }

    func printDocument() {
        guard let webView else { return }
        
        let printInfo = NSPrintInfo()
        printInfo.horizontalPagination = .fit
        printInfo.isVerticallyCentered = false
        printInfo.topMargin = 40
        printInfo.bottomMargin = 40
        printInfo.leftMargin = 40
        printInfo.rightMargin = 40
        printInfo.dictionary().setObject(NSNumber(value: true), forKey: NSPrintInfo.AttributeKey.headerAndFooter as NSString)
        
        let printOp = webView.printOperation(with: printInfo)
        printOp.canSpawnSeparateThread = true
        printOp.showsPrintPanel = true
        
        // Ejecutar en la ventana principal para que sea modal si es posible, 
        // o simplemente correrlo.
        if let window = webView.window {
            printOp.runModal(for: window, delegate: nil, didRun: nil, contextInfo: nil)
        } else {
            printOp.run()
        }
    }
}

// MARK: - Search panel

struct SearchPanel: View {
    @ObservedObject var model: SearchModel
    @FocusState private var searchFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            searchBar
            if !model.headings.isEmpty {
                Divider()
                headingList
            }
        }
        .frame(width: 272)
        .frame(maxHeight: 480)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
        .shadow(color: .black.opacity(0.22), radius: 12, x: -2, y: 4)
        .onAppear {
            // Esperamos a que termine la animación de entrada antes de robar el foco al WebView
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                searchFocused = true
            }
        }
    }

    private var searchBar: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                Button { model.performSearch() } label: {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                        .font(.system(size: 15))
                }
                .buttonStyle(.plain)
                .padding(.leading, 10)
                .padding(.trailing, 6)
                .help("Buscar")

                TextField("Buscar en el documento", text: $model.query)
                    .textFieldStyle(.plain)
                    .font(.system(size: 14))
                    .focused($searchFocused)
                    .onSubmit {
                        if let count = model.matchCount, count > 0 { model.next() }
                        else { model.performSearch() }
                    }
                    .onChange(of: model.query) { newValue in
                        if newValue.count >= 3 { model.performSearch() }
                        else { model.clearHighlights() }
                    }

                if let display = model.matchDisplay {
                    Text(display)
                        .font(.system(size: 11))
                        .foregroundStyle(model.matchCount == 0 ? Color.red.opacity(0.8) : Color.secondary)
                        .padding(.leading, 4)
                        .fixedSize()
                }

                if let count = model.matchCount, count > 0 {
                    HStack(spacing: 4) {
                        Button { model.prev() } label: {
                            Image(systemName: "chevron.up")
                                .font(.system(size: 12, weight: .semibold))
                                .frame(width: 28, height: 24)
                                .background(.quaternary, in: RoundedRectangle(cornerRadius: 5))
                        }
                        .buttonStyle(.plain)
                        .help("Anterior")

                        Button { model.next() } label: {
                            Image(systemName: "chevron.down")
                                .font(.system(size: 12, weight: .semibold))
                                .frame(width: 28, height: 24)
                                .background(.quaternary, in: RoundedRectangle(cornerRadius: 5))
                        }
                        .buttonStyle(.plain)
                        .help("Siguiente")
                    }
                    .foregroundStyle(.secondary)
                    .padding(.leading, 6)
                }

                Button { model.isVisible = false; model.clear() } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.tertiary)
                        .font(.system(size: 16))
                }
                .buttonStyle(.plain)
                .padding(.leading, 8)
                .padding(.trailing, 10)
                .help("Cerrar (Esc)")

                // Escape key handler
                Button("") { model.isVisible = false; model.clear() }
                    .keyboardShortcut(.escape, modifiers: [])
                    .hidden()
            }
            .padding(.vertical, 8)
        }
    }

    private var headingList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(model.headings) { heading in
                    Button { model.navigateTo(heading.id) } label: {
                        HStack(spacing: 4) {
                            if heading.level > 1 {
                                Spacer().frame(width: CGFloat((heading.level - 1) * 10))
                            }
                            Image(systemName: "number")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(.tertiary)
                            Text(heading.text)
                                .font(.system(size: heading.level == 1 ? 13 : 12))
                                .fontWeight(heading.level <= 2 ? .medium : .regular)
                                .foregroundStyle(heading.level == 1 ? Color.primary : Color.secondary)
                                .lineLimit(1)
                                .truncationMode(.tail)
                            Spacer()
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, 4)
        }
    }
}

// MARK: - FocusedValues

extension FocusedValues {
    struct ReloadActionKey: FocusedValueKey {
        typealias Value = () -> Void
    }
    struct PrintActionKey: FocusedValueKey {
        typealias Value = () -> Void
    }
    var reloadAction: (() -> Void)? {
        get { self[ReloadActionKey.self] }
        set { self[ReloadActionKey.self] = newValue }
    }
    var printAction: (() -> Void)? {
        get { self[PrintActionKey.self] }
        set { self[PrintActionKey.self] = newValue }
    }
}

// MARK: - Content view

struct ContentView: View {
    let document: MarkdownDocument
    let fileURL: URL?
    @State private var currentText: String
    @StateObject private var searchModel = SearchModel()
    @AppStorage("appearanceMode") private var appearanceMode: String = "system"

    init(document: MarkdownDocument, fileURL: URL?) {
        self.document = document
        self.fileURL = fileURL
        _currentText = State(initialValue: document.text)
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            MarkdownWebView(markdownText: currentText, searchModel: searchModel, appearanceMode: appearanceMode)
                .frame(minWidth: 560, minHeight: 400)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(WindowFrameSaver())
                .onAppear { searchModel.loadHeadings(from: currentText) }

            if searchModel.isVisible {
                SearchPanel(model: searchModel)
                    .padding(.top, 10)
                    .padding(.trailing, 14)
                    .transition(.asymmetric(
                        insertion: .move(edge: .trailing).combined(with: .opacity),
                        removal: .move(edge: .trailing).combined(with: .opacity)
                    ))
            }
        }
        .animation(.easeInOut(duration: 0.18), value: searchModel.isVisible)
        .background(
            Button("") { searchModel.toggle() }
                .keyboardShortcut("f", modifiers: .command)
                .hidden()
        )
        .focusedValue(\.reloadAction, reload)
        .focusedValue(\.printAction, searchModel.printDocument)
    }

    private func reload() {
        guard let fileURL,
              let text = try? String(contentsOf: fileURL, encoding: .utf8) else { return }
        currentText = text
        searchModel.loadHeadings(from: text)
    }
}

// MARK: - Window frame saver

private struct WindowFrameSaver: NSViewRepresentable {
    func makeNSView(context: Context) -> FrameSetterView { FrameSetterView() }
    func updateNSView(_ nsView: FrameSetterView, context: Context) {}
}

// NSView subclass para capturar viewDidMoveToWindow(), que se dispara cuando
// la view ya está conectada al window — a diferencia de makeNSView donde
// view.window aún puede ser nil y el guard falla silenciosamente.
final class FrameSetterView: NSView {
    private var applied = false

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard let window, !applied else { return }
        applied = true

        // Primer intento: sincrono, antes de que la ventana sea visible.
        applyDefaultFrame(to: window)

        // Segundo intento via didBecomeKeyNotification: corre DESPUÉS de que
        // SwiftUI termina su layout inicial, corrigiendo cualquier override posterior.
        var obs: NSObjectProtocol?
        obs = NotificationCenter.default.addObserver(
            forName: NSWindow.didBecomeKeyNotification,
            object: window,
            queue: .main
        ) { [weak window] _ in
            if let o = obs { NotificationCenter.default.removeObserver(o) }
            obs = nil
            guard let window else { return }
            self.applyDefaultFrame(to: window)
        }
    }

    private func applyDefaultFrame(to window: NSWindow) {
        let screenHeight = (window.screen ?? NSScreen.main)?.frame.height ?? 734
        window.setFrame(NSRect(x: 0, y: 0, width: 860, height: screenHeight * 0.9), display: false)
        window.center()
    }
}
