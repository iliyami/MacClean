import Foundation
import AppKit

public final class LaunchServicesService: @unchecked Sendable {
    public static let shared = LaunchServicesService()

    private let plistPath: String

    private init() {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        plistPath = "\(home)/Library/Preferences/com.apple.LaunchServices/com.apple.launchservices.secure.plist"
    }

    public func loadHandlers() -> [HandlerEntry] {
        guard FileManager.default.fileExists(atPath: plistPath),
              let plistData = NSDictionary(contentsOfFile: plistPath),
              let handlers = plistData["LSHandlers"] as? [[String: Any]] else {
            return []
        }
        return handlers.compactMap { dict -> HandlerEntry? in
            var entry = HandlerEntry(id: UUID())
            entry.contentType = dict["LSHandlerContentType"] as? String
            entry.contentTag = dict["LSHandlerContentTag"] as? String
            entry.contentTagClass = dict["LSHandlerContentTagClass"] as? String
            entry.roleAll = dict["LSHandlerRoleAll"] as? String
            entry.urlScheme = dict["LSHandlerURLScheme"] as? String
            if let ts = dict["LSHandlerModificationDate"] as? Double {
                entry.modificationDate = Date(timeIntervalSince1970: ts)
            }
            if entry.roleAll == nil && entry.urlScheme == nil { return nil }
            return entry
        }
    }

    public func saveHandlers(_ handlers: [HandlerEntry]) throws {
        let arr: [[String: Any]] = handlers.map { entry in
            var dict: [String: Any] = [:]
            dict["LSHandlerContentType"] = entry.contentType
            dict["LSHandlerContentTag"] = entry.contentTag
            dict["LSHandlerContentTagClass"] = entry.contentTagClass
            dict["LSHandlerRoleAll"] = entry.roleAll
            dict["LSHandlerURLScheme"] = entry.urlScheme
            if let md = entry.modificationDate {
                dict["LSHandlerModificationDate"] = md.timeIntervalSince1970
            }
            dict["LSHandlerPreferredVersions"] = ["LSHandlerRoleAll": "-"]
            return dict
        }
        let plist: [String: Any] = ["LSHandlers": arr]
        let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        try data.write(to: URL(fileURLWithPath: plistPath))
    }

    public func getAppInfo(for bundleId: String?) -> (name: String, icon: NSImage)? {
        guard let bid = bundleId, !bid.isEmpty,
              let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bid) else {
            return nil
        }
        let name = FileManager.default.displayName(atPath: url.path)
        let icon = NSWorkspace.shared.icon(forFile: url.path)
        icon.size = NSSize(width: 32, height: 32)
        return (name, icon)
    }

    public func getURLSchemeAppInfo(for scheme: String?) -> (name: String, icon: NSImage)? {
        guard let s = scheme, !s.isEmpty,
              let url = URL(string: "\(s)://test"),
              let appURL = NSWorkspace.shared.urlForApplication(toOpen: url) else {
            return nil
        }
        let name = FileManager.default.displayName(atPath: appURL.path)
        let icon = NSWorkspace.shared.icon(forFile: appURL.path)
        icon.size = NSSize(width: 32, height: 32)
        return (name, icon)
    }
}
