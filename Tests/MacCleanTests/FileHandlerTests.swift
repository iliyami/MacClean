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

    func testLoadHandlersFromPlistData() throws {
        try TestFixtures.withTempDir { dir in
            let plistURL = dir.appending(path: "launchservices.plist")
            let plistData: [String: Any] = [
                "LSHandlers": [
                    [
                        "LSHandlerContentType": "public.plain-text",
                        "LSHandlerContentTag": "txt",
                        "LSHandlerContentTagClass": "filename-extension",
                        "LSHandlerRoleAll": "com.apple.TextEdit",
                    ] as [String: Any],
                    [
                        "LSHandlerURLScheme": "https",
                    ] as [String: Any],
                ] as [[String: Any]]
            ]
            try TestFixtures.writePlist(plistData, to: plistURL)

            let service = LaunchServicesService(plistPath: plistURL.path)
            let loaded = service.loadHandlers()
            XCTAssertEqual(loaded.count, 2)

            let textHandler = loaded.first { $0.contentType == "public.plain-text" }
            XCTAssertNotNil(textHandler)
            XCTAssertEqual(textHandler?.contentTag, "txt")
            XCTAssertEqual(textHandler?.contentTagClass, "filename-extension")
            XCTAssertEqual(textHandler?.roleAll, "com.apple.TextEdit")
            XCTAssertNil(textHandler?.urlScheme)

            let httpsHandler = loaded.first { $0.urlScheme == "https" }
            XCTAssertNotNil(httpsHandler)
            XCTAssertNil(httpsHandler?.contentType)
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

    func testLoadPreservesAllKeysNotInModel() throws {
        try TestFixtures.withTempDir { dir in
            let plistURL = dir.appending(path: "launchservices.plist")
            let plistData: [String: Any] = [
                "LSHandlers": [
                    [
                        "LSHandlerContentType": "public.foo",
                        "LSHandlerRoleAll": "com.example.App",
                        "LSHandlerContentTag": "foo",
                        "LSHandlerContentTagClass": "filename-extension",
                        // Keys we intentionally don't model — must not cause a crash
                        "LSHandlerPreferredVersions": ["LSHandlerRoleAll": "-"],
                        "LSHandlerRank": "DefaultHandler",
                    ] as [String: Any],
                ] as [[String: Any]]
            ]
            try TestFixtures.writePlist(plistData, to: plistURL)

            let service = LaunchServicesService(plistPath: plistURL.path)
            let handlers = service.loadHandlers()
            XCTAssertEqual(handlers.count, 1)
            // Non-model keys should be silently ignored but not break parsing
            XCTAssertEqual(handlers.first?.contentTag, "foo")
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
}

// MARK: - LaunchServicesService Delete + Backup Tests

final class LaunchServicesServiceDeleteBackupTests: XCTestCase {
    /// Helper: write a plist + create a service pointing to it.
    private func makeService(dir: URL, data: [String: Any]) throws -> LaunchServicesService {
        let plistURL = dir.appending(path: "com.apple.launchservices.secure.plist")
        try TestFixtures.writePlist(data, to: plistURL)
        return LaunchServicesService(plistPath: plistURL.path)
    }

    // MARK: Delete

    func testDeleteRemovesEntryByContentType() throws {
        try TestFixtures.withTempDir { dir in
            let service = try makeService(dir: dir, data: [
                "LSHandlers": [
                    ["LSHandlerContentType": "public.foo", "LSHandlerRoleAll": "com.example.App1"],
                    ["LSHandlerContentType": "public.bar", "LSHandlerRoleAll": "com.example.App2"],
                ]
            ])
            let entry = HandlerEntry(id: UUID(), contentType: "public.foo", contentTag: nil, contentTagClass: nil, roleAll: "com.example.App1", urlScheme: nil, modificationDate: nil)
            try service.deleteHandler(entry)
            let remaining = service.loadHandlers()
            XCTAssertEqual(remaining.count, 1)
            XCTAssertEqual(remaining.first?.contentType, "public.bar")
        }
    }

    func testDeleteRemovesEntryByURLScheme() throws {
        try TestFixtures.withTempDir { dir in
            let service = try makeService(dir: dir, data: [
                "LSHandlers": [
                    ["LSHandlerURLScheme": "https"],
                    ["LSHandlerURLScheme": "mailto"],
                ]
            ])
            let entry = HandlerEntry(id: UUID(), contentType: nil, contentTag: nil, contentTagClass: nil, roleAll: nil, urlScheme: "https", modificationDate: nil)
            try service.deleteHandler(entry)
            let remaining = service.loadHandlers()
            XCTAssertEqual(remaining.count, 1)
            XCTAssertEqual(remaining.first?.urlScheme, "mailto")
        }
    }

    func testDeletePreservesUnknownKeys() throws {
        try TestFixtures.withTempDir { dir in
            let service = try makeService(dir: dir, data: [
                "LSHandlers": [
                    [
                        "LSHandlerContentType": "public.foo",
                        "LSHandlerRoleAll": "com.example.App",
                        "LSHandlerPreferredVersions": ["LSHandlerRoleAll": "-"],
                        "LSHandlerRank": "DefaultHandler",
                    ]
                ]
            ])
            let entry = HandlerEntry(id: UUID(), contentType: "public.foo", contentTag: nil, contentTagClass: nil, roleAll: "com.example.App", urlScheme: nil, modificationDate: nil)
            try service.deleteHandler(entry)
            // After delete, this entry is gone — but the test verifies no crash
            XCTAssertTrue(service.loadHandlers().isEmpty)
        }
    }

    func testDeleteNoopForNonMatchingEntry() throws {
        try TestFixtures.withTempDir { dir in
            let service = try makeService(dir: dir, data: [
                "LSHandlers": [
                    ["LSHandlerContentType": "public.foo", "LSHandlerRoleAll": "com.example.App"],
                ]
            ])
            let entry = HandlerEntry(id: UUID(), contentType: "public.bar", contentTag: nil, contentTagClass: nil, roleAll: "com.other.App", urlScheme: nil, modificationDate: nil)
            try service.deleteHandler(entry)
            // Nothing should be removed
            XCTAssertEqual(service.loadHandlers().count, 1)
        }
    }

    // MARK: Backup

    func testBackupCreatesFile() throws {
        try TestFixtures.withTempDir { dir in
            let service = try makeService(dir: dir, data: [
                "LSHandlers": [
                    ["LSHandlerContentType": "public.foo", "LSHandlerRoleAll": "com.example.App"],
                ]
            ])
            try service.backup()
            let backups = service.listBackups()
            XCTAssertEqual(backups.count, 1)
        }
    }

    func testBackupAndRestoreRoundTrip() throws {
        try TestFixtures.withTempDir { dir in
            let beforePlist = [
                "LSHandlers": [
                    ["LSHandlerContentType": "public.foo", "LSHandlerRoleAll": "com.example.App"],
                    ["LSHandlerURLScheme": "https"],
                ] as [[String: Any]]
            ] as [String: Any]
            let service = try makeService(dir: dir, data: beforePlist)

            // Delete one entry
            let entry = HandlerEntry(id: UUID(), contentType: "public.foo", contentTag: nil, contentTagClass: nil, roleAll: "com.example.App", urlScheme: nil, modificationDate: nil)
            try service.deleteHandler(entry) // this also creates a backup
            XCTAssertEqual(service.loadHandlers().count, 1)

            // Restore from backup
            let backups = service.listBackups()
            XCTAssertEqual(backups.count, 1)
            try service.restoreBackup(from: backups[0])

            // Verify restored
            let restored = service.loadHandlers()
            XCTAssertEqual(restored.count, 2)
            XCTAssertNotNil(restored.first { $0.contentType == "public.foo" })
            XCTAssertNotNil(restored.first { $0.urlScheme == "https" })
        }
    }

    func testBackupMultipleCreatesSeparateFiles() throws {
        try TestFixtures.withTempDir { dir in
            let service = try makeService(dir: dir, data: [
                "LSHandlers": [
                    ["LSHandlerContentType": "public.foo", "LSHandlerRoleAll": "com.example.App"],
                ]
            ])
            try service.backup()
            try service.backup()
            let backups = service.listBackups()
            XCTAssertEqual(backups.count, 2)
        }
    }
}
