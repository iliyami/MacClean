import XCTest
import Foundation
@testable import MacCleanKit

final class AppcastParserTests: XCTestCase {

    func testParsesShortVersionString() {
        let xml = """
        <?xml version="1.0" encoding="utf-8"?>
        <rss xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle" version="2.0">
          <channel>
            <title>Test</title>
            <item>
              <enclosure
                url="https://example.com/Foo.zip"
                sparkle:shortVersionString="2.5.1"
                sparkle:version="2510"
                length="1000000" type="application/octet-stream"/>
            </item>
          </channel>
        </rss>
        """
        let parser = AppcastParser()
        let version = parser.parseLatestVersion(from: xml.data(using: .utf8)!)
        XCTAssertEqual(version, "2.5.1")
    }

    func testFallsBackToVersionWhenNoShort() {
        let xml = """
        <?xml version="1.0" encoding="utf-8"?>
        <rss xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
          <channel>
            <item>
              <enclosure url="https://example.com/A.zip" sparkle:version="42"/>
            </item>
          </channel>
        </rss>
        """
        let parser = AppcastParser()
        XCTAssertEqual(parser.parseLatestVersion(from: xml.data(using: .utf8)!), "42")
    }

    func testReturnsNilOnEmptyXML() {
        let parser = AppcastParser()
        XCTAssertNil(parser.parseLatestVersion(from: Data()))
    }

    func testReturnsNilOnNonAppcastXML() {
        let xml = "<root><foo>bar</foo></root>"
        let parser = AppcastParser()
        XCTAssertNil(parser.parseLatestVersion(from: xml.data(using: .utf8)!))
    }

    func testPicksHighestVersionWhenNewestListedFirst() {
        let xml = """
        <rss xmlns:sparkle="ns">
          <channel>
            <item><enclosure url="x" sparkle:shortVersionString="3.0"/></item>
            <item><enclosure url="x" sparkle:shortVersionString="2.0"/></item>
          </channel>
        </rss>
        """
        let parser = AppcastParser()
        XCTAssertEqual(parser.parseLatestVersion(from: xml.data(using: .utf8)!), "3.0")
    }

    // Regression for #105: Sparkle feeds are not guaranteed newest-first. The
    // parser must return the HIGHEST version, not the first item.
    func testPicksHighestVersionWhenOldestListedFirst() {
        let xml = """
        <rss xmlns:sparkle="ns">
          <channel>
            <item><enclosure url="https://e/old.zip" sparkle:shortVersionString="3.4"/></item>
            <item><enclosure url="https://e/new.zip" sparkle:shortVersionString="3.6.8"/></item>
          </channel>
        </rss>
        """
        let parser = AppcastParser()
        XCTAssertEqual(parser.parseLatestVersion(from: xml.data(using: .utf8)!), "3.6.8")
    }

    func testPicksHighestVersionAndItsDownloadURL() {
        let xml = """
        <rss xmlns:sparkle="ns">
          <channel>
            <item><enclosure url="https://e/old.zip" sparkle:shortVersionString="3.4"/></item>
            <item><enclosure url="https://e/new.zip" sparkle:shortVersionString="3.6.8"/></item>
          </channel>
        </rss>
        """
        let parser = AppcastParser()
        let result = parser.parseLatestItem(from: xml.data(using: .utf8)!)
        XCTAssertEqual(result.version, "3.6.8")
        XCTAssertEqual(result.downloadURL?.absoluteString, "https://e/new.zip")
    }

    func testParserIsReusable() {
        let parser = AppcastParser()
        let xml1 = "<rss xmlns:sparkle=\"ns\"><channel><item><enclosure sparkle:shortVersionString=\"1.0\"/></item></channel></rss>"
        let xml2 = "<rss xmlns:sparkle=\"ns\"><channel><item><enclosure sparkle:shortVersionString=\"2.0\"/></item></channel></rss>"
        XCTAssertEqual(parser.parseLatestVersion(from: xml1.data(using: .utf8)!), "1.0")
        XCTAssertEqual(parser.parseLatestVersion(from: xml2.data(using: .utf8)!), "2.0")
    }
}
