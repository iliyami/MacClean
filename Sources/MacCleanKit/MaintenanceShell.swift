import Foundation

/// POSIX shell quoting for assembling the maintenance admin command that
/// `osascript`'s `do shell script` hands to `/bin/sh`. Wrapping each
/// argument in single quotes neutralises every shell metacharacter; the
/// only character that can't appear literally inside single quotes is the
/// single quote itself, handled with the standard close-escape-reopen idiom.
public enum MaintenanceShell {
    public static func quote(_ argument: String) -> String {
        "'" + argument.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    /// Quote an executable + its arguments into a single sh command line.
    public static func commandLine(_ executable: String, _ arguments: [String]) -> String {
        ([executable] + arguments).map(quote).joined(separator: " ")
    }

    /// Turn an osascript `do shell script` failure into the underlying message.
    ///
    /// osascript surfaces failures as `"<line>:<col>: execution error: <message>
    /// (<code>)"` — the cryptic `1:92: execution error: …` users saw in issue
    /// #82. Strip the offset prefix and the trailing AppleScript error code so
    /// the UI shows the real message (e.g. the actual `diskutil` complaint)
    /// instead of the wrapper. Non-osascript strings pass through unchanged.
    public static func humanReadableError(_ raw: String) -> String {
        var message = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        // Leading "[N:M: ]execution error: " — the line:col offset is optional.
        if let prefix = message.range(
            of: #"^(\d+:\d+:\s*)?execution error:\s*"#,
            options: .regularExpression
        ) {
            message.removeSubrange(prefix)
        }
        // Trailing " (<code>)" AppleScript error number.
        if let suffix = message.range(
            of: #"\s*\(-?\d+\)\s*$"#,
            options: .regularExpression
        ) {
            message.removeSubrange(suffix)
        }
        return message.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
