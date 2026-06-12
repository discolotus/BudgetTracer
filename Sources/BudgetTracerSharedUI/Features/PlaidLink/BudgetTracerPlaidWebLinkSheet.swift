#if os(macOS)
import SwiftUI
import WebKit

struct BudgetTracerPlaidWebLinkSheet: View {
    var linkToken: String
    var onSuccess: (String, String?) -> Void
    var onExit: () -> Void
    var onFailure: (String) -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Connect Account")
                    .font(.headline)

                Spacer()

                Button("Cancel", action: onExit)
                    .buttonStyle(.borderless)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 12)

            Divider()

            BudgetTracerPlaidWebView(
                linkToken: linkToken,
                onSuccess: onSuccess,
                onExit: onExit,
                onFailure: onFailure
            )
        }
        .frame(minWidth: 520, idealWidth: 560, minHeight: 680, idealHeight: 720)
    }
}

struct BudgetTracerPlaidWebView: NSViewRepresentable {
    var linkToken: String
    var onSuccess: (String, String?) -> Void
    var onExit: () -> Void
    var onFailure: (String) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(
            linkToken: linkToken,
            onSuccess: onSuccess,
            onExit: onExit,
            onFailure: onFailure
        )
    }

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true

        let controller = WKUserContentController()
        for messageName in Coordinator.messageNames {
            controller.add(context.coordinator, name: messageName)
        }
        configuration.userContentController = controller

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator
        context.coordinator.loadInitialLink(in: webView)
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        context.coordinator.onSuccess = onSuccess
        context.coordinator.onExit = onExit
        context.coordinator.onFailure = onFailure
        if context.coordinator.linkToken != linkToken {
            context.coordinator.linkToken = linkToken
            context.coordinator.loadInitialLink(in: webView)
        }
    }

    static func dismantleNSView(_ webView: WKWebView, coordinator: Coordinator) {
        for messageName in Coordinator.messageNames {
            webView.configuration.userContentController.removeScriptMessageHandler(forName: messageName)
        }
        webView.navigationDelegate = nil
        webView.uiDelegate = nil
        webView.stopLoading()
    }

    final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler, WKUIDelegate {
        static let messageNames = ["plaidSuccess", "plaidExit", "plaidError"]

        var linkToken: String
        var onSuccess: (String, String?) -> Void
        var onExit: () -> Void
        var onFailure: (String) -> Void
        private var didFinish = false

        init(
            linkToken: String,
            onSuccess: @escaping (String, String?) -> Void,
            onExit: @escaping () -> Void,
            onFailure: @escaping (String) -> Void
        ) {
            self.linkToken = linkToken
            self.onSuccess = onSuccess
            self.onExit = onExit
            self.onFailure = onFailure
        }

        func loadInitialLink(in webView: WKWebView) {
            didFinish = false
            webView.loadHTMLString(
                BudgetTracerPlaidWebLinkPage.html(linkToken: linkToken),
                baseURL: BudgetTracerPlaidWebLinkPage.baseURL
            )
        }

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            let payload = message.body as? [String: Any]
            switch message.name {
            case "plaidSuccess":
                guard let publicToken = payload?["publicToken"] as? String, !publicToken.isEmpty else {
                    complete { onFailure("Plaid did not return a public token.") }
                    return
                }
                complete { onSuccess(publicToken, payload?["institutionID"] as? String) }
            case "plaidExit":
                complete(onExit)
            case "plaidError":
                complete { onFailure(payload?["message"] as? String ?? "Plaid Link failed.") }
            default:
                break
            }
        }

        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
        ) {
            guard let url = navigationAction.request.url,
                  let receivedRedirectURI = BudgetTracerPlaidOAuthRedirect.receivedRedirectURI(from: url) else {
                decisionHandler(.allow)
                return
            }

            webView.loadHTMLString(
                BudgetTracerPlaidWebLinkPage.html(
                    linkToken: linkToken,
                    receivedRedirectURI: receivedRedirectURI
                ),
                baseURL: BudgetTracerPlaidWebLinkPage.baseURL
            )
            decisionHandler(.cancel)
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            guard !error.isWebKitCancellation else {
                return
            }
            complete { onFailure(error.localizedDescription) }
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            guard !error.isWebKitCancellation else {
                return
            }
            complete { onFailure(error.localizedDescription) }
        }

        func webView(
            _ webView: WKWebView,
            createWebViewWith configuration: WKWebViewConfiguration,
            for navigationAction: WKNavigationAction,
            windowFeatures: WKWindowFeatures
        ) -> WKWebView? {
            if navigationAction.targetFrame == nil {
                webView.load(navigationAction.request)
            }
            return nil
        }

        private func complete(_ action: () -> Void) {
            guard !didFinish else {
                return
            }
            didFinish = true
            action()
        }
    }
}

enum BudgetTracerPlaidWebLinkPage {
    static let baseURL = URL(string: "https://budgettracer.local/plaid/link")!

    static func html(linkToken: String, receivedRedirectURI: String? = nil) -> String {
        let encodedToken = jsonString(linkToken)
        let encodedReceivedRedirectURI = receivedRedirectURI.map(jsonString) ?? "null"
        return """
        <!doctype html>
        <html>
        <head>
          <meta charset="utf-8">
          <meta name="viewport" content="width=device-width, initial-scale=1">
          <style>
            html, body {
              width: 100%;
              height: 100%;
              margin: 0;
              font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
              background: #f7f8fb;
              color: #172033;
            }
            #status {
              min-height: 100%;
              display: grid;
              place-items: center;
              padding: 32px;
              box-sizing: border-box;
              text-align: center;
              font-size: 15px;
            }
          </style>
        </head>
        <body>
          <div id="status">Preparing Plaid Link...</div>
          <script>
            const linkToken = \(encodedToken);
            const receivedRedirectUri = \(encodedReceivedRedirectURI);
            let plaidHandler = null;

            function postMessage(name, payload) {
              window.webkit.messageHandlers[name].postMessage(payload || {});
            }

            function setStatus(text) {
              const status = document.getElementById('status');
              if (status) {
                status.textContent = text;
              }
            }

            function plaidLoadFailed() {
              postMessage('plaidError', { message: 'Plaid Link could not load.' });
            }

            function initializePlaid() {
              if (!window.Plaid) {
                plaidLoadFailed();
                return;
              }

              const plaidConfig = {
                token: linkToken,
                onSuccess: function(publicToken, metadata) {
                  const institution = metadata && metadata.institution ? metadata.institution : null;
                  postMessage('plaidSuccess', {
                    publicToken: publicToken,
                    institutionID: institution ? institution.institution_id : null
                  });
                },
                onExit: function(error, metadata) {
                  if (error) {
                    postMessage('plaidError', {
                      message: error.display_message || error.error_message || error.error_code || 'Plaid Link exited with an error.'
                    });
                  } else {
                    postMessage('plaidExit', {});
                  }
                },
                onEvent: function(eventName, metadata) {
                  if (eventName === 'OPEN') {
                    setStatus('Opening Plaid Link...');
                  }
                },
                onLoad: function() {
                  setStatus('Opening Plaid Link...');
                }
              };

              if (receivedRedirectUri) {
                plaidConfig.receivedRedirectUri = receivedRedirectUri;
              }

              plaidHandler = Plaid.create(plaidConfig);

              plaidHandler.open();
            }
          </script>
          <script src="https://cdn.plaid.com/link/v2/stable/link-initialize.js" onload="initializePlaid()" onerror="plaidLoadFailed()"></script>
        </body>
        </html>
        """
    }

    private static func jsonString(_ value: String) -> String {
        let data = (try? JSONEncoder().encode(value)) ?? Data("\"\"".utf8)
        let encoded = String(data: data, encoding: .utf8) ?? "\"\""
        return encoded.replacingOccurrences(of: "</", with: "<\\/")
    }
}

enum BudgetTracerPlaidOAuthRedirect {
    static func receivedRedirectURI(from url: URL) -> String? {
        guard let scheme = url.scheme?.lowercased(),
              scheme == "https" || scheme == "http",
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              components.queryItems?.contains(where: { $0.name == "oauth_state_id" }) == true else {
            return nil
        }

        return url.absoluteString
    }
}

private extension Error {
    var isWebKitCancellation: Bool {
        let nsError = self as NSError
        return nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorCancelled
    }
}
#endif
