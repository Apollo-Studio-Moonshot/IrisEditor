import AppKit
import WebKit

enum PDFExportError: LocalizedError {
    case couldNotLoad
    case couldNotCreatePDF
    case timedOut

    var errorDescription: String? {
        switch self {
        case .couldNotLoad:
            return "The document could not be rendered for export."
        case .couldNotCreatePDF:
            return "The PDF could not be created."
        case .timedOut:
            return "The document took too long to render."
        }
    }
}

/// Renders the preview HTML in an offscreen WebKit view to produce PDFs or print jobs.
@MainActor
enum MarkdownPDFExporter {
    private static let pageSize = CGSize(width: 800, height: 1000)
    private static let loadTimeout: TimeInterval = 15
    private static let layoutDelay: Duration = .milliseconds(400)

    static func exportPDF(html: String, to url: URL) async throws {
        let data = try await makePDF(html: html)
        try data.write(to: url, options: [.atomic])
    }

    static func makePDF(html: String) async throws -> Data {
        let webView = WKWebView(frame: CGRect(origin: .zero, size: pageSize))
        let waiter = PDFNavigationWaiter()
        webView.navigationDelegate = waiter
        defer { webView.navigationDelegate = nil }

        webView.loadHTMLString(html, baseURL: nil)
        try await waiter.wait(timeout: loadTimeout)
        try await Task.sleep(for: layoutDelay)
        try Task.checkCancellation()

        // The default configuration captures the web view's entire content.
        let configuration = WKPDFConfiguration()

        do {
            return try await webView.pdf(configuration: configuration)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw PDFExportError.couldNotCreatePDF
        }
    }

    static func printHTML(_ html: String, jobTitle: String) async throws {
        let webView = WKWebView(frame: CGRect(origin: .zero, size: pageSize))
        let waiter = PDFNavigationWaiter()
        webView.navigationDelegate = waiter

        // WKWebView needs a window for printing; keep it offscreen so nothing flashes.
        let window = NSWindow(
            contentRect: CGRect(origin: CGPoint(x: -20_000, y: -20_000), size: pageSize),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.contentView = webView
        window.orderFrontRegardless()

        defer {
            window.orderOut(nil)
            webView.navigationDelegate = nil
        }

        webView.loadHTMLString(html, baseURL: nil)
        try await waiter.wait(timeout: loadTimeout)
        try await Task.sleep(for: layoutDelay)
        try Task.checkCancellation()

        let printInfo = (NSPrintInfo.shared.copy() as? NSPrintInfo) ?? NSPrintInfo.shared
        printInfo.jobDisposition = .spool
        printInfo.horizontalPagination = .fit
        printInfo.verticalPagination = .automatic

        let operation = NSPrintOperation(view: webView, printInfo: printInfo)
        operation.jobTitle = jobTitle
        operation.showsPrintPanel = true
        operation.showsProgressPanel = true

        guard operation.run() else {
            throw PDFExportError.couldNotCreatePDF
        }
    }
}

/// Bridges `WKNavigationDelegate` callbacks to an async wait with a timeout.
@MainActor
private final class PDFNavigationWaiter: NSObject, WKNavigationDelegate {
    private var continuation: CheckedContinuation<Void, Error>?
    private var timeoutTask: Task<Void, Never>?
    private var settled = false
    private var hasFinishedLoading = false

    func wait(timeout: TimeInterval) async throws {
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                self.continuation = continuation
                if self.hasFinishedLoading {
                    self.settle(.success(()))
                } else {
                    self.timeoutTask = Task { @MainActor [weak self] in
                        try? await Task.sleep(for: .seconds(timeout))
                        guard !Task.isCancelled else { return }
                        self?.settle(.failure(PDFExportError.timedOut))
                    }
                }
            }
        } onCancel: {
            Task { @MainActor in
                self.settle(.failure(CancellationError()))
            }
        }
    }

    private func settle(_ result: Result<Void, Error>) {
        guard !settled else { return }
        settled = true
        timeoutTask?.cancel()
        timeoutTask = nil
        let continuation = self.continuation
        self.continuation = nil
        continuation?.resume(with: result)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        hasFinishedLoading = true
        settle(.success(()))
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: any Error) {
        settle(.failure(PDFExportError.couldNotLoad))
    }

    func webView(
        _ webView: WKWebView,
        didFailProvisionalNavigation navigation: WKNavigation!,
        withError error: any Error
    ) {
        settle(.failure(PDFExportError.couldNotLoad))
    }
}
