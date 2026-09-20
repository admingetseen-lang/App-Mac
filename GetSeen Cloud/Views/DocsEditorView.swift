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
    @MainActor
    static func syncCookies(to webView: WKWebView) async {
        let store = webView.configuration.websiteDataStore.httpCookieStore
        let cookies = HTTPCookieStorage.shared.cookies ?? []
        for cookie in cookies {
            await store.setCookie(cookie)
            // App loggt über www.getseen.cloud ein; der Docs-Editor läuft auf der
            // kanonischen Domain getseen.cloud (ohne www). Cookie zusätzlich auf
            // ".getseen.cloud" setzen, damit es für BEIDE Hosts gilt.
            if cookie.domain.contains("getseen.cloud") && cookie.domain != ".getseen.cloud" {
                var props = cookie.properties ?? [:]
                props[.domain] = ".getseen.cloud"
                if let dup = HTTPCookie(properties: props) {
                    await store.setCookie(dup)
                }
            }
        }
    }
}

// MARK: - Navigation-Delegate mit Status- & Fehler-Erkennung
final class DocsWebCoordinator: NSObject, WKNavigationDelegate {
    weak var state: DocsWebState?
    private var lastStatus: Int = 200

    func webView(_ webView: WKWebView,
                 decidePolicyFor navigationResponse: WKNavigationResponse,
                 decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void) {
        if let http = navigationResponse.response as? HTTPURLResponse {
            lastStatus = http.statusCode
        }
        decisionHandler(.allow)
    }

    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        DispatchQueue.main.async {
            self.state?.isLoading = true
            self.state?.errorText = nil
        }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
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

        Task {
            await DocsWebHelper.syncCookies(to: webView)
            if let url = URL(string: urlString) {
                await MainActor.run { _ = webView.load(URLRequest(url: url)) }
            }
        }
        return webView
    }
}
