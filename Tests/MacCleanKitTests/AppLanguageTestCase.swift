import Foundation
import XCTest

@testable import MacCleanKit

/// Restores both language preference stores exactly as they were before each
/// test. Saving only `AppLanguage.current` would turn an absent preference into
/// an explicit value during teardown and leak state into later test classes.
class AppLanguageTestCase: XCTestCase {
    private var sharedLanguage: String?
    private var standardLanguage: String?

    override func setUp() {
        super.setUp()
        sharedLanguage = SharedAppState.defaults.string(forKey: AppLanguage.defaultsKey)
        standardLanguage = UserDefaults.standard.string(forKey: AppLanguage.defaultsKey)
    }

    override func tearDown() {
        restore(sharedLanguage, in: SharedAppState.defaults)
        restore(standardLanguage, in: UserDefaults.standard)
        super.tearDown()
    }

    private func restore(_ value: String?, in defaults: UserDefaults) {
        if let value {
            defaults.set(value, forKey: AppLanguage.defaultsKey)
        } else {
            defaults.removeObject(forKey: AppLanguage.defaultsKey)
        }
    }
}

/// Base class for tests whose assertions intentionally describe English UI
/// copy, independently of the developer machine's system language or defaults.
class EnglishAppLanguageTestCase: AppLanguageTestCase {
    override func setUp() {
        super.setUp()
        AppLanguage.current = .en
    }
}
