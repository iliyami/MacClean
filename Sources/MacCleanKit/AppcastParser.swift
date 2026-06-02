import Foundation

/// Minimal Sparkle appcast XML parser. Extracts the latest version's
/// `sparkle:shortVersionString` (or `sparkle:version`) from an appcast feed.
public final class AppcastParser: NSObject, XMLParserDelegate, @unchecked Sendable {
    private var latestVersion: String?
    private var latestDownloadURL: URL?
    private var inItem = false

    public override init() { super.init() }

    public func parseLatestVersion(from data: Data) -> String? {
        latestVersion = nil
        latestDownloadURL = nil
        inItem = false
        let parser = XMLParser(data: data)
        parser.delegate = self
        parser.parse()
        return latestVersion
    }

    public func parseLatestItem(from data: Data) -> (version: String?, downloadURL: URL?) {
        latestVersion = nil
        latestDownloadURL = nil
        inItem = false
        let parser = XMLParser(data: data)
        parser.delegate = self
        parser.parse()
        return (latestVersion, latestDownloadURL)
    }

    public func parser(_ parser: XMLParser, didStartElement elementName: String,
                       namespaceURI: String?, qualifiedName: String?,
                       attributes: [String: String] = [:]) {
        if elementName == "item" {
            inItem = true
        }
        if elementName == "enclosure", inItem {
            if let version = attributes["sparkle:shortVersionString"] ?? attributes["sparkle:version"],
               latestVersion == nil {
                latestVersion = version
            }
            if let urlStr = attributes["url"], let url = URL(string: urlStr), latestDownloadURL == nil {
                latestDownloadURL = url
            }
        }
    }

    public func parser(_ parser: XMLParser, didEndElement elementName: String,
                       namespaceURI: String?, qualifiedName: String?) {
        if elementName == "item" {
            inItem = false
        }
    }
}
