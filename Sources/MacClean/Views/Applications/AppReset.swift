import Foundation
import MacCleanKit

/// Pure reset-to-defaults plan, kept out of the view so it's testable.
///
/// Issue #52: the Uninstaller's Reset button used to only clear UI selection.
/// This builds the clean plan for a real reset: selected leftovers that
/// `AppResetPolicy` marks resetable. The `.app` bundle is never included.
enum AppReset {
    /// Returns `nil` when nothing selected is resetable (button should be disabled).
    static func plan(
        app: AppInfo,
        associatedFiles: [FileItem],
        selectedFiles: Set<URL>
    ) -> (items: [FileItem], selection: Set<URL>)? {
        let items = AppResetPolicy.resetableItems(
            from: associatedFiles,
            selected: selectedFiles,
            appBundle: app.path
        )
        guard !items.isEmpty else { return nil }
        return (items, Set(items.map(\.url)))
    }
}
