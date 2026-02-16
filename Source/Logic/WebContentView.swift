#if canImport(SwiftUI) && canImport(WebKit)
import SwiftUI
import WebKit

public struct WebContentView: View {
    let url: String
    @State private var isLoading = true
    
    public init(url: String) {
        self.url = url
    }
    
    public var body: some View {
        ZStack {
            WebViewRepresentable(urlString: url, isLoading: $isLoading)
                .ignoresSafeArea()
            
            if isLoading {
                LoadingOverlay()
            }
        }
    }
}

private struct LoadingOverlay: View {
    var body: some View {
        ZStack {
            Color.black.opacity(0.3)
                .ignoresSafeArea()
            
            ProgressView()
                .scaleEffect(1.5)
                .tint(.white)
        }
    }
}

public struct WebViewRepresentable: UIViewControllerRepresentable {
    let urlString: String
    @Binding var isLoading: Bool
    
    public init(urlString: String, isLoading: Binding<Bool>) {
        self.urlString = urlString
        self._isLoading = isLoading
    }
    
    public func makeUIViewController(context: Context) -> WebViewController {
        let controller = WebViewController()
        controller.delegate = context.coordinator
        controller.loadURL(urlString)
        return controller
    }
    
    public func updateUIViewController(_ uiViewController: WebViewController, context: Context) {}
    
    public func makeCoordinator() -> Coordinator {
        Coordinator(isLoading: $isLoading)
    }
    
    public class Coordinator: WebViewControllerDelegate {
        @Binding var isLoading: Bool
        
        init(isLoading: Binding<Bool>) {
            _isLoading = isLoading
        }
        
        public func webViewDidStartLoading() {
            DispatchQueue.main.async {
                self.isLoading = true
            }
        }
        
        public func webViewDidFinishLoading() {
            DispatchQueue.main.async {
                self.isLoading = false
            }
        }
    }
}

public protocol WebViewControllerDelegate: AnyObject {
    func webViewDidStartLoading()
    func webViewDidFinishLoading()
}

public class WebViewController: UIViewController {
    public weak var delegate: WebViewControllerDelegate?
    
    private var webView: WKWebView!
    private var backButton: UILabel!
    private var navigationDepth: Int = 0
    private var pendingURLString: String?
    
    public override func viewDidLoad() {
        super.viewDidLoad()
        setupWebView()
        // setupBackButton() // Кнопка BACK скрыта
        
        // Загружаем URL, если он был передан до viewDidLoad
        if let urlString = pendingURLString {
            loadURL(urlString)
            pendingURLString = nil
        }
    }
    
    private func setupWebView() {
        let configuration = WKWebViewConfiguration()
        configuration.allowsInlineMediaPlayback = true
        
        webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.translatesAutoresizingMaskIntoConstraints = false
        webView.scrollView.bounces = true
        webView.allowsBackForwardNavigationGestures = true
        
        view.addSubview(webView)
        
        NSLayoutConstraint.activate([
            webView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            webView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            webView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }
    
    private func setupBackButton() {
        backButton = UILabel()
        backButton.text = "◄ BACK"
        backButton.font = UIFont.monospacedSystemFont(ofSize: 17, weight: .semibold)
        backButton.textColor = .systemBlue
        backButton.layer.shadowColor = UIColor.black.cgColor
        backButton.layer.shadowRadius = 2.0
        backButton.layer.shadowOpacity = 0.5
        backButton.layer.shadowOffset = CGSize(width: 1, height: 1)
        backButton.isUserInteractionEnabled = true
        backButton.alpha = 0
        
        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(handleBackTap))
        backButton.addGestureRecognizer(tapGesture)
        
        backButton.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(backButton)
        
        NSLayoutConstraint.activate([
            backButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            backButton.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 12)
        ])
    }
    
    public func loadURL(_ urlString: String) {
        // Если webView еще не инициализирован, сохраняем URL для загрузки позже
        guard webView != nil else {
            pendingURLString = urlString
            return
        }
        
        guard let url = URL(string: urlString) else { return }
        let request = URLRequest(url: url)
        webView.load(request)
    }
    
    @objc private func handleBackTap() {
        if webView.canGoBack {
            navigationDepth -= 1
            webView.goBack()
        }
        // updateBackButtonVisibility() // Кнопка BACK скрыта
    }
    
    private func updateBackButtonVisibility() {
        UIView.animate(withDuration: 0.25) {
            self.backButton.alpha = self.webView.canGoBack ? 1.0 : 0.0
        }
    }
}

extension WebViewController: WKNavigationDelegate {
    public func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        delegate?.webViewDidStartLoading()
    }
    
    public func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        delegate?.webViewDidFinishLoading()
        // updateBackButtonVisibility() // Кнопка BACK скрыта
    }
    
    public func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        delegate?.webViewDidFinishLoading()
    }
    
    public func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        delegate?.webViewDidFinishLoading()
    }
}

extension WebViewController: WKUIDelegate {
    public func webView(_ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping () -> Void) {
        let alert = UIAlertController(title: nil, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default) { _ in
            completionHandler()
        })
        present(alert, animated: true)
    }
    
    public func webView(_ webView: WKWebView, runJavaScriptConfirmPanelWithMessage message: String, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (Bool) -> Void) {
        let alert = UIAlertController(title: nil, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel) { _ in
            completionHandler(false)
        })
        alert.addAction(UIAlertAction(title: "OK", style: .default) { _ in
            completionHandler(true)
        })
        present(alert, animated: true)
    }
    
    public func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        if navigationAction.targetFrame == nil, let url = navigationAction.request.url {
            navigationDepth += 1
            webView.load(URLRequest(url: url))
        }
        return nil
    }
}

#endif
