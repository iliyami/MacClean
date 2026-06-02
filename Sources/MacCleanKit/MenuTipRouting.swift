import Foundation

/// Maps a menu-bar Tip id to the main app's sidebar module deep-link id.
/// Keep in sync with the tip ids produced by `TipsEngine`.
public enum MenuTipRouting {
    public static func moduleID(forTipID id: String) -> String? {
        switch id {
        case "trash_large": "trash-bins"
        case "caches_large": "system-junk"
        default: nil
        }
    }
}
