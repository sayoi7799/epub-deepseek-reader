import Foundation
import WebKit

/// 让 ViewModel 能直接操作 WKWebView（插入译文、改字号等）。
@MainActor
final class ReaderWebController {
    weak var webView: WKWebView?

    func insertTranslation(anchorID: String, text: String) {
        call("insertTranslation", [anchorID, text])
    }

    func removeTranslation(anchorID: String) {
        call("removeTranslation", [anchorID])
    }

    func setFontSize(_ size: Double) {
        call("setFontSize", [size])
    }

    func setLineHeight(_ value: Double) {
        call("setLineHeight", [value])
    }

    func scrollToTop() {
        call("scrollToTop", [])
    }

    private func call(_ function: String, _ arguments: [Any]) {
        guard let webView = self.webView else { return }
        guard
            let data = try? JSONSerialization.data(withJSONObject: arguments),
            let json = String(data: data, encoding: .utf8)
        else { return }
        let script = """
        (function () {
          try {
            if (!window.__reader) { return false; }
            return !!(window.__reader.\(function).apply(null, \(json)));
          } catch (error) {
            return false;
          }
        })();
        """
        Task {
            _ = try? await webView.evaluateJavaScript(script)
        }
    }
}
