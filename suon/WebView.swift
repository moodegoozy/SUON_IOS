//
//  WebView.swift
//  suon
//
//  WKWebView wrapper with custom file upload via the Files app (no permissions required).
//

import SwiftUI
import WebKit
import UniformTypeIdentifiers

// MARK: - SwiftUI Wrapper

struct WebView: UIViewRepresentable {
    let url: URL
    @Binding var isLoading: Bool
    @Binding var estimatedProgress: Double
    @Binding var canGoBack: Bool
    @Binding var canGoForward: Bool

    func makeCoordinator() -> WebViewCoordinator {
        WebViewCoordinator(parent: self)
    }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []
        config.defaultWebpagePreferences.allowsContentJavaScript = true
        config.websiteDataStore = .default()

        // User content controller — inject the file picker bridge.
        let ucc = WKUserContentController()
        let script = WKUserScript(
            source: WebView.fileUploadBridgeScript,
            injectionTime: .atDocumentStart,
            forMainFrameOnly: false
        )
        ucc.addUserScript(script)
        ucc.add(context.coordinator, name: "fileUploadBridge")
        config.userContentController = ucc

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.allowsBackForwardNavigationGestures = true
        webView.allowsLinkPreview = true
        webView.scrollView.contentInsetAdjustmentBehavior = .always
        webView.isOpaque = false
        webView.backgroundColor = .systemBackground
        webView.scrollView.backgroundColor = .clear
        webView.customUserAgent = WebView.modernUserAgent
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator

        // KVO observers
        context.coordinator.observe(webView: webView)

        webView.load(URLRequest(url: url))
        context.coordinator.webView = webView
        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}

    static func dismantleUIView(_ uiView: WKWebView, coordinator: WebViewCoordinator) {
        coordinator.invalidate(webView: uiView)
    }

    // MARK: - Constants

    static let modernUserAgent: String =
        "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1 SuonApp/1.0"

    /// Injected JS that intercepts <input type="file"> clicks and routes them
    /// to a native UIDocumentPickerViewController. After the native side
    /// returns base64 data, we synthesize File objects and dispatch input/change events.
    static let fileUploadBridgeScript: String = """
    (function() {
      if (window.__suonFileBridgeInstalled) return;
      window.__suonFileBridgeInstalled = true;

      const pendingInputs = new Map();
      let requestSeq = 0;

      function dispatchEvents(input) {
        try {
          input.dispatchEvent(new Event('input',  { bubbles: true, composed: true }));
          input.dispatchEvent(new Event('change', { bubbles: true, composed: true }));
        } catch (e) { /* ignore */ }
      }

      function buildFile(meta) {
        const byteString = atob(meta.base64);
        const len = byteString.length;
        const bytes = new Uint8Array(len);
        for (let i = 0; i < len; i++) bytes[i] = byteString.charCodeAt(i);
        return new File([bytes], meta.name, { type: meta.mime || 'application/octet-stream', lastModified: Date.now() });
      }

      window.__suonFileBridgeDeliver = function(requestId, filesMeta) {
        const input = pendingInputs.get(requestId);
        pendingInputs.delete(requestId);
        if (!input) return;
        if (!filesMeta || !filesMeta.length) return;
        try {
          const dt = new DataTransfer();
          for (const m of filesMeta) dt.items.add(buildFile(m));
          input.files = dt.files;
          dispatchEvents(input);
        } catch (e) {
          console.error('suon bridge: failed to set files', e);
        }
      };

      function handleClick(e) {
        const t = e.target;
        if (!t || t.tagName !== 'INPUT' || t.type !== 'file') return;
        e.preventDefault();
        e.stopPropagation();
        const requestId = ++requestSeq;
        pendingInputs.set(requestId, t);
        try {
          window.webkit.messageHandlers.fileUploadBridge.postMessage({
            requestId: requestId,
            accept: t.getAttribute('accept') || '',
            multiple: !!t.multiple
          });
        } catch (err) {
          pendingInputs.delete(requestId);
          console.error('suon bridge: postMessage failed', err);
        }
      }

      document.addEventListener('click', handleClick, true);
      document.addEventListener('touchend', handleClick, true);
    })();
    """
}

// MARK: - Coordinator

final class WebViewCoordinator: NSObject, WKNavigationDelegate, WKUIDelegate, WKScriptMessageHandler {
    var parent: WebView
    weak var webView: WKWebView?

    private var loadingObs: NSKeyValueObservation?
    private var progressObs: NSKeyValueObservation?
    private var backObs: NSKeyValueObservation?
    private var forwardObs: NSKeyValueObservation?

    init(parent: WebView) { self.parent = parent }

    func observe(webView: WKWebView) {
        loadingObs = webView.observe(\.isLoading, options: [.new]) { [weak self] _, change in
            guard let self, let v = change.newValue else { return }
            Task { @MainActor in self.parent.isLoading = v }
        }
        progressObs = webView.observe(\.estimatedProgress, options: [.new]) { [weak self] _, change in
            guard let self, let v = change.newValue else { return }
            Task { @MainActor in self.parent.estimatedProgress = v }
        }
        backObs = webView.observe(\.canGoBack, options: [.new]) { [weak self] _, change in
            guard let self, let v = change.newValue else { return }
            Task { @MainActor in self.parent.canGoBack = v }
        }
        forwardObs = webView.observe(\.canGoForward, options: [.new]) { [weak self] _, change in
            guard let self, let v = change.newValue else { return }
            Task { @MainActor in self.parent.canGoForward = v }
        }
    }

    func invalidate(webView: WKWebView) {
        loadingObs?.invalidate()
        progressObs?.invalidate()
        backObs?.invalidate()
        forwardObs?.invalidate()
        webView.configuration.userContentController.removeScriptMessageHandler(forName: "fileUploadBridge")
    }

    // MARK: WKNavigationDelegate

    func webView(_ webView: WKWebView,
                 decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard let url = navigationAction.request.url else {
            decisionHandler(.allow); return
        }
        let scheme = url.scheme?.lowercased() ?? ""
        if ["tel", "mailto", "sms", "facetime", "itms-apps", "maps"].contains(scheme) {
            UIApplication.shared.open(url, options: [:], completionHandler: nil)
            decisionHandler(.cancel); return
        }
        decisionHandler(.allow)
    }

    // Open target=_blank in same webview.
    func webView(_ webView: WKWebView,
                 createWebViewWith configuration: WKWebViewConfiguration,
                 for navigationAction: WKNavigationAction,
                 windowFeatures: WKWindowFeatures) -> WKWebView? {
        if navigationAction.targetFrame == nil, let url = navigationAction.request.url {
            webView.load(URLRequest(url: url))
        }
        return nil
    }

    // MARK: WKScriptMessageHandler

    func userContentController(_ userContentController: WKUserContentController,
                               didReceive message: WKScriptMessage) {
        guard message.name == "fileUploadBridge",
              let body = message.body as? [String: Any],
              let requestId = body["requestId"] as? Int else { return }

        let accept   = (body["accept"] as? String) ?? ""
        let multiple = (body["multiple"] as? Bool) ?? false

        Task { @MainActor in
            self.presentDocumentPicker(requestId: requestId, accept: accept, multiple: multiple)
        }
    }

    // MARK: File picker

    @MainActor
    private func presentDocumentPicker(requestId: Int, accept: String, multiple: Bool) {
        let types = FileUploadHelper.contentTypes(forAccept: accept)
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: types, asCopy: true)
        picker.allowsMultipleSelection = multiple
        picker.shouldShowFileExtensions = true

        let proxy = DocumentPickerProxy { [weak self] urls in
            self?.deliverFiles(requestId: requestId, urls: urls)
        }
        picker.delegate = proxy
        // Retain the proxy until dismissed.
        objc_setAssociatedObject(picker, &DocumentPickerProxy.assocKey, proxy, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)

        guard let presenter = WebViewCoordinator.topViewController() else {
            deliverFiles(requestId: requestId, urls: [])
            return
        }
        picker.modalPresentationStyle = .formSheet
        presenter.present(picker, animated: true)
    }

    @MainActor
    private func deliverFiles(requestId: Int, urls: [URL]) {
        let metas: [[String: String]] = urls.compactMap { url in
            guard let data = try? Data(contentsOf: url) else { return nil }
            let mime = FileUploadHelper.mimeType(for: url)
            return [
                "name": url.lastPathComponent,
                "mime": mime,
                "base64": data.base64EncodedString()
            ]
        }
        let payload: [String: Any] = ["files": metas]
        guard let json = try? JSONSerialization.data(withJSONObject: payload),
              let jsonString = String(data: json, encoding: .utf8) else {
            invokeDeliver(requestId: requestId, jsonArray: "[]")
            return
        }
        // Extract array portion
        let filesArray: String = {
            if let r = jsonString.range(of: "\"files\":") {
                return String(jsonString[r.upperBound..<jsonString.index(before: jsonString.endIndex)])
            }
            return "[]"
        }()
        invokeDeliver(requestId: requestId, jsonArray: filesArray)
    }

    @MainActor
    private func invokeDeliver(requestId: Int, jsonArray: String) {
        let js = "window.__suonFileBridgeDeliver && window.__suonFileBridgeDeliver(\(requestId), \(jsonArray));"
        webView?.evaluateJavaScript(js, completionHandler: nil)
    }

    static func topViewController(base: UIViewController? = nil) -> UIViewController? {
        let root = base ?? UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
            .first(where: { $0.isKeyWindow })?.rootViewController
        if let nav = root as? UINavigationController { return topViewController(base: nav.visibleViewController) }
        if let tab = root as? UITabBarController, let sel = tab.selectedViewController {
            return topViewController(base: sel)
        }
        if let presented = root?.presentedViewController { return topViewController(base: presented) }
        return root
    }
}

// MARK: - Document Picker Proxy

private final class DocumentPickerProxy: NSObject, UIDocumentPickerDelegate {
    static var assocKey: UInt8 = 0
    let completion: ([URL]) -> Void
    init(completion: @escaping ([URL]) -> Void) { self.completion = completion }

    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        completion(urls)
    }
    func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
        completion([])
    }
}

// MARK: - Helpers

enum FileUploadHelper {
    static func contentTypes(forAccept accept: String) -> [UTType] {
        let tokens = accept
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
            .filter { !$0.isEmpty }
        if tokens.isEmpty { return [.item] }

        var types: [UTType] = []
        for token in tokens {
            switch token {
            case "image/*": types.append(.image)
            case "video/*": types.append(.movie)
            case "audio/*": types.append(.audio)
            case "text/*":  types.append(.text)
            default:
                if token.hasPrefix(".") {
                    let ext = String(token.dropFirst())
                    if let t = UTType(filenameExtension: ext) { types.append(t) }
                } else if token.contains("/") {
                    if let t = UTType(mimeType: token) { types.append(t) }
                }
            }
        }
        return types.isEmpty ? [.item] : types
    }

    static func mimeType(for url: URL) -> String {
        if let type = UTType(filenameExtension: url.pathExtension), let mime = type.preferredMIMEType {
            return mime
        }
        return "application/octet-stream"
    }
}
