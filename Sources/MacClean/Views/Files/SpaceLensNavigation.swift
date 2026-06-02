import Foundation

/// Pure navigation state for SpaceLens drill-down ("zoom"). SwiftUI-free so
/// the back/up/home logic is unit-testable.
struct SpaceLensNavigation: Equatable {
    private(set) var breadcrumbs: [URL]

    init(root: URL) { breadcrumbs = [root] }

    // Invariant: `breadcrumbs` is never empty — seeded with the root in
    // init and no method ever removes the last element (up() guards count>1,
    // home() resets to [root]).
    var current: URL { breadcrumbs.last! }
    var canGoUp: Bool { breadcrumbs.count > 1 }

    mutating func drillInto(_ url: URL) { breadcrumbs.append(url) }
    mutating func up() { if breadcrumbs.count > 1 { breadcrumbs.removeLast() } }
    mutating func home() { if let root = breadcrumbs.first { breadcrumbs = [root] } }
    mutating func navigate(to url: URL) {
        if let i = breadcrumbs.firstIndex(of: url) { breadcrumbs = Array(breadcrumbs.prefix(through: i)) }
    }
}
