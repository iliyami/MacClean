import XCTest
import Foundation
@testable import MacClean
@testable import MacCleanKit
import MacCleanTestSupport

// MARK: - HandlerEntry Tests

final class HandlerEntryTests: XCTestCase {
    func testFileTypeDescriptionWithContentType() {
        let entry = HandlerEntry(id: UUID(), contentType: "public.jpeg", contentTag: nil, contentTagClass: nil, roleAll: "com.apple.Preview", urlScheme: nil, modificationDate: nil)
        XCTAssertEqual(entry.fileTypeDescription, "public.jpeg")
    }

    func testFileTypeDescriptionWithExtension() {
        let entry = HandlerEntry(id: UUID(), contentType: nil, contentTag: "txt", contentTagClass: "filename-extension", roleAll: "com.apple.TextEdit", urlScheme: nil, modificationDate: nil)
        XCTAssertEqual(entry.fileTypeDescription, ".txt")
    }

    func testFileTypeDescriptionWithURLScheme() {
        let entry = HandlerEntry(id: UUID(), contentType: nil, contentTag: nil, contentTagClass: nil, roleAll: nil, urlScheme: "https", modificationDate: nil)
        XCTAssertEqual(entry.fileTypeDescription, "https://")
    }

    func testFileTypeDescriptionWithGenericTag() {
        let entry = HandlerEntry(id: UUID(), contentType: nil, contentTag: "public.foo", contentTagClass: "public.type", roleAll: "com.example.App", urlScheme: nil, modificationDate: nil)
        XCTAssertEqual(entry.fileTypeDescription, "public.foo")
    }

    func testFileTypeDescriptionUnknown() {
        let entry = HandlerEntry(id: UUID(), contentType: nil, contentTag: nil, contentTagClass: nil, roleAll: nil, urlScheme: nil, modificationDate: nil)
        XCTAssertEqual(entry.fileTypeDescription, "Unknown")
    }

    func testAppBundleIdentifierReturnsRoleAll() {
        let entry = HandlerEntry(id: UUID(), contentType: nil, contentTag: nil, contentTagClass: nil, roleAll: "com.apple.Safari", urlScheme: nil, modificationDate: nil)
        XCTAssertEqual(entry.appBundleIdentifier, "com.apple.Safari")
    }

    func testAppBundleIdentifierNilWhenRoleAllNil() {
        let entry = HandlerEntry(id: UUID(), contentType: nil, contentTag: nil, contentTagClass: nil, roleAll: nil, urlScheme: "https", modificationDate: nil)
        XCTAssertNil(entry.appBundleIdentifier)
    }
}

// MARK: - LaunchServicesService Tests

final class LaunchServicesServiceTests: XCTestCase {
    func testLoadHandlersEmptyWhenFileMissing() {
        let tmp = FileManager.default.temporaryDirectory.appending(path: "no-such-file-\(UUID().uuidString).plist")
        defer { try? FileManager.default.removeItem(at: tmp) }
        let service = LaunchServicesService(plistPath: tmp.path)
        let handlers = service.loadHandlers()
        XCTAssertTrue(handlers.isEmpty)
    }

    func testSaveAndLoadRoundTrip() throws {
        try TestFixtures.withTempDir { dir in
            let plistURL = dir.appending(path: "launchservices.plist")
            let service = LaunchServicesService(plistPath: plistURL.path)

            // Create test handlers
            let handlers: [HandlerEntry] = [
                HandlerEntry(
                    id: UUID(),
                    contentType: "public.plain-text",
                    contentTag: "txt",
                    contentTagClass: "filename-extension",
                    roleAll: "com.apple.TextEdit",
                    urlScheme: nil,
                    modificationDate: Date(timeIntervalSince1970: 1_700_000_000)
                ),
                HandlerEntry(
                    id: UUID(),
                    contentType: nil,
                    contentTag: nil,
                    contentTagClass: nil,
                    roleAll: nil,
                    urlScheme: "https",
                    modificationDate: nil
                ),
            ]

            try service.saveHandlers(handlers)

            // Reload and verify
            let loaded = service.loadHandlers()
            XCTAssertEqual(loaded.count, 2)

            let textHandler = loaded.first { $0.contentType == "public.plain-text" }
            XCTAssertNotNil(textHandler)
            XCTAssertEqual(textHandler?.contentTag, "txt")
            XCTAssertEqual(textHandler?.contentTagClass, "filename-extension")
            XCTAssertEqual(textHandler?.roleAll, "com.apple.TextEdit")
            XCTAssertNil(textHandler?.urlScheme)
            XCTAssertNotNil(textHandler?.modificationDate)

            let httpsHandler = loaded.first { $0.urlScheme == "https" }
            XCTAssertNotNil(httpsHandler)
            XCTAssertNil(httpsHandler?.contentType)
            XCTAssertNil(httpsHandler?.contentTag)
            XCTAssertNil(httpsHandler?.modificationDate)
        }
    }

    func testLoadSkipsEntriesWithoutRoleOrURLScheme() throws {
        try TestFixtures.withTempDir { dir in
            let plistURL = dir.appending(path: "launchservices.plist")
            let plistData: [String: Any] = [
                "LSHandlers": [
                    // Valid entry
                    [
                        "LSHandlerContentType": "public.foo",
                        "LSHandlerRoleAll": "com.example.App",
                    ] as [String: Any],
                    // Invalid entry (no roleAll, no urlScheme) — should be skipped
                    [
                        "LSHandlerContentType": "public.bar",
                    ] as [String: Any],
                ] as [[String: Any]]
            ]
            try TestFixtures.writePlist(plistData, to: plistURL)

            let service = LaunchServicesService(plistPath: plistURL.path)
            let handlers = service.loadHandlers()
            XCTAssertEqual(handlers.count, 1)
            XCTAssertEqual(handlers.first?.contentType, "public.foo")
        }
    }

    func testSaveWithoutModificationDate() throws {
        try TestFixtures.withTempDir { dir in
            let plistURL = dir.appending(path: "launchservices.plist")
            let service = LaunchServicesService(plistPath: plistURL.path)

            let handlers: [HandlerEntry] = [
                HandlerEntry(
                    id: UUID(),
                    contentType: nil,
                    contentTag: nil,
                    contentTagClass: nil,
                    roleAll: nil,
                    urlScheme: "mailto",
                    modificationDate: nil
                ),
            ]

            try service.saveHandlers(handlers)
            let loaded = service.loadHandlers()
            XCTAssertEqual(loaded.count, 1)
            XCTAssertEqual(loaded.first?.urlScheme, "mailto")
        }
    }

    func testEmptyHandlersList() throws {
        try TestFixtures.withTempDir { dir in
            let plistURL = dir.appending(path: "launchservices.plist")
            let service = LaunchServicesService(plistPath: plistURL.path)

            try service.saveHandlers([])
            let loaded = service.loadHandlers()
            XCTAssertTrue(loaded.isEmpty)
        }
    }
}

// MARK: - FileHandlerViewModel Tests

@MainActor
final class FileHandlerViewModelTests: XCTestCase {
    func testFilteredHandlersReturnsAllWhenSearchEmpty() {
        let vm = FileHandlerViewModel()
        vm.handlers = [
            HandlerEntry(id: UUID(), contentType: "public.jpeg", contentTag: nil, contentTagClass: nil, roleAll: "com.apple.Preview", urlScheme: nil, modificationDate: nil),
            HandlerEntry(id: UUID(), contentType: nil, contentTag: "txt", contentTagClass: "filename-extension", roleAll: "com.apple.TextEdit", urlScheme: nil, modificationDate: nil),
        ]
        vm.searchText = ""
        XCTAssertEqual(vm.filteredHandlers.count, 2)
    }

    func testFilteredHandlersSearchByFileType() {
        let vm = FileHandlerViewModel()
        vm.handlers = [
            HandlerEntry(id: UUID(), contentType: "public.jpeg", contentTag: nil, contentTagClass: nil, roleAll: "com.apple.Preview", urlScheme: nil, modificationDate: nil),
            HandlerEntry(id: UUID(), contentType: "public.plain-text", contentTag: nil, contentTagClass: nil, roleAll: "com.apple.TextEdit", urlScheme: nil, modificationDate: nil),
        ]
        vm.searchText = "jpeg"
        XCTAssertEqual(vm.filteredHandlers.count, 1)
        XCTAssertEqual(vm.filteredHandlers.first?.contentType, "public.jpeg")
    }

    func testFilteredHandlersSearchByExtension() {
        let vm = FileHandlerViewModel()
        vm.handlers = [
            HandlerEntry(id: UUID(), contentType: nil, contentTag: "txt", contentTagClass: "filename-extension", roleAll: "com.apple.TextEdit", urlScheme: nil, modificationDate: nil),
            HandlerEntry(id: UUID(), contentType: nil, contentTag: "pdf", contentTagClass: "filename-extension", roleAll: "com.apple.Preview", urlScheme: nil, modificationDate: nil),
        ]
        vm.searchText = ".txt"
        XCTAssertEqual(vm.filteredHandlers.count, 1)
        XCTAssertEqual(vm.filteredHandlers.first?.contentTag, "txt")
    }

    func testFilteredHandlersSearchByURLScheme() {
        let vm = FileHandlerViewModel()
        vm.handlers = [
            HandlerEntry(id: UUID(), contentType: nil, contentTag: nil, contentTagClass: nil, roleAll: nil, urlScheme: "https", modificationDate: nil),
            HandlerEntry(id: UUID(), contentType: nil, contentTag: nil, contentTagClass: nil, roleAll: nil, urlScheme: "mailto", modificationDate: nil),
        ]
        vm.searchText = "https://"
        XCTAssertEqual(vm.filteredHandlers.count, 1)
        XCTAssertEqual(vm.filteredHandlers.first?.urlScheme, "https")
    }

    func testFilteredHandlersSearchByContentType() {
        let vm = FileHandlerViewModel()
        vm.handlers = [
            HandlerEntry(id: UUID(), contentType: "public.plain-text", contentTag: nil, contentTagClass: nil, roleAll: "com.apple.TextEdit", urlScheme: nil, modificationDate: nil),
            HandlerEntry(id: UUID(), contentType: "public.jpeg", contentTag: nil, contentTagClass: nil, roleAll: "com.apple.Preview", urlScheme: nil, modificationDate: nil),
        ]
        vm.searchText = "plain"
        XCTAssertEqual(vm.filteredHandlers.count, 1)
        XCTAssertEqual(vm.filteredHandlers.first?.contentType, "public.plain-text")
    }

    func testFilteredHandlersSearchByBundleID() {
        let vm = FileHandlerViewModel()
        vm.handlers = [
            HandlerEntry(id: UUID(), contentType: "public.foo", contentTag: nil, contentTagClass: nil, roleAll: "com.apple.Safari", urlScheme: nil, modificationDate: nil),
            HandlerEntry(id: UUID(), contentType: "public.bar", contentTag: nil, contentTagClass: nil, roleAll: "com.apple.TextEdit", urlScheme: nil, modificationDate: nil),
        ]
        vm.searchText = "safari"
        XCTAssertEqual(vm.filteredHandlers.count, 1)
        XCTAssertEqual(vm.filteredHandlers.first?.roleAll, "com.apple.Safari")
    }

    func testFilteredHandlersNoMatch() {
        let vm = FileHandlerViewModel()
        vm.handlers = [
            HandlerEntry(id: UUID(), contentType: "public.jpeg", contentTag: nil, contentTagClass: nil, roleAll: "com.apple.Preview", urlScheme: nil, modificationDate: nil),
        ]
        vm.searchText = "nonexistent"
        XCTAssertTrue(vm.filteredHandlers.isEmpty)
    }

    func testDeleteHandlerRemovesFromList() {
        let vm = FileHandlerViewModel()
        let h1 = HandlerEntry(id: UUID(), contentType: "public.foo", contentTag: nil, contentTagClass: nil, roleAll: "com.example.App1", urlScheme: nil, modificationDate: nil)
        let h2 = HandlerEntry(id: UUID(), contentType: "public.bar", contentTag: nil, contentTagClass: nil, roleAll: "com.example.App2", urlScheme: nil, modificationDate: nil)
        vm.handlers = [h1, h2]

        vm.deleteHandler(h1)
        XCTAssertEqual(vm.handlers.count, 1)
        XCTAssertEqual(vm.handlers.first?.roleAll, "com.example.App2")
    }

    func testDeleteHandlerNoOpForMissingHandler() {
        let vm = FileHandlerViewModel()
        let h1 = HandlerEntry(id: UUID(), contentType: "public.foo", contentTag: nil, contentTagClass: nil, roleAll: "com.example.App", urlScheme: nil, modificationDate: nil)
        vm.handlers = [h1]

        let missing = HandlerEntry(id: UUID(), contentType: "public.bar", contentTag: nil, contentTagClass: nil, roleAll: "com.example.Missing", urlScheme: nil, modificationDate: nil)
        vm.deleteHandler(missing)
        // Should not crash and count stays the same
        XCTAssertEqual(vm.handlers.count, 1)
    }
}
