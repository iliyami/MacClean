import XCTest
import Foundation
@testable import MacCleanKit

final class FileTypeCategoryTests: EnglishAppLanguageTestCase {

    // MARK: - Directory detection

    func testDirectoryReturnsFoldersCategory() {
        XCTAssertEqual(FileTypeCategory.category(forFileExtension: "", isDirectory: true), .folders)
        XCTAssertEqual(FileTypeCategory.category(forFileExtension: "mp4", isDirectory: true), .folders)
        XCTAssertEqual(FileTypeCategory.category(forFileExtension: "pdf", isDirectory: true), .folders)
    }

    // MARK: - Video files

    func testVideoExtensions() {
        for ext in ["mp4", "mov", "avi", "mkv", "wmv", "flv", "webm"] {
            XCTAssertEqual(FileTypeCategory.category(forFileExtension: ext, isDirectory: false), .video,
                           "\(ext) should be .video")
        }
    }

    // MARK: - Audio files

    func testAudioExtensions() {
        for ext in ["mp3", "wav", "flac", "aac", "m4a", "ogg", "wma"] {
            XCTAssertEqual(FileTypeCategory.category(forFileExtension: ext, isDirectory: false), .audio,
                           "\(ext) should be .audio")
        }
    }

    // MARK: - Images

    func testImageExtensions() {
        for ext in ["jpg", "jpeg", "png", "gif", "bmp", "tiff", "heic", "webp"] {
            XCTAssertEqual(FileTypeCategory.category(forFileExtension: ext, isDirectory: false), .images,
                           "\(ext) should be .images")
        }
    }

    // MARK: - Documents

    func testDocumentExtensions() {
        for ext in ["pdf", "doc", "docx", "pages", "rtf", "txt", "odt",
                     "xls", "xlsx", "numbers", "csv", "ods",
                     "ppt", "pptx", "key"] {
            XCTAssertEqual(FileTypeCategory.category(forFileExtension: ext, isDirectory: false), .documents,
                           "\(ext) should be .documents")
        }
    }

    // MARK: - Archives

    func testArchiveExtensions() {
        for ext in ["zip", "gz", "tar", "rar", "7z", "bz2", "xz"] {
            XCTAssertEqual(FileTypeCategory.category(forFileExtension: ext, isDirectory: false), .archives,
                           "\(ext) should be .archives")
        }
    }

    // MARK: - Disk Images

    func testDiskImageExtensions() {
        for ext in ["dmg", "iso", "img", "sparseimage"] {
            XCTAssertEqual(FileTypeCategory.category(forFileExtension: ext, isDirectory: false), .diskImages,
                           "\(ext) should be .diskImages")
        }
    }

    // MARK: - Applications

    func testApplicationExtensions() {
        for ext in ["app", "pkg", "mpkg"] {
            XCTAssertEqual(FileTypeCategory.category(forFileExtension: ext, isDirectory: false), .applications,
                           "\(ext) should be .applications")
        }
    }

    // MARK: - Code

    func testCodeExtensions() {
        for ext in ["swift", "h", "m", "mm", "c", "cpp", "py", "js", "ts",
                     "java", "rs", "go", "rb", "php", "css", "html", "sh",
                     "json", "xml", "yaml", "toml", "plist", "entitlements"] {
            XCTAssertEqual(FileTypeCategory.category(forFileExtension: ext, isDirectory: false), .code,
                           "\(ext) should be .code")
        }
    }

    // MARK: - System

    func testSystemExtensions() {
        for ext in ["kext", "dylib", "framework", "bundle", "log", "cache", "db", "sqlite"] {
            XCTAssertEqual(FileTypeCategory.category(forFileExtension: ext, isDirectory: false), .system,
                           "\(ext) should be .system")
        }
    }

    // MARK: - Unknown / Other

    func testUnknownExtensionReturnsOther() {
        XCTAssertEqual(FileTypeCategory.category(forFileExtension: "xyz", isDirectory: false), .other)
        XCTAssertEqual(FileTypeCategory.category(forFileExtension: "abc123", isDirectory: false), .other)
        XCTAssertEqual(FileTypeCategory.category(forFileExtension: "", isDirectory: false), .other)
    }

    // MARK: - Case insensitivity

    func testCategoryIsCaseInsensitive() {
        XCTAssertEqual(FileTypeCategory.category(forFileExtension: "MP4", isDirectory: false), .video)
        XCTAssertEqual(FileTypeCategory.category(forFileExtension: "PDF", isDirectory: false), .documents)
        XCTAssertEqual(FileTypeCategory.category(forFileExtension: "ZIP", isDirectory: false), .archives)
    }

    // MARK: - Category labels

    func testCategoryLabels() {
        XCTAssertEqual(FileTypeCategory.folders.label, "Folders")
        XCTAssertEqual(FileTypeCategory.documents.label, "Documents")
        XCTAssertEqual(FileTypeCategory.images.label, "Images")
        XCTAssertEqual(FileTypeCategory.video.label, "Video")
        XCTAssertEqual(FileTypeCategory.audio.label, "Audio")
        XCTAssertEqual(FileTypeCategory.archives.label, "Archives")
        XCTAssertEqual(FileTypeCategory.code.label, "Code")
        XCTAssertEqual(FileTypeCategory.diskImages.label, "Disk Images")
        XCTAssertEqual(FileTypeCategory.applications.label, "Applications")
        XCTAssertEqual(FileTypeCategory.system.label, "System")
        XCTAssertEqual(FileTypeCategory.other.label, "Other")
    }

    // MARK: - All cases present

    func testAllCasesCovered() {
        // Every FileTypeCategory case should produce the right label
        let cases = FileTypeCategory.allCases
        XCTAssertEqual(cases.count, 11)
        XCTAssertTrue(cases.contains(.folders))
        XCTAssertTrue(cases.contains(.other))
    }
}
