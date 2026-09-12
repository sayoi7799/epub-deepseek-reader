import SwiftUI
import WebKit

struct ReaderWebView: UIViewRepresentable {
    let html: String
    let reloadToken: UUID
    let fontSize: Double
    let lineHeight: Double
    let controller: ReaderWebController
    let onMessage: (ReaderMessage) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onMessage: onMessage)
    }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        configuration.userContentController.add(context.coordinator, name: "reader")

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.backgroundColor = .clear
        webView.allowsLinkPreview = false
        webView.allowsBackForwardNavigationGestures = false
        if #available(iOS 16.4, *) {
            webView.isInspectable = true
        }

        context.coordinator.webView = webView
        context.coordinator.loadedToken = reloadToken
        context.coordinator.appliedFontSize = fontSize
        context.coordinator.appliedLineHeight = lineHeight
        controller.webView = webView

        if !html.isEmpty {
            webView.loadHTMLString(html, baseURL: nil)
        }
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        context.coordinator.onMessage = onMessage
        controller.webView = webView

        if context.coordinator.loadedToken != reloadToken {
            context.coordinator.loadedToken = reloadToken
            webView.loadHTMLString(html, baseURL: nil)
            return
        }

        if context.coordinator.appliedFontSize != fontSize {
            context.coordinator.appliedFontSize = fontSize
            controller.setFontSize(fontSize)
        }
        if context.coordinator.appliedLineHeight != lineHeight {
            context.coordinator.appliedLineHeight = lineHeight
            controller.setLineHeight(lineHeight)
        }
    }

    static func dismantleUIView(_ webView: WKWebView, coordinator: Coordinator) {
        webView.stopLoading()
        webView.navigationDelegate = nil
        webView.configuration.userContentController.removeScriptMessageHandler(forName: "reader")
    }

    final class Coordinator: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
        var onMessage: (ReaderMessage) -> Void
        weak var webView: WKWebView?
        var loadedToken: UUID?
        var appliedFontSize: Double = 0
        var appliedLineHeight: Double = 0

        init(onMessage: @escaping (ReaderMessage) -> Void) {
            self.onMessage = onMessage
        }

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            guard let payload = message.body as? [String: Any] else { return }
            guard let decoded = ReaderMessage(payload: payload) else { return }
            onMessage(decoded)
        }

        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
        ) {
            if navigationAction.navigationType == .linkActivated {
                decisionHandler(.cancel)
                return
            }
            decisionHandler(.allow)
        }
    }
}
