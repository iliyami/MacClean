import Foundation
import MacCleanKit

public struct HandlerEntry: Identifiable, Equatable, Sendable {
    public let id: UUID
    public var contentType: String?
    public var contentTag: String?
    public var contentTagClass: String?
    public var roleAll: String?
    public var urlScheme: String?
    public var modificationDate: Date?

    public var fileTypeDescription: String {
        if let ct = contentType {
            return ct
        } else if let tag = contentTag, let cls = contentTagClass {
            if cls.contains("filename-extension") { return ".\(tag)" }
            return tag
        } else if let scheme = urlScheme {
            return "\(scheme)://"
        }
        return L10n.tr("未知", "Unknown", "Неизвестно")
    }

    public var appBundleIdentifier: String? { roleAll }
}
