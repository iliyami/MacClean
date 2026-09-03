import AppKit
import Foundation
import GRDB
import MacCleanKit

enum AppPermissionsListing: Equatable, Sendable {
    case loaded
    case needsFullDiskAccess
    case unavailable
}

struct AppPermissionsSnapshot: Equatable, Sendable {
    var grants: [AppPermissionGrant]
    var listing: AppPermissionsListing
}

struct AppPermissionsClient: Sendable {
    var userDatabaseURL: URL
    var systemDatabaseURL: URL
    var readRows: @Sendable (URL) throws -> [TCCAccessRow]
    var openURL: @Sendable (URL) -> Void

    static func live() -> AppPermissionsClient {
        let home = URL(filePath: NSHomeDirectory(), directoryHint: .isDirectory)
        return AppPermissionsClient(
            userDatabaseURL: home.appending(path: "Library/Application Support/com.apple.TCC/TCC.db"),
            systemDatabaseURL: URL(filePath: "/Library/Application Support/com.apple.TCC/TCC.db"),
            readRows: { url in try Self.readAccessRows(at: url) },
            openURL: { NSWorkspace.shared.open($0) }
        )
    }

    func load() async -> AppPermissionsSnapshot {
        var rows: [TCCAccessRow] = []
        var anySuccess = false
        var sawDenied = false
        for url in [userDatabaseURL, systemDatabaseURL] {
            do {
                rows.append(contentsOf: try readRows(url))
                anySuccess = true
            } catch {
                if Self.isPermissionDenied(error) {
                    sawDenied = true
                }
            }
        }
        let grants = TCCAccessParser.grants(from: rows)
        if anySuccess {
            return AppPermissionsSnapshot(grants: grants, listing: .loaded)
        }
        if sawDenied {
            return AppPermissionsSnapshot(grants: [], listing: .needsFullDiskAccess)
        }
        return AppPermissionsSnapshot(grants: [], listing: .unavailable)
    }

    func openSettings(for permission: PrivacyPermission) {
        openURL(AppPermissionsSettings.url(for: permission))
    }

    func openFullDiskAccessSettings() {
        openSettings(for: .fullDiskAccess)
    }

    private static func isPermissionDenied(_ error: Error) -> Bool {
        let ns = error as NSError
        if ns.domain == NSPOSIXErrorDomain, ns.code == Int(EPERM) || ns.code == Int(EACCES) {
            return true
        }
        if ns.domain == NSCocoaErrorDomain, ns.code == NSFileReadNoPermissionError {
            return true
        }
        if let dbError = error as? DatabaseError {
            let message = (dbError.message ?? "").lowercased()
            if message.contains("authorization denied") || message.contains("permission denied") {
                return true
            }
            if dbError.resultCode == .SQLITE_AUTH || dbError.resultCode == .SQLITE_CANTOPEN {
                return true
            }
        }
        return false
    }

    private static func readAccessRows(at url: URL) throws -> [TCCAccessRow] {
        var config = Configuration()
        config.readonly = true
        let db = try DatabaseQueue(path: url.path(percentEncoded: false), configuration: config)
        return try db.read { db in
            let withIndirect = """
                SELECT service, client, client_type, auth_value, indirect_object_identifier
                FROM access
                """
            do {
                return try Row.fetchAll(db, sql: withIndirect).map(rowToAccess)
            } catch {
                let withoutIndirect = "SELECT service, client, client_type, auth_value FROM access"
                return try Row.fetchAll(db, sql: withoutIndirect).map(rowToAccess)
            }
        }
    }

    private static func rowToAccess(_ row: Row) -> TCCAccessRow {
        let auth: Int
        if let value = row["auth_value"] as Int? {
            auth = value
        } else if let value = row["auth_value"] as Int64? {
            auth = Int(value)
        } else {
            auth = 0
        }
        let clientType: Int
        if let value = row["client_type"] as Int? {
            clientType = value
        } else if let value = row["client_type"] as Int64? {
            clientType = Int(value)
        } else {
            clientType = 0
        }
        return TCCAccessRow(
            service: row["service"] ?? "",
            client: row["client"] ?? "",
            clientType: clientType,
            authValue: auth,
            indirectObjectIdentifier: row["indirect_object_identifier"]
        )
    }
}
