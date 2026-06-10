import Foundation

/// Declares the "leftovers from deleted apps" category. Like
/// `UniversalBinariesCategory`, this needs a system-side scanner (it enumerates
/// Library subdirs and reads installed bundle ids) rather than the targeted
/// path enumerator, so its `targets` are empty and `SystemJunkModule`
/// special-cases it to call `AppLeftoversScanner`. The orphan decision itself
/// is pure and lives in `OrphanedAppFiles`.
public struct AppLeftoversCategory: JunkCategory {
    public init() {}
    public let scanCategory = ScanCategory.appLeftovers
    public var targets: [ScanTarget] { [] }
}
