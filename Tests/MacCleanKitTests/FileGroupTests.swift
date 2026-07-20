import XCTest
import Foundation
@testable import MacCleanKit

final class FileGroupTests: EnglishAppLanguageTestCase {

    private func makeFile(_ name: String, size: UInt64 = 0, mod: Date? = nil) -> FileItem {
        FileItem(
            url: URL(filePath: "/\(name)"),
            name: name, size: size, allocatedSize: size,
            isDirectory: false, modificationDate: mod
        )
    }

    // MARK: - fileTypeLabel

    func testVideoTypesLabeledVideos() {
        for ext in ["mp4", "mov", "avi", "mkv"] {
            XCTAssertEqual(FileGroup.fileTypeLabel(ext), "Videos", "extension '\(ext)' should be Videos")
        }
    }

    func testAudioTypesLabeledAudio() {
        for ext in ["mp3", "wav", "flac", "aac"] {
            XCTAssertEqual(FileGroup.fileTypeLabel(ext), "Audio")
        }
    }

    func testImageTypesLabeledImages() {
        for ext in ["jpg", "jpeg", "png", "heic"] {
            XCTAssertEqual(FileGroup.fileTypeLabel(ext), "Images")
        }
    }

    func testUnknownTypeIsOther() {
        XCTAssertEqual(FileGroup.fileTypeLabel("xyz"), "Other")
        XCTAssertEqual(FileGroup.fileTypeLabel(""), "Other")
    }

    // MARK: - ageLabel

    func testAgeLabels() {
        XCTAssertEqual(FileGroup.ageLabel(days: 0), "Last month")
        XCTAssertEqual(FileGroup.ageLabel(days: 25), "Last month")
        XCTAssertEqual(FileGroup.ageLabel(days: 31), "1 - 3 months")
        XCTAssertEqual(FileGroup.ageLabel(days: 91), "3 - 6 months")
        XCTAssertEqual(FileGroup.ageLabel(days: 181), "6 months - 1 year")
        XCTAssertEqual(FileGroup.ageLabel(days: 400), "Over 1 year")
    }

    // MARK: - group by size

    func testGroupBySize_1GBBucket() {
        let big = makeFile("big.mov", size: 2 * 1024 * 1024 * 1024) // 2 GB
        let groups = FileGroup.bySize.group([big])
        XCTAssertEqual(groups.first?.0, "1 GB+")
        XCTAssertEqual(groups.first?.1.count, 1)
    }

    func testGroupBySize_500MBBucket() {
        let file = makeFile("file.zip", size: 700 * 1024 * 1024) // 700 MB
        let groups = FileGroup.bySize.group([file])
        XCTAssertTrue(groups.contains(where: { $0.0 == "500 MB - 1 GB" }))
    }

    func testGroupBySize_50MBBucket() {
        let file = makeFile("file.zip", size: 60 * 1024 * 1024)
        let groups = FileGroup.bySize.group([file])
        XCTAssertTrue(groups.contains(where: { $0.0 == "50 - 100 MB" }))
    }

    func testGroupBySize_emptyBucketsDropped() {
        let file = makeFile("file.zip", size: 100 * 1024 * 1024)
        let groups = FileGroup.bySize.group([file])
        // Only one bucket has data
        XCTAssertEqual(groups.count, 1)
    }

    // MARK: - group by type

    func testGroupByType_mixedExtensions() {
        let files = [
            makeFile("a.mp4"), makeFile("b.mov"),
            makeFile("c.mp3"), makeFile("d.pdf"),
        ]
        let groups = FileGroup.byType.group(files)
        let dict = Dictionary(uniqueKeysWithValues: groups.map { ($0.0, $0.1.count) })
        XCTAssertEqual(dict["Videos"], 2)
        XCTAssertEqual(dict["Audio"], 1)
        XCTAssertEqual(dict["PDFs"], 1)
    }

    // MARK: - group by age

    func testGroupByAge_recentFile() {
        let now = Date()
        let recent = makeFile("recent.txt", mod: now.addingTimeInterval(-3 * 24 * 3600))
        let groups = FileGroup.byAge.group([recent], now: now)
        XCTAssertTrue(groups.contains(where: { $0.0 == "Last month" }))
    }

    func testGroupByAge_oldFile() {
        let now = Date()
        let old = makeFile("old.txt", mod: now.addingTimeInterval(-400 * 24 * 3600))
        let groups = FileGroup.byAge.group([old], now: now)
        XCTAssertTrue(groups.contains(where: { $0.0 == "Over 1 year" }))
    }

    func testGroupByAge_skipsFilesWithoutModDate() {
        let noDate = makeFile("nodate.txt")
        let groups = FileGroup.byAge.group([noDate])
        XCTAssertTrue(groups.allSatisfy { $0.1.isEmpty })
    }
}
