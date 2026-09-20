//
//  DocsEditorView.swift
//  GetSeen Cloud
//
//  Lädt den GetSeen-Docs-Editor in einer WKWebView.
//  Teilt Cookies mit der nativen URLSession (HTTPCookieStorage.shared) und
//  dupliziert sie auf ".getseen.cloud", damit die WebView auch dann angemeldet
//  ist, wenn die App über www.getseen.cloud eingeloggt wurde.
//

import SwiftUI
import WebKit

// MARK: - Beobachtbarer Zustand der WebView (Laden / Fehler / Reload)
final class DocsWebState: ObservableObject {
    @Published var isLoading: Bool = true
    @Published var errorText: String? = nil
    weak var webView: WKWebView?
    var pendingURL: URL? = nil

    func reload() {
        errorText = nil
        isLoading = true
        webView?.reload()
    }
}

struct DocsEditorWindow: View {
    let url: String
    var onClose: () -> Void

    @StateObject private var webState = DocsWebState()

    var body: some View {
        VStack(spacing: 0) {
            // Toolbar
            HStack {
                Button {
                    onClose()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "chevron.left")
                        Text("Zurück zum Dashboard")
                    }
                    .font(.system(size: 12, weight: .medium))
                }
                .buttonStyle(.plain)
                .foregroundColor(.secondary)

                Spacer()

                Text("docs.getseen.cloud")
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundColor(.secondary)

                Spacer()

                Button {
                    webState.reload()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.plain)
                .help("Neu laden")

                Button {
                    if let u = URL(string: url) { PlatformOpen.url(u) }
                } label: {
                    Image(systemName: "arrow.up.right.square")
                }
                .buttonStyle(.plain)
                .help("Im Browser öffnen")
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(Color.platformWindowBackground)

            Divider()

            // WebView + Lade-/Fehler-Overlays
            ZStack {
                DocsWebView(urlString: url, state: webState)

                if webState.isLoading && webState.errorText == nil {
                    VStack(spacing: 10) {
                        ProgressView()
                        Text("Editor wird geladen…")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                    }
                }

                if let err = webState.errorText {
                    VStack(spacing: 14) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 34))
                            .foregroundColor(.orange)
                        Text("Der Docs-Editor konnte nicht geladen werden")
                            .font(.system(size: 15, weight: .semibold))
                        Text(err)
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: 420)
                        HStack(spacing: 10) {
                            Button("Erneut laden") { webState.reload() }
                                .buttonStyle(.borderedProminent)
                            Button("Im Browser öffnen") {
                                if let u = URL(string: url) { PlatformOpen.url(u) }
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                    .padding(30)
                    .background(Color.platformWindowBackground)
                }
            }
            #if os(macOS)
            .frame(minWidth: 900, minHeight: 700)
            #endif
        }
        #if os(macOS)
        .frame(minWidth: 1000, idealWidth: 1200, minHeight: 800, idealHeight: 900)
        #else
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        #endif
    }
}

// MARK: - Cookie-Sync (inkl. Duplikat auf ".getseen.cloud")
enum DocsWebHelper {
    /// Alle relevanten Cookies (Original + Duplikat auf ".getseen.cloud")
    static func cookiesToSync() -> [HTTPCookie] {
        var out: [HTTPCookie] = []
        for cookie in HTTPCookieStorage.shared.cookies ?? [] {
            out.append(cookie)
            // App loggt über www.getseen.cloud ein; der Docs-Editor läuft auf der
            // kanonischen Domain getseen.cloud (ohne www). Cookie zusätzlich auf
            // ".getseen.cloud" setzen, damit es für BEIDE Hosts gilt.
            if cookie.domain.contains("getseen.cloud") && cookie.domain != ".getseen.cloud" {
                var props = cookie.properties ?? [:]
                props[.domain] = ".getseen.cloud"
                if let dup = HTTPCookie(properties: props) { out.append(dup) }
            }
        }
        return out
    }

    @MainActor
    static func syncCookies(to webView: WKWebView) async {
        let store = webView.configuration.websiteDataStore.httpCookieStore
        for cookie in cookiesToSync() {
            await store.setCookie(cookie)
        }
    }

    /// Cookie-Sync mit Zeitlimit. Auf iOS kann WKHTTPCookieStore beim allerersten
    /// Start (Web-Content-Prozess noch nicht da) hängen – dann darf das Laden
    /// des Editors nicht ewig blockieren.
    @MainActor
    static func syncCookies(to webView: WKWebView, timeout seconds: Double) async {
        // Echtes Rennen: wer zuerst fertig ist (Sync oder Timer) lässt uns weiter.
        // (Eine TaskGroup würde am Ende auf ALLE Kinder warten – und setCookie
        // ruft auf iOS beim ersten Mal u. U. nie zurück.)
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            let once = OnceResumer(cont)
            Task { @MainActor in
                await syncCookies(to: webView)
                once.resume()
            }
            Task {
                try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                once.resume()
            }
        }
    }

    /// Hilfsklasse: Continuation garantiert nur einmal fortsetzen.
    final class OnceResumer: @unchecked Sendable {
        private var cont: CheckedContinuation<Void, Never>?
        private let lock = NSLock()
        init(_ c: CheckedContinuation<Void, Never>) { cont = c }
        func resume() {
            lock.lock(); let c = cont; cont = nil; lock.unlock()
            c?.resume()
        }
    }

    /// Cookie-Header für den initialen Request (Fallback, falls der Store noch
    /// nicht bereit war): so ist die Sitzung schon beim ersten Aufruf bekannt.
    static func cookieHeader(for url: URL) -> String? {
        let host = url.host ?? ""
        let matching = (HTTPCookieStorage.shared.cookies ?? []).filter { c in
            let d = c.domain.hasPrefix(".") ? String(c.domain.dropFirst()) : c.domain
            return host == d || host.hasSuffix("." + d) || d.hasSuffix(host)
        }
        guard !matching.isEmpty else { return nil }
        return matching.map { "\($0.name)=\($0.value)" }.joined(separator: "; ")
    }
}

// MARK: - Navigation-Delegate mit Status- & Fehler-Erkennung
final class DocsWebCoordinator: NSObject, WKNavigationDelegate {
    weak var state: DocsWebState?
    private var lastStatus: Int = 200
    /// true, sobald die Seite tatsächlich Inhalt empfangen hat
    private(set) var didCommit = false
    private var retried = false
    /// true während der about:blank-Aufwärmnavigation (wird ignoriert)
    var warmingUp = false

    /// Watchdog: Hängt die Navigation nach `seconds` noch ohne Inhalt, einmal neu laden.
    func armWatchdog(_ webView: WKWebView, seconds: Double) {
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { [weak self, weak webView] in
            guard let self, let webView, !self.retried else { return }
            let stillLoading = self.state?.isLoading ?? false
            guard !self.didCommit || stillLoading else { return }
            self.retried = true
            print("📄 docs watchdog: kein Inhalt nach \(seconds)s – lade neu")
            if let url = webView.url ?? self.state?.pendingURL {
                var req = URLRequest(url: url)
                if let h = DocsWebHelper.cookieHeader(for: url) { req.setValue(h, forHTTPHeaderField: "Cookie") }
                webView.load(req)
            } else {
                webView.reload()
            }
        }
    }

    func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
        if warmingUp { return }
        didCommit = true
    }

    /// WebKit hat den Inhaltsprozess verloren (passiert auf iOS gern beim
    /// allerersten Start der WebView) – dann bleibt die Seite leer und
    /// didFinish kommt nie. Einmal automatisch neu laden.
    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        print("📄 docs: WebContent-Prozess beendet – lade neu")
        didCommit = false
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self, weak webView] in
            guard let webView else { return }
            self?.state?.isLoading = true
            if let url = self?.state?.pendingURL ?? webView.url {
                var req = URLRequest(url: url)
                if let h = DocsWebHelper.cookieHeader(for: url) { req.setValue(h, forHTTPHeaderField: "Cookie") }
                webView.load(req)
            } else {
                webView.reload()
            }
            // Watchdog erneut scharf schalten, falls auch der zweite Versuch hängt
            self?.retried = false
            self?.armWatchdog(webView, seconds: 12)
        }
    }

    func webView(_ webView: WKWebView,
                 decidePolicyFor navigationResponse: WKNavigationResponse,
                 decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void) {
        if let http = navigationResponse.response as? HTTPURLResponse {
            lastStatus = http.statusCode
        }
        decisionHandler(.allow)
    }

    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        if warmingUp { return }
        DispatchQueue.main.async {
            self.state?.isLoading = true
            self.state?.errorText = nil
        }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        // Aufwärm-Navigation (about:blank) nie als "fertig" werten
        if warmingUp || webView.url?.absoluteString == "about:blank" { return }
        // Cookies aus der WebView zurück in die App übernehmen
        webView.configuration.websiteDataStore.httpCookieStore.getAllCookies { cookies in
            for cookie in cookies {
                // Die künstlich auf ".getseen.cloud" duplizierten Cookies NICHT in
                // den App-Speicher zurückschreiben – sonst sendet die App jedes
                // Cookie doppelt (führte zu Timeouts). Nur echte Host-Cookies.
                if cookie.domain == ".getseen.cloud" { continue }
                HTTPCookieStorage.shared.setCookie(cookie)
            }
        }
        let status = lastStatus
        let finalURL = webView.url?.absoluteString ?? ""
        print("📄 docs didFinish status=\(status) url=\(finalURL)")
        DispatchQueue.main.async {
            self.state?.isLoading = false
            if status >= 400 {
                self.state?.errorText = "Der Server hat mit HTTP \(status) geantwortet."
            }
        }
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        handleFailure(error)
    }
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        handleFailure(error)
    }
    private func handleFailure(_ error: Error) {
        if warmingUp { return }
        let ns = error as NSError
        // Abgebrochene Navigationen (z. B. Redirect) ignorieren
        if ns.code == NSURLErrorCancelled { return }
        print("📄 docs FAIL \(ns.domain) \(ns.code): \(ns.localizedDescription)")
        DispatchQueue.main.async {
            self.state?.isLoading = false
            self.state?.errorText = ns.localizedDescription
        }
    }
}

// MARK: - Plattform-Wrapper
#if os(macOS)
struct DocsWebView: NSViewRepresentable {
    let urlString: String
    @ObservedObject var state: DocsWebState
    func makeCoordinator() -> DocsWebCoordinator {
        let c = DocsWebCoordinator(); c.state = state; return c
    }
    func makeNSView(context: Context) -> WKWebView {
        let wv = Self.build(urlString, context.coordinator)
        state.webView = wv
        return wv
    }
    func updateNSView(_ nsView: WKWebView, context: Context) { }
}
#else
struct DocsWebView: UIViewRepresentable {
    let urlString: String
    @ObservedObject var state: DocsWebState
    func makeCoordinator() -> DocsWebCoordinator {
        let c = DocsWebCoordinator(); c.state = state; return c
    }
    func makeUIView(context: Context) -> WKWebView {
        let wv = Self.build(urlString, context.coordinator)
        state.webView = wv
        return wv
    }
    func updateUIView(_ uiView: WKWebView, context: Context) { }
}
#endif

extension DocsWebView {
    static func build(_ urlString: String, _ coordinator: DocsWebCoordinator) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = WKWebsiteDataStore.default()
        config.preferences.javaScriptCanOpenWindowsAutomatically = true

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = coordinator
        webView.allowsBackForwardNavigationGestures = true
        // WICHTIG: undurchsichtiger Hintergrund, damit eine noch ladende Seite
        // nicht den grauen Fensterhintergrund durchscheinen lässt.
        #if os(iOS)
        webView.isOpaque = true
        #endif

        Task { @MainActor in
            // 1) Web-Prozess starten: ohne laufenden Prozess ruft
            //    WKHTTPCookieStore.setCookie auf iOS beim ersten Mal nie zurück.
            coordinator.warmingUp = true
            webView.load(URLRequest(url: URL(string: "about:blank")!))
            try? await Task.sleep(nanoseconds: 400_000_000)
            // 2) Cookies syncen – mit echtem Zeitlimit
            print("📄 docs cookie-sync start")
            await DocsWebHelper.syncCookies(to: webView, timeout: 3)
            print("📄 docs cookie-sync done")
            coordinator.warmingUp = false
            // 3) Editor laden (Session zusätzlich als Cookie-Header)
            guard let url = URL(string: urlString), !urlString.isEmpty else {
                print("📄 docs FEHLER: ungültige URL '\(urlString)'")
                return
            }
            coordinator.state?.pendingURL = url
            var req = URLRequest(url: url)
            if let h = DocsWebHelper.cookieHeader(for: url) {
                req.setValue(h, forHTTPHeaderField: "Cookie")
            }
            print("📄 docs load \(url.absoluteString)")
            _ = webView.load(req)
            coordinator.armWatchdog(webView, seconds: 12)
        }
        return webView
    }
}
