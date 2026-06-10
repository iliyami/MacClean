import XCTest
import Foundation
import UniformTypeIdentifiers
@testable import MacCleanKit

final class FileItemTests: XCTestCase {

    func testCreation() {
        let url = URL(filePath: "/tmp/test.txt")
        let item = FileItem(
            url: url, name: "test.txt",
            size: 1024, allocatedSize: 4096,
            isDirectory: false,
            contentType: .plainText,
            creationDate: Date(),
            modificationDate: Date()
        )
        XCTAssertEqual(item.name, "test.txt")
        XCTAssertEqual(item.size, 1024)
        XCTAssertEqual(item.allocatedSize, 4096)
        XCTAssertFalse(item.isDirectory)
        XCTAssertEqual(item.fileExtension, "txt")
    }

    func testFileExtensionLowercase() {
        let item = FileItem(url: URL(filePath: "/tmp/PHOTO.PNG"),
                            name: "PHOTO.PNG", size: 0, allocatedSize: 0,
                            isDirectory: false)
        XCTAssertEqual(item.fileExtension, "png")
    }

    func testAgeWhenModificationDateSet() {
        let pastDate = Date().addingTimeInterval(-3600)
        let item = FileItem(url: URL(filePath: "/tmp/old"), name: "old",
                            size: 0, allocatedSize: 0, isDirectory: false,
                            modificationDate: pastDate)
        XCTAssertNotNil(item.age)
        XCTAssertGreaterThan(item.age!, 3500)
    }

    func testAgeWhenNoModificationDate() {
        let item = FileItem(url: URL(filePath: "/tmp/new"), name: "new",
                            size: 0, allocatedSize: 0, isDirectory: false)
        XCTAssertNil(item.age)
    }

    func testFormattedSize() {
        let item = FileItem(url: URL(filePath: "/tmp/x"), name: "x",
                            size: 5 * 1024 * 1024, allocatedSize: 5 * 1024 * 1024,
                            isDirectory: false)
        XCTAssertTrue(item.formattedSize.contains("5"))
    }

    func testEqualityByURL() {
        let url = URL(filePath: "/tmp/same.txt")
        let a = FileItem(url: url, name: "x", size: 100, allocatedSize: 100, isDirectory: false)
        let b = FileItem(url: url, name: "y", size: 999, allocatedSize: 999, isDirectory: false)
        XCTAssertEqual(a, b, "FileItems with the same URL are equal regardless of other props")
    }

    func testInequalityByURL() {
        let a = FileItem(url: URL(filePath: "/a"), name: "a", size: 1, allocatedSize: 1, isDirectory: false)
        let b = FileItem(url: URL(filePath: "/b"), name: "b", size: 1, allocatedSize: 1, isDirectory: false)
        XCTAssertNotEqual(a, b)
    }

    func testHashableByURL() {
        let url = URL(filePath: "/tmp/x.txt")
        let a = FileItem(url: url, name: "x", size: 1, allocatedSize: 1, isDirectory: false)
        let b = FileItem(url: url, name: "y", size: 99, allocatedSize: 99, isDirectory: false)
        XCTAssertEqual(a.hashValue, b.hashValue)
    }
}

final class ScanResultTests: XCTestCase {

    func testTotalSize() {
        let items = (0..<5).map {
            FileItem(url: URL(filePath: "/\($0)"), name: "\($0)",
                     size: 100, allocatedSize: 100, isDirectory: false)
        }
        let r = ScanResult(category: .userCaches, items: items)
        XCTAssertEqual(r.totalSize, 500)
        XCTAssertEqual(r.fileCount, 5)
    }

    func testEmpty() {
        let r = ScanResult(category: .userCaches, items: [])
        XCTAssertEqual(r.totalSize, 0)
        XCTAssertEqual(r.fileCount, 0)
    }

    func testAutoSelectDefault() {
        let r = ScanResult(category: .userCaches, items: [])
        XCTAssertTrue(r.autoSelect)
    }

    func testAutoSelectOverridable() {
        let r = ScanResult(category: .duplicates, items: [], autoSelect: false)
        XCTAssertFalse(r.autoSelect)
    }
}

final class ModuleScanResultTests: XCTestCase {

    func testAggregation() {
        let g1 = [FileItem(url: URL(filePath: "/a"), name: "a", size: 500, allocatedSize: 500, isDirectory: false)]
        let g2 = [
            FileItem(url: URL(filePath: "/b"), name: "b", size: 300, allocatedSize: 300, isDirectory: false),
            FileItem(url: URL(filePath: "/c"), name: "c", size: 200, allocatedSize: 200, isDirectory: false),
        ]
        let m = ModuleScanResult(
            moduleID: "test", moduleName: "Test",
            categories: [
                ScanResult(category: .userCaches, items: g1),
                ScanResult(category: .userLogs, items: g2),
            ],
            scanDuration: 1.5
        )
        XCTAssertEqual(m.totalSize, 1000)
        XCTAssertEqual(m.totalFileCount, 3)
        XCTAssertFalse(m.formattedSize.isEmpty)
    }
}

final class AppInfoTests: XCTestCase {

    func testCreation() {
        let app = AppInfo(
            bundleIdentifier: "com.test.app", name: "Test",
            path: URL(filePath: "/Applications/Test.app"),
            version: "1.0", size: 50_000_000
        )
        XCTAssertEqual(app.bundleIdentifier, "com.test.app")
        XCTAssertEqual(app.name, "Test")
        XCTAssertEqual(app.version, "1.0")
        XCTAssertFalse(app.isAppleApp)
    }

    func testIsUnused() {
        let oldDate = Date().addingTimeInterval(-200 * 24 * 3600)
        let unused = AppInfo(bundleIdentifier: "com.unused", name: "U",
                             path: URL(filePath: "/u.app"), lastOpened: oldDate)
        XCTAssertTrue(unused.isUnused)

        let recent = AppInfo(bundleIdentifier: "com.recent", name: "R",
                             path: URL(filePath: "/r.app"), lastOpened: Date())
        XCTAssertFalse(recent.isUnused)

        let never = AppInfo(bundleIdentifier: "com.never", name: "N",
                            path: URL(filePath: "/n.app"))
        XCTAssertFalse(never.isUnused, "App with no lastOpened date should NOT be flagged as unused")
    }

    func testFormattedSize() {
        let app = AppInfo(
            bundleIdentifier: "x", name: "x",
            path: URL(filePath: "/x.app"), size: 50_000_000
        )
        XCTAssertTrue(app.formattedSize.contains("50") || app.formattedSize.contains("47"))
    }

    func testEqualityByBundleIDAndPath() {
        let a = AppInfo(bundleIdentifier: "com.test", name: "T",
                        path: URL(filePath: "/T.app"), version: "1")
        let b = AppInfo(bundleIdentifier: "com.test", name: "T",
                        path: URL(filePath: "/T.app"), version: "2")
        XCTAssertEqual(a, b)
    }

    func testInequalityByBundleID() {
        let a = AppInfo(bundleIdentifier: "com.x", name: "X",
                        path: URL(filePath: "/X.app"))
        let b = AppInfo(bundleIdentifier: "com.y", name: "X",
                        path: URL(filePath: "/X.app"))
        XCTAssertNotEqual(a, b)
    }
}

final class ScanCategoryEnumTests: XCTestCase {

    func testAllCasesNonEmpty() {
        XCTAssertGreaterThan(ScanCategory.allCases.count, 0)
    }

    func testAllHaveDistinctIDs() {
        let ids = ScanCategory.allCases.map(\.id)
        XCTAssertEqual(Set(ids).count, ids.count)
    }

    func testAllHaveDisplayNames() {
        for c in ScanCategory.allCases {
            XCTAssertFalse(c.displayName.isEmpty)
        }
    }

    func testAllHaveIcons() {
        for c in ScanCategory.allCases {
            XCTAssertFalse(c.systemImage.isEmpty)
        }
    }

    func testAutoSelectDefaults() {
        XCTAssertTrue(ScanCategory.userCaches.autoSelect)
        XCTAssertTrue(ScanCategory.systemCaches.autoSelect)
        XCTAssertFalse(ScanCategory.unusedDiskImages.autoSelect)
        XCTAssertFalse(ScanCategory.largeFiles.autoSelect)
        XCTAssertFalse(ScanCategory.duplicates.autoSelect)
    }
}

final class ConstantsTests: XCTestCase {

    func testProtectedPathsNotEmpty() {
        XCTAssertFalse(MCConstants.protectedPaths.isEmpty)
        // Critical paths
        XCTAssertTrue(MCConstants.protectedPaths.contains("/System"))
        XCTAssertTrue(MCConstants.protectedPaths.contains("/usr"))
        XCTAssertTrue(MCConstants.protectedPaths.contains("/bin"))
        XCTAssertTrue(MCConstants.protectedPaths.contains("/sbin"))
    }

    func testProtectedAppsHasCriticalApps() {
        XCTAssertTrue(MCConstants.protectedApps.contains("com.apple.finder"))
        XCTAssertTrue(MCConstants.protectedApps.contains("com.apple.Safari"))
        XCTAssertTrue(MCConstants.protectedApps.contains("com.apple.dt.Xcode"))
    }

    func testPreservedLanguagesContainsEnglish() {
        XCTAssertTrue(MCConstants.preservedLanguages.contains("en.lproj"))
        XCTAssertTrue(MCConstants.preservedLanguages.contains("Base.lproj"))
    }

    func testMaxFilesCap() {
        XCTAssertEqual(MCConstants.maxFilesPerOperation, 10_000)
    }

    func testOperationLogPathUnderUserLogs() {
        let logPath = MCConstants.operationLogFile.path(percentEncoded: false)
        let logsPath = MCConstants.userLogs.path(percentEncoded: false)
        XCTAssertTrue(logPath.hasPrefix(logsPath))
    }
}

final class FileSizeFormatterTests: XCTestCase {

    func testFormatNonEmpty() {
        XCTAssertFalse(FileSizeFormatter.format(UInt64(1024)).isEmpty)
    }

    func testFormatZero() {
        XCTAssertFalse(FileSizeFormatter.format(UInt64(0)).isEmpty)
    }

    func testShortFormat() {
        let r = FileSizeFormatter.shortFormat(UInt64(100 * 1024 * 1024))
        XCTAssertFalse(r.value.isEmpty)
        XCTAssertFalse(r.unit.isEmpty)
    }

    func testInt64Overload() {
        XCTAssertFalse(FileSizeFormatter.format(Int64(1024)).isEmpty)
    }
}
