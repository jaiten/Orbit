import UIKit
import SwiftUI
import UniformTypeIdentifiers

/// "Add to Orbit" in the share sheet: text and web pages from Safari, Mail, Notes and other apps.
@objc(ShareViewController)
final class ShareViewController: UIViewController {
    override func viewDidLoad() {
        super.viewDidLoad()
        let items = extensionContext?.inputItems as? [NSExtensionItem] ?? []
        Task { @MainActor in
            let shared = await SharedContent.load(from: items)
            let view = ShareView(shared: shared,
                                 done: { [weak self] in self?.extensionContext?.completeRequest(returningItems: nil) },
                                 cancel: { [weak self] in self?.extensionContext?.cancelRequest(withError: CocoaError(.userCancelled)) })
            let host = UIHostingController(rootView: view)
            addChild(host)
            host.view.frame = self.view.bounds
            host.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            self.view.addSubview(host.view)
            host.didMove(toParent: self)
        }
    }
}

/// The shared text (or page title) and web address, if any.
struct SharedContent {
    var text: String
    var url: URL?

    static func load(from items: [NSExtensionItem]) async -> SharedContent {
        var text = "", url: URL?
        for item in items {
            if text.isEmpty, let title = (item.attributedTitle ?? item.attributedContentText)?.string { text = title }
            for provider in item.attachments ?? [] {
                if url == nil, provider.hasItemConformingToTypeIdentifier(UTType.url.identifier),
                   let value = try? await provider.loadItem(forTypeIdentifier: UTType.url.identifier) as? URL {
                    url = value
                } else if text.isEmpty, provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier),
                          let value = try? await provider.loadItem(forTypeIdentifier: UTType.plainText.identifier) as? String {
                    text = value
                }
            }
        }
        // A bare link still gets a readable title.
        if text.isEmpty, let url { text = url.host() ?? url.absoluteString }
        if let url, text == url.absoluteString { text = url.host() ?? text }
        return SharedContent(text: text.trimmingCharacters(in: .whitespacesAndNewlines), url: url)
    }
}
