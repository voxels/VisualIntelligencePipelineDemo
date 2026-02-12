import Foundation
import LinkPresentation
#if canImport(MessageUI)
import MessageUI
#endif
#if canImport(UIKit)
import UIKit
#endif

#if canImport(UIKit) && os(iOS)
/// A utility for sharing links with rich metadata, specifically for custom schemes
/// where automatic scraping by Messages app might fail.
/// 
@MainActor
public class RichLinkSharer: NSObject, MFMessageComposeViewControllerDelegate {

    public static let shared = RichLinkSharer()

    // Keep a strong reference to the metadata provider if needed,
    // though for manual construction we just need the object.
    
    /// Presents a configured MFMessageComposeViewController with rich link metadata.
    /// - Parameters:
    ///   - sourceViewController: The view controller to present from.
    ///   - url: The URL to share (can be a custom scheme).
    ///   - title: The title for the preview.
    ///   - image: An optional image (UIImage) for the preview icon.
    ///   - originalURL: An optional fallback URL (e.g. valid https) if the primary URL is a deep link.
    public func presentMessageComposer(
        from sourceViewController: UIViewController,
        url: URL,
        title: String?,
        image: UIImage?,
        originalURL: URL? = nil
    ) {
        #if canImport(MessageUI)
        guard MFMessageComposeViewController.canSendText() else {
            print("❌ RichLinkSharer: Device cannot send texts.")
            // Fallback to basic share sheet or alert?
            // For now, simpler fallback: just open the URL if possible, or copy to clipboard layout?
            // But this method specifically promises Message Composer.
            return
        }
        
        let composeVC = MFMessageComposeViewController()
        composeVC.messageComposeDelegate = self
        
        // Create Rich Metadata
        let metadata = LPLinkMetadata()
        metadata.originalURL = originalURL ?? url
        metadata.url = url
        metadata.title = title ?? "Shared Link"
        
        if let image = image {
            metadata.iconProvider = NSItemProvider(object: image)
            metadata.imageProvider = NSItemProvider(object: image)
        }
        
        // In iOS 13+, we can set the message payload with metadata
        // However, MFMessageComposeViewController doesn't have a direct 'linkMetadata' property publicly exposed
        // in a way that guarantees the bubble.
        // The standard way to share a rich link programmatically is just to put the URL in the body.
        // BUT, for custom schemes, Messages won't scrape it.
        // WORKAROUND: Use MSMessage (Messages Framework) if we were an iMessage App.
        // Since we are likely NOT an iMessage app (just a standard app), we are limited.
        //
        // WAIT - standard `sms:` or `MFMessageComposeViewController` body = URL only text.
        // To get the Bubble, we normally need `UIActivityViewController`.
        //
        // Let's try `UIActivityViewController` first as it supports `LPLinkMetadata` via `UIActivityItemSource`.
        // `MFMessageComposeViewController` does NOT supports rich links unless you are an iMessage App extension
        // sending an `MSMessage`.
        
        // Re-routing strategy: Use UIActivityViewController with a custom item source that provides the metadata.
        print("⚠️ RichLinkSharer: Switching to UIActivityViewController for Rich Link support.")
        presentShareSheet(from: sourceViewController, url: url, title: title, image: image, originalURL: originalURL)
        
        #else
        print("❌ RichLinkSharer: MessageUI not available.")
        #endif
    }
    
    /// Presents a UIActivityViewController with rich link metadata.
    /// This is the preferred way to share rich links from a standard app.
    public func presentShareSheet(
        from sourceViewController: UIViewController,
        url: URL,
        title: String?,
        image: UIImage?,
        originalURL: URL? = nil
    ) {
        let linkSource = RichLinkActivitySource(url: url, title: title, image: image, originalURL: originalURL)
        
        let activityVC = UIActivityViewController(
            activityItems: [linkSource],
            applicationActivities: nil
        )
        
        // iPad support
        if let popover = activityVC.popoverPresentationController {
            popover.sourceView = sourceViewController.view
            popover.sourceRect = CGRect(x: sourceViewController.view.bounds.midX, y: sourceViewController.view.bounds.midY, width: 0, height: 0)
            popover.permittedArrowDirections = []
        }
        
        sourceViewController.present(activityVC, animated: true)
    }
    
    nonisolated public func messageComposeViewController(_ controller: MFMessageComposeViewController, didFinishWith result: MessageComposeResult) {
        Task { @MainActor in
            controller.dismiss(animated: true)
        }
    }
}
#else
/// A no-op placeholder to avoid duplicate type names on non-iOS platforms.
@MainActor
public class RichLinkSharer: NSObject {
    public static let shared = RichLinkSharer()
}
#endif

// MARK: - UIActivityItemSource

#if canImport(UIKit) && os(iOS)
class RichLinkActivitySource: NSObject, UIActivityItemSource {
    let url: URL
    let title: String?
    let image: UIImage?
    let originalURL: URL?
    
    init(url: URL, title: String?, image: UIImage?, originalURL: URL?) {
        self.url = url
        self.title = title
        self.image = image
        self.originalURL = originalURL
        super.init()
    }
    
    func activityViewControllerPlaceholderItem(_ activityViewController: UIActivityViewController) -> Any {
        return url
    }
    
    func activityViewController(_ activityViewController: UIActivityViewController, itemForActivityType activityType: UIActivity.ActivityType?) -> Any? {
        return url
    }
    
    func activityViewControllerLinkMetadata(_ activityViewController: UIActivityViewController) -> LPLinkMetadata? {
        let metadata = LPLinkMetadata()
        metadata.originalURL = originalURL ?? url
        metadata.url = url
        metadata.title = title ?? "Shared Link"
        
        if let image = image {
            metadata.iconProvider = NSItemProvider(object: image)
            metadata.imageProvider = NSItemProvider(object: image)
        }
        
        return metadata
    }
}
#endif
