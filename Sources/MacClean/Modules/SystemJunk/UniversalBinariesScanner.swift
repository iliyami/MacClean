import Foundation
import MacCleanKit

/// Walks `.app` bundles under a search root, asks `UniversalBinariesPolicy`
/// whether each is safe to thin, and surfaces the eligible main executables
/// as `FileItem`s.
///
/// Decision logic is pure and lives in MacCleanKit (`UniversalBinariesPolicy`);
/// this type's only job is to gather the inputs from the filesystem and
/// call into the policy.
public enum UniversalBinariesScanner {

    /// Scans `searchRoot` (default `/Applications`) for thinnable apps.
    /// Returns one `FileItem` per eligible main executable. The item's `size`
    /// is the estimated savings, not the executable's real size, so the
    /// scan-results UI shows the user a meaningful "you'll save X MB" number.
    public static func scan(
        in searchRoot: URL = URL(filePath: "/Applications"),
        host: BundleHostInfo = .current,
        policy: UniversalBinariesPolicy = UniversalBinariesPolicy()
    ) -> [FileItem] {
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(
            at: searchRoot, includingPropertiesForKeys: nil
        ) else { return [] }

        let apps = entries.filter { $0.pathExtension == "app" }
        guard !apps.isEmpty else { return [] }

        // /Applications has dozens-to-hundreds of .app bundles on a typical
        // Mac. For each candidate we Info.plist-read, lipo the main exec,
        // and (if eligible) walk every Mach-O in the bundle — sequential
        // execution turns a Smart Scan into a multi-minute affair. Fan
        // out via DispatchQueue.concurrentPerform.
        var results = [FileItem?](repeating: nil, count: apps.count)
        let lock = NSLock()
        DispatchQueue.concurrentPerform(iterations: apps.count) { i in
            let item = thinnableItem(appURL: apps[i], host: host, policy: policy)
            lock.lock()
            results[i] = item
            lock.unlock()
        }
        return results.compactMap { $0 }
    }

    /// Scans every directory macOS actually installs `.app` bundles into —
    /// `/Applications` AND the current user's `~/Applications` — and merges
    /// the results. `scan(in:)` alone only ever covered the system-wide
    /// folder; an app installed only under the user's own Applications
    /// folder (a common outcome of a drag-install or a non-admin install)
    /// was silently invisible to this scanner even though `AppDiscovery`
    /// (the Uninstaller's app lister) has always covered both.
    public static func scanAllApplicationsDirectories(
        systemApplications: URL = URL(filePath: "/Applications"),
        home: URL = MCConstants.home,
        host: BundleHostInfo = .current,
        policy: UniversalBinariesPolicy = UniversalBinariesPolicy()
    ) -> [FileItem] {
        let roots = [
            systemApplications,
            home.appending(path: "Applications"),
        ]
        var seen = Set<String>()
        var results: [FileItem] = []
        for root in roots {
            for item in scan(in: root, host: host, policy: policy) {
                let path = item.url.path(percentEncoded: false)
                guard seen.insert(path).inserted else { continue }
                results.append(item)
            }
        }
        return results
    }

    /// Gathers info for one bundle, asks the policy, and returns the
    /// associated `FileItem` (representing the whole .app to thin) if the
    /// policy says to thin.
    ///
    /// FileItem.url is the **bundle URL** (the .app dir), not the main
    /// executable — CleanActions routes universal-binary items to
    /// ThinAppBundleOperation, which walks the whole bundle for fat
    /// binaries.
    static func thinnableItem(
        appURL: URL,
        host: BundleHostInfo,
        policy: UniversalBinariesPolicy
    ) -> FileItem? {
        let infoURL = appURL.appending(path: "Contents/Info.plist")
        guard let data = try? Data(contentsOf: infoURL),
              let plist = try? PropertyListSerialization.propertyList(
                  from: data, format: nil
              ) as? [String: Any],
              let bundleID = plist["CFBundleIdentifier"] as? String,
              let executable = plist["CFBundleExecutable"] as? String
        else { return nil }

        let executableURL = appURL.appending(path: "Contents/MacOS/\(executable)")
        guard FileManager.default.fileExists(
            atPath: executableURL.path(percentEncoded: false)
        ) else { return nil }

        let isAppStore = FileManager.default.fileExists(
            atPath: appURL.appending(path: "Contents/_MASReceipt/receipt").path(percentEncoded: false)
        )

        // Use the main exec's archs as the canonical set for the policy
        // decision (SIP / Apple-system / App Store / arm64e checks are all
        // path- or bundleID-driven and don't need anything more).
        let lipoArchs = runLipoInfo(at: executableURL)
        let archSet: Set<BinaryArch> = Set(lipoArchs.compactMap(BinaryArch.init(lipoName:)))
        guard !archSet.isEmpty else { return nil }

        let info = AppBundleInfo(
            bundlePath: appURL.path(percentEncoded: false),
            bundleID: bundleID,
            isAppStore: isAppStore,
            architectures: archSet
        )

        let decision = policy.decideThinning(for: info, host: host)

        let fatBinaries: [URL]
        let dropping: Set<BinaryArch>
        // Number of architecture slices the *fat binaries we're actually
        // about to sum bytes for* carry — NOT necessarily `archSet.count`
        // (the main exec's count), since the fallback branch below sums
        // bytes across embedded binaries whose slice count can differ from
        // the main exec's.
        let originalArchCount: Int

        switch decision {
        case .thin(_, let d):
            fatBinaries = MachOWalker.fatBinaries(in: appURL)
            dropping = d
            originalArchCount = archSet.count

        case .skip(.alreadyThin):
            // The main executable already runs natively on this Mac, but
            // that says nothing about the rest of the bundle. Modern
            // Apple-Silicon-native apps routinely ship a thin arm64 main
            // exec alongside third-party frameworks (Sparkle, Electron/CEF
            // helpers, ffmpeg, …) that were never rebuilt thin — those can
            // be 10s to 100s of MB, and the old main-exec-only check
            // skipped every one of these apps as "nothing to do" without
            // ever looking. Walk the bundle for any OTHER fat Mach-O and
            // only bail out for real if none exists.
            let embeddedFat = MachOWalker.fatBinaries(in: appURL)
                .filter { $0.standardizedFileURL != executableURL.standardizedFileURL }
            var embeddedArchs: Set<BinaryArch> = []
            for binary in embeddedFat {
                embeddedArchs.formUnion(runLipoInfo(at: binary).compactMap(BinaryArch.init(lipoName:)))
            }
            let extraArchs = embeddedArchs.subtracting([host.hostArch])
            guard !extraArchs.isEmpty else { return nil }
            fatBinaries = embeddedFat
            dropping = extraArchs
            // Use the embedded binaries' own slice count (host + extras),
            // not the main exec's (which is 1 here by definition of this
            // branch) — otherwise the estimate divides by 1 and reports
            // ~100% of the framework's fat size as "savings" instead of
            // the actual ~1/N.
            originalArchCount = embeddedArchs.count

        default:
            return nil
        }

        // Sum sizes across every fat binary in the bundle for a meaningful
        // "you'll save X MB" estimate. Frameworks/XPC services often
        // contribute as much as the main exec.
        let totalFatBytes = fatBinaries.reduce(UInt64(0)) { sum, url in
            let attrs = try? FileManager.default
                .attributesOfItem(atPath: url.path(percentEncoded: false))
            return sum + ((attrs?[.size] as? NSNumber)?.uint64Value ?? 0)
        }
        let savings = UniversalBinariesPolicy.estimatedSavings(
            originalSize: totalFatBytes,
            originalArchCount: originalArchCount,
            droppingCount: dropping.count
        )

        return FileItem(
            url: appURL,
            name: L10n.tr("\(appURL.deletingPathExtension().lastPathComponent)（移除 \(dropping.map { $0.lipoName }.sorted().joined(separator: ", "))）", "\(appURL.deletingPathExtension().lastPathComponent) (drop \(dropping.map { $0.lipoName }.sorted().joined(separator: ", ")))", "\(appURL.deletingPathExtension().lastPathComponent) (удалить \(dropping.map { $0.lipoName }.sorted().joined(separator: ", ")))"),
            size: savings,
            allocatedSize: savings,
            isDirectory: true
        )
    }

    private static func runLipoInfo(at url: URL) -> [String] {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(filePath: "/usr/bin/lipo")
        process.arguments = ["-info", url.path(percentEncoded: false)]
        process.standardOutput = pipe
        process.standardError = Pipe()
        guard (try? process.run()) != nil else { return [] }
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return [] }
        let output = String(
            data: pipe.fileHandleForReading.readDataToEndOfFile(),
            encoding: .utf8
        ) ?? ""
        if let r = output.range(of: "are: ") {
            return output[r.upperBound...]
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .split(separator: " ").map(String.init)
        }
        if let r = output.range(of: "is architecture: ") {
            return [output[r.upperBound...].trimmingCharacters(in: .whitespacesAndNewlines)]
        }
        return []
    }
}
