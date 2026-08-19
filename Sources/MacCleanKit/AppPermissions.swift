import Foundation

/// The five privacy services issue #49 asks to surface. TCC service IDs and
/// System Settings URL fragments are implementation details of macOS; the
/// FDA fragment matches `PermissionManager`.
public enum PrivacyPermission: String, CaseIterable, Sendable, Identifiable {
    case camera
    case microphone
    case fullDiskAccess
    case screenRecording
    case automation

    public var id: String { rawValue }

    public var tccServiceIDs: Set<String> {
        switch self {
        case .camera: ["kTCCServiceCamera"]
        case .microphone: ["kTCCServiceMicrophone"]
        case .fullDiskAccess: ["kTCCServiceSystemPolicyAllFiles"]
        case .screenRecording: ["kTCCServiceScreenCapture"]
        case .automation: ["kTCCServiceAppleEvents"]
        }
    }

    public var settingsFragment: String {
        switch self {
        case .camera: "Privacy_Camera"
        case .microphone: "Privacy_Microphone"
        case .fullDiskAccess: "Privacy_AllFiles"
        case .screenRecording: "Privacy_ScreenCapture"
        case .automation: "Privacy_Automation"
        }
    }

    public static func matching(service: String) -> PrivacyPermission? {
        allCases.first { $0.tccServiceIDs.contains(service) }
    }
}

public enum AppPermissionsSettings {
    public static let schemePrefix = "x-apple.systempreferences:com.apple.preference.security?"

    public static func url(for permission: PrivacyPermission) -> URL {
        URL(string: schemePrefix + permission.settingsFragment)!
    }
}

public struct TCCAccessRow: Equatable, Sendable {
    public var service: String
    public var client: String
    public var clientType: Int
    public var authValue: Int
    public var indirectObjectIdentifier: String?

    public init(
        service: String,
        client: String,
        clientType: Int,
        authValue: Int,
        indirectObjectIdentifier: String?
    ) {
        self.service = service
        self.client = client
        self.clientType = clientType
        self.authValue = authValue
        self.indirectObjectIdentifier = indirectObjectIdentifier
    }
}

public struct AppPermissionGrant: Equatable, Hashable, Sendable, Identifiable {
    public var id: String {
        "\(permission.rawValue)|\(client)|\(indirectObjectIdentifier ?? "")"
    }

    public let permission: PrivacyPermission
    public let client: String
    public let clientIsPath: Bool
    public let isLimited: Bool
    public let indirectObjectIdentifier: String?

    public init(
        permission: PrivacyPermission,
        client: String,
        clientIsPath: Bool,
        isLimited: Bool,
        indirectObjectIdentifier: String?
    ) {
        self.permission = permission
        self.client = client
        self.clientIsPath = clientIsPath
        self.isLimited = isLimited
        self.indirectObjectIdentifier = indirectObjectIdentifier
    }
}

public enum TCCAccessParser {
    /// `auth_value`: 0 denied, 2 allowed, 3 limited (Big Sur+ schema).
    public static func grants(from rows: [TCCAccessRow]) -> [AppPermissionGrant] {
        var seen: Set<String> = []
        var result: [AppPermissionGrant] = []
        for row in rows {
            guard let permission = PrivacyPermission.matching(service: row.service) else { continue }
            guard row.authValue == 2 || row.authValue == 3 else { continue }
            let client = row.client.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !client.isEmpty else { continue }
            let grant = AppPermissionGrant(
                permission: permission,
                client: client,
                clientIsPath: row.clientType == 1,
                isLimited: row.authValue == 3,
                indirectObjectIdentifier: normalizedIndirect(row.indirectObjectIdentifier, permission: permission)
            )
            if seen.insert(grant.id).inserted {
                result.append(grant)
            }
        }
        return result
    }

    private static func normalizedIndirect(_ raw: String?, permission: PrivacyPermission) -> String? {
        guard permission == .automation else { return nil }
        guard let raw, !raw.isEmpty, raw != "UNUSED", raw != "NONE" else { return nil }
        return raw
    }
}

public struct AppPermissionApp: Equatable, Hashable, Sendable, Identifiable {
    public var id: String { "\(clientIsPath ? "path" : "bundle")|\(client)" }

    public let client: String
    public let clientIsPath: Bool
    public let grants: [AppPermissionGrant]

    public init(client: String, clientIsPath: Bool, grants: [AppPermissionGrant]) {
        self.client = client
        self.clientIsPath = clientIsPath
        self.grants = grants
    }

    /// Unique permissions on this app, in `PrivacyPermission.allCases` order.
    public var permissions: [PrivacyPermission] {
        PrivacyPermission.allCases.filter { permission in
            grants.contains { $0.permission == permission }
        }
    }
}

/// Groups TCC grants by app so the UI can show a by-app overview
/// (the view System Settings does not provide).
public enum AppPermissionOverview {
    public static func apps(from grants: [AppPermissionGrant]) -> [AppPermissionApp] {
        var buckets: [String: [AppPermissionGrant]] = [:]
        var meta: [String: (client: String, isPath: Bool)] = [:]
        for grant in grants {
            let key = "\(grant.clientIsPath ? "path" : "bundle")|\(grant.client)"
            buckets[key, default: []].append(grant)
            meta[key] = (grant.client, grant.clientIsPath)
        }
        let order = Dictionary(
            uniqueKeysWithValues: PrivacyPermission.allCases.enumerated().map { ($0.element, $0.offset) }
        )
        return buckets.keys.compactMap { key -> AppPermissionApp? in
            guard let info = meta[key], var list = buckets[key] else { return nil }
            list.sort { (order[$0.permission] ?? 99) < (order[$1.permission] ?? 99) }
            return AppPermissionApp(client: info.client, clientIsPath: info.isPath, grants: list)
        }
        .sorted { $0.client.localizedCaseInsensitiveCompare($1.client) == .orderedAscending }
    }
}
