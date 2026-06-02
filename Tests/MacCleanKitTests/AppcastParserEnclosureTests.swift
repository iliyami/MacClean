import XCTest
@testable import MacCleanKit

final class AppcastParserEnclosureTests: XCTestCase {
    func testParsesVersionAndDownloadURL() {
        let xml = """
        <rss xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
          <channel><item>
            <enclosure url="https://example.com/App-4.3.dmg"
                       sparkle:shortVersionString="4.3"
                       sparkle:version="4300" length="123" type="application/octet-stream"/>
          </item></channel>
        </rss>
        """
        let parsed = AppcastParser().parseLatestItem(from: Data(xml.utf8))
        XCTAssertEqual(parsed.version, "4.3")
        XCTAssertEqual(parsed.downloadURL, URL(string: "https://example.com/App-4.3.dmg"))
    }
}
