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
}
