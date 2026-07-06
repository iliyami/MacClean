import Foundation

/// Minimal Sparkle appcast XML parser. Extracts the latest version's
/// `sparkle:shortVersionString` (or `sparkle:version`) from an appcast feed.
public final class AppcastParser: NSObject, XMLParserDelegate, @unchecked Sendable {
    /// Highest-version item seen so far (across the whole feed).
    private var bestVersion: String?
    private var bestDownloadURL: URL?
    /// Version/URL of the item currently being parsed.
    private var inItem = false
    private var currentVersion: String?
    private var currentURL: URL?

    public override init() { super.init() }

    public func parseLatestVersion(from data: Data) -> String? {
        parseLatestItem(from: data).version
    }

    public func parseLatestItem(from data: Data) -> (version: String?, downloadURL: URL?) {
        bestVersion = nil
        bestDownloadURL = nil
        inItem = false
        currentVersion = nil
        currentURL = nil
        let parser = XMLParser(data: data)
        parser.delegate = self
        parser.parse()
        return (bestVersion, bestDownloadURL)
    }

    public func parser(_ parser: XMLParser, didStartElement elementName: String,
                       namespaceURI: String?, qualifiedName: String?,
                       attributes: [String: String] = [:]) {
        if elementName == "item" {
            inItem = true
            currentVersion = nil
            currentURL = nil
        }
        if elementName == "enclosure", inItem {
            if let version = attributes["sparkle:shortVersionString"] ?? attributes["sparkle:version"],
               currentVersion == nil {
                currentVersion = version
            }
            if let urlStr = attributes["url"], let url = URL(string: urlStr), currentURL == nil {
                currentURL = url
            }
        }
    }

    public func parser(_ parser: XMLParser, didEndElement elementName: String,
                       namespaceURI: String?, qualifiedName: String?) {
        guard elementName == "item" else { return }
        inItem = false
        // Keep the highest version across all items. Sparkle appcasts are NOT
        // guaranteed to list the newest release first (issue #105: taking the
        // first item offered downgrades), so compare every item's version.
        if let version = currentVersion,
           bestVersion == nil || UpdateChecker.isNewer(version, than: bestVersion!) {
            bestVersion = version
            bestDownloadURL = currentURL
        }
        currentVersion = nil
        currentURL = nil
    }
}
