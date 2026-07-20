import Foundation
import MacCleanKit
import XCTest

/// Keeps English-copy assertions independent of the host language and restores
/// both preference stores without converting a missing preference into `.en`.
class EnglishAppLanguageTestCase: XCTestCase {
    private var sharedLanguage: String?
    private var standardLanguage: String?

    override func setUp() {
        super.setUp()
        sharedLanguage = SharedAppState.defaults.string(forKey: AppLanguage.defaultsKey)
        standardLanguage = UserDefaults.standard.string(forKey: AppLanguage.defaultsKey)
        AppLanguage.current = .en
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
