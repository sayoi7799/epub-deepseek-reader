import Foundation

/// 把 EPUB 章节的 XHTML 变成 WKWebView 可以直接显示的 HTML，
/// 同时注入阅读样式和与原生通信的 JavaScript。
enum HTMLDocumentBuilder {
    static func build(
        sourceHTML: String,
        chapterPath: String,
        contentRoot: URL,
        appearance: ReaderAppearance,
        initialProgress: Double
    ) -> String {
        let body = extractBody(from: sourceHTML)
        let cleaned = stripUnsafeMarkup(body)
        let withImages = inlineImages(in: cleaned, chapterPath: chapterPath, contentRoot: contentRoot)

        let css = styleSheet(appearance: appearance)
        let script = script(appearance: appearance, initialProgress: initialProgress)

        return """
        <!DOCTYPE html>
        <html lang="zh">
        <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no, viewport-fit=cover">
        <style>\(css)</style>
        </head>
        <body>
        <div id="reader-root">\(withImages)</div>
        <script>\(script)</script>
        </body>
        </html>
        """
    }

    // MARK: - 清理

    private static func extractBody(from html: String) -> String {
        if let range = html.range(of: "(?is)<body[^>]*>(.*?)</body>", options: .regularExpression) {
            let matched = String(html[range])
            if let open = matched.range(of: ">", options: .literal),
               let close = matched.range(of: "</body>", options: [.caseInsensitive, .backwards]) {
                return String(matched[open.upperBound..<close.lowerBound])
            }
        }
        var result = html
        if let headRange = result.range(of: "(?is)<head[^>]*>.*?</head>", options: .regularExpression) {
            result.removeSubrange(headRange)
        }
        result = result.replacingOccurrences(
            of: "(?is)<\\?xml.*?\\?>|<!DOCTYPE[^>]*>|</?(html|body)[^>]*>",
            with: "",
            options: .regularExpression
        )
        return result
    }

    private static func stripUnsafeMarkup(_ html: String) -> String {
        var result = html
        let patterns = [
            "(?is)<script\\b[^>]*>.*?</script>",
            "(?is)<style\\b[^>]*>.*?</style>",
            "(?is)<link\\b[^>]*>",
            "(?is)<base\\b[^>]*>",
            "(?is)\\son[a-z]+\\s*=\\s*(\"[^\"]*\"|'[^']*'|[^\\s>]+)",
            "(?is)<iframe\\b[^>]*>.*?</iframe>",
            "(?is)<object\\b[^>]*>.*?</object>",
            "(?is)<embed\\b[^>]*>",
        ]
        for pattern in patterns {
            result = result.replacingOccurrences(of: pattern, with: "", options: .regularExpression)
        }
        return result
    }

    private static func inlineImages(in html: String, chapterPath: String, contentRoot: URL) -> String {
        let chapterDirectory = EPUBParser.directory(of: chapterPath)
        var result = html
        var replacements: [(Range<String.Index>, String)] = []

        guard let tagRegex = try? NSRegularExpression(pattern: "(?is)<img\\b[^>]*>", options: []) else {
            return html
        }
        let fullRange = NSRange(result.startIndex..<result.endIndex, in: result)
        for match in tagRegex.matches(in: result, options: [], range: fullRange) {
            guard let tagRange = Range(match.range, in: result) else { continue }
            let tag = String(result[tagRange])
            guard
                let source = attribute("src", in: tag),
                !source.hasPrefix("data:"),
                !source.hasPrefix("http")
            else { continue }

            let relativePath = EPUBParser.resolve(base: chapterDirectory, href: source)
            let fileURL = EPUBParser.fileURL(root: contentRoot, relativePath: relativePath)
            guard
                let data = try? Data(contentsOf: fileURL),
                let dataURL = dataURL(data: data, path: relativePath)
            else {
                replacements.append((tagRange, ""))
                continue
            }
            var newTag = tag
            if let srcRange = newTag.range(of: "(?is)src\\s*=\\s*(\"[^\"]*\"|'[^']*'|[^\\s>]+)", options: .regularExpression) {
                newTag.replaceSubrange(srcRange, with: "src=\"\(dataURL)\"")
            }
            newTag = newTag.replacingOccurrences(
                of: "(?is)\\s(srcset|sizes)\\s*=\\s*(\"[^\"]*\"|'[^']*'|[^\\s>]+)",
                with: "",
                options: .regularExpression
            )
            replacements.append((tagRange, newTag))
        }

        for (range, replacement) in replacements.reversed() {
            result.replaceSubrange(range, with: replacement)
        }
        return result
    }

    private static func attribute(_ name: String, in tag: String) -> String? {
        let pattern = "(?is)\\b\(name)\\s*=\\s*(\"[^\"]*\"|'[^']*'|[^\\s>]+)"
        guard
            let regex = try? NSRegularExpression(pattern: pattern, options: []),
            let match = regex.firstMatch(in: tag, options: [], range: NSRange(tag.startIndex..<tag.endIndex, in: tag)),
            match.numberOfRanges > 1,
            let valueRange = Range(match.range(at: 1), in: tag)
        else { return nil }
        var value = String(tag[valueRange])
        if (value.hasPrefix("\"") && value.hasSuffix("\"")) || (value.hasPrefix("'") && value.hasSuffix("'")) {
            value.removeFirst()
            value.removeLast()
        }
        return value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func dataURL(data: Data, path: String) -> String? {
        let ext = (path as NSString).pathExtension.lowercased()
        let mimeType: String
        switch ext {
        case "png": mimeType = "image/png"
        case "gif": mimeType = "image/gif"
        case "svg": mimeType = "image/svg+xml"
        case "webp": mimeType = "image/webp"
        case "heic": mimeType = "image/heic"
        default: mimeType = "image/jpeg"
        }
        return "data:\(mimeType);base64,\(data.base64EncodedString())"
    }

    // MARK: - 样式与脚本

    private static func styleSheet(appearance: ReaderAppearance) -> String {
        """
        :root {
          --reader-font-size: \(Int(appearance.fontSize))px;
          --reader-line-height: \(String(format: "%.2f", appearance.lineHeight));
          --reader-padding: \(Int(appearance.horizontalPadding))px;
          --reader-font-family: \(appearance.font.cssStack);
          --reader-text: \(appearance.theme.textColorHex);
          --reader-bg: \(appearance.theme.backgroundColorHex);
          --reader-accent: \(appearance.theme.accentHex);
          --reader-translation-bg: \(appearance.theme.translationBackgroundHex);
        }
        html { background: var(--reader-bg); }
        body {
          margin: 0;
          padding: 12px var(--reader-padding) 120px;
          background: var(--reader-bg);
          color: var(--reader-text);
          font-family: var(--reader-font-family);
          font-size: var(--reader-font-size);
          line-height: var(--reader-line-height);
          -webkit-text-size-adjust: 100%;
          -webkit-font-smoothing: antialiased;
          overflow-wrap: break-word;
          word-break: break-word;
        }
        p, div, li, dd, td { text-align: justify; }
        p { margin: 0 0 1.05em; }
        \(appearance.firstLineIndent ? "p { text-indent: 2em; }" : "")
        h1, h2, h3, h4, h5, h6 { line-height: 1.4; margin: 1.5em 0 0.75em; font-weight: 600; }
        h1 { font-size: 1.45em; }
        h2 { font-size: 1.28em; }
        h3 { font-size: 1.14em; }
        img, svg, video, table { max-width: 100%; height: auto; }
        a { color: var(--reader-accent); text-decoration: none; }
        blockquote { margin: 0 0 1.1em; padding-left: 0.9em; border-left: 3px solid var(--reader-accent); opacity: 0.92; }
        hr { border: none; border-top: 1px solid var(--reader-accent); opacity: 0.3; margin: 1.6em 0; }
        ::selection { background: rgba(255, 206, 84, 0.45); }
        .reader-translation {
          margin: -0.35em 0 1.15em;
          padding: 0.62em 0.8em;
          border-left: 3px solid var(--reader-accent);
          border-radius: 6px;
          background: var(--reader-translation-bg);
          font-size: 0.95em;
          line-height: 1.72;
          text-indent: 0;
        }
        .reader-translation-tag {
          display: inline-block;
          margin-right: 0.45em;
          padding: 0 0.38em;
          border-radius: 4px;
          background: var(--reader-accent);
          color: #fff;
          font-size: 0.72em;
          vertical-align: 0.12em;
          text-indent: 0;
        }
        """
    }

    private static func script(appearance: ReaderAppearance, initialProgress: Double) -> String {
        """
        (function () {
          var bridge = window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.reader;
          if (!bridge) { return; }
          var counter = 0;

          function post(payload) {
            try { bridge.postMessage(payload); } catch (error) { }
          }

          function isBlock(element) {
            if (!element || !element.tagName) { return false; }
            return /^(P|LI|BLOCKQUOTE|H1|H2|H3|H4|H5|H6|TD|DD|DT|DIV|SECTION|ARTICLE|PRE)$/.test(element.tagName);
          }

          function blockOf(node) {
            var element = node && node.nodeType === 1 ? node : (node ? node.parentElement : null);
            while (element && !isBlock(element)) { element = element.parentElement; }
            return element;
          }

          function ensureAnchor(element) {
            if (!element) { return ""; }
            if (!element.dataset.rid) {
              counter += 1;
              element.dataset.rid = "rid-" + counter + "-" + Math.floor(Math.random() * 1000000);
            }
            return element.dataset.rid;
          }

          function rectJSON(rect) {
            if (!rect) { return { x: 0, y: 0, width: 0, height: 0 }; }
            return { x: rect.x, y: rect.y, width: rect.width, height: rect.height };
          }

          function contextOf(element) {
            var context = { paragraph: "", before: "", after: "" };
            if (!element) { return context; }
            context.paragraph = (element.innerText || "").replace(/\\s+/g, " ").trim().slice(0, 1500);
            var previous = element.previousElementSibling;
            var next = element.nextElementSibling;
            if (previous) {
              context.before = (previous.innerText || "").replace(/\\s+/g, " ").trim().slice(-500);
            }
            if (next) {
              context.after = (next.innerText || "").replace(/\\s+/g, " ").trim().slice(0, 500);
            }
            return context;
          }

          var selectionTimer = null;
          function handleSelectionChange() {
            if (selectionTimer) { clearTimeout(selectionTimer); }
            selectionTimer = setTimeout(function () {
              var selection = window.getSelection();
              var text = selection ? selection.toString().replace(/[ \\t]+\\n/g, "\\n").trim() : "";
              if (!text) {
                post({ type: "selectionCleared" });
                return;
              }
              if (!selection.rangeCount) { return; }
              var range = selection.getRangeAt(0);
              var rect = range.getBoundingClientRect();
              if ((!rect || (rect.width === 0 && rect.height === 0)) && range.getClientRects().length) {
                rect = range.getClientRects()[0];
              }
              var block = blockOf(range.startContainer);
              post({
                type: "selection",
                text: text,
                anchorId: ensureAnchor(block),
                rect: rectJSON(rect),
                context: contextOf(block)
              });
            }, 220);
          }
          document.addEventListener("selectionchange", handleSelectionChange);

          document.addEventListener("click", function (event) {
            var target = event.target;
            if (!target || !target.closest) { return; }
            var anchor = target.closest("a");
            if (anchor) {
              post({ type: "link", href: anchor.getAttribute("href") || "" });
              return;
            }
            var selection = window.getSelection();
            if (selection && selection.toString().trim().length > 0) { return; }
            var element = blockOf(target);
            if (!element) { return; }
            if (element.classList && element.classList.contains("reader-translation")) { return; }
            var text = (element.innerText || "").trim();
            if (text.length < 1) { return; }
            post({
              type: "paragraphTap",
              text: text.slice(0, 4000),
              anchorId: ensureAnchor(element),
              rect: rectJSON(element.getBoundingClientRect()),
              context: contextOf(element)
            });
          }, false);

          var scrollTimer = null;
          window.addEventListener("scroll", function () {
            if (scrollTimer) { clearTimeout(scrollTimer); }
            scrollTimer = setTimeout(function () {
              var max = Math.max(1, document.documentElement.scrollHeight - window.innerHeight);
              post({ type: "progress", value: Math.min(1, Math.max(0, window.scrollY / max)) });
            }, 320);
          }, { passive: true });

          function escapeHTML(value) {
            return String(value).replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;");
          }

          window.__reader = {
            setFontSize: function (size) {
              document.documentElement.style.setProperty("--reader-font-size", size + "px");
            },
            setLineHeight: function (value) {
              document.documentElement.style.setProperty("--reader-line-height", value);
            },
            insertTranslation: function (anchorId, text) {
              var target = document.querySelector('[data-rid="' + anchorId + '"]');
              if (!target) { return false; }
              var html = '<span class="reader-translation-tag">译</span>' + escapeHTML(text).replace(/\\n{2,}/g, "<br><br>").replace(/\\n/g, "<br>");
              var sibling = target.nextElementSibling;
              if (sibling && sibling.classList && sibling.classList.contains("reader-translation")) {
                sibling.innerHTML = html;
                return true;
              }
              var block = document.createElement("div");
              block.className = "reader-translation";
              block.setAttribute("data-for-anchor", anchorId);
              block.innerHTML = html;
              target.parentNode.insertBefore(block, target.nextSibling);
              return true;
            },
            removeTranslation: function (anchorId) {
              var block = document.querySelector('.reader-translation[data-for-anchor="' + anchorId + '"]');
              if (!block) { return false; }
              block.parentNode.removeChild(block);
              return true;
            },
            scrollToTop: function () {
              window.scrollTo(0, 0);
            },
            initialProgress: function () {
              return \(String(format: "%.5f", initialProgress));
            }
          };

          window.addEventListener("load", function () {
            if (window.__reader.initialProgress() > 0.002) {
              var max = Math.max(0, document.documentElement.scrollHeight - window.innerHeight);
              window.scrollTo(0, window.__reader.initialProgress() * max);
            }
            post({ type: "ready" });
          });
        })();
        """
    }
}
