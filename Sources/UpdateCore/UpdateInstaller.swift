import Foundation

public enum UpdateInstaller {
    // Validate all entries before extraction. Current releases contain no symlinks.
    public static func validateArchiveEntries(_ entries: String, details: String) throws {
        let paths = entries.split(separator: "\n")
        guard !paths.isEmpty, !details.split(separator: "\n").contains(where: { $0.hasPrefix("l") }),
              paths.allSatisfy({ path in
                  let parts = path.split(separator: "/", omittingEmptySubsequences: false)
                  return (parts.first == "OrbSweep.app" || parts.first == "__MACOSX") && !parts.contains("..")
              }) else { throw UpdateError("安装包目录结构无效，已取消更新。") }
    }

    public static func validateBundle(_ app: URL, version: String) throws {
        let plistURL = app.appendingPathComponent("Contents/Info.plist")
        guard let plist = try PropertyListSerialization.propertyList(from: Data(contentsOf: plistURL), format: nil) as? [String: Any],
              plist["CFBundleIdentifier"] as? String == "local.orbsweep.app",
              plist["CFBundleShortVersionString"] as? String == version,
              plist["CFBundleExecutable"] as? String == "OrbSweep",
              FileManager.default.isExecutableFile(atPath: app.appendingPathComponent("Contents/MacOS/OrbSweep").path) else {
            throw UpdateError("下载的 App 标识或版本不匹配，已取消更新。")
        }
        if let minimum = plist["LSMinimumSystemVersion"] as? String {
            let components = minimum.split(separator: ".", omittingEmptySubsequences: false)
            let parts = components.compactMap { Int($0) }
            guard !parts.isEmpty, parts.count == components.count, parts.count <= 3, parts.allSatisfy({ $0 >= 0 }),
                  ProcessInfo.processInfo.isOperatingSystemAtLeast(OperatingSystemVersion(
                    majorVersion: parts[0], minorVersion: parts.count > 1 ? parts[1] : 0,
                    patchVersion: parts.count > 2 ? parts[2] : 0)) else {
                throw UpdateError("新版需要 macOS \(minimum) 或以上，当前 App 未被修改。")
            }
        }
        try run("/usr/bin/codesign", ["--verify", "--deep", "--strict", app.path])
    }

    public static func prepare(archive: URL, update: AvailableUpdate, staging: URL) throws -> URL {
        try update.verifyArchive(archive)
        let entries = try run("/usr/bin/zipinfo", ["-1", archive.path])
        let details = try run("/usr/bin/zipinfo", ["-l", archive.path])
        try validateArchiveEntries(entries, details: details)
        let unpacked = staging.appendingPathComponent("unpacked", isDirectory: true)
        try run("/usr/bin/ditto", ["-x", "-k", archive.path, unpacked.path])
        let app = unpacked.appendingPathComponent("OrbSweep.app", isDirectory: true)
        try validateBundle(app, version: update.version)
        return app
    }

    @discardableResult
    private static func run(_ executable: String, _ arguments: [String]) throws -> String {
        // File-backed output also handles large archive listings without filling a pipe.
        let output = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        FileManager.default.createFile(atPath: output.path, contents: nil)
        defer { try? FileManager.default.removeItem(at: output) }
        let handle = try FileHandle(forWritingTo: output)
        defer { try? handle.close() }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardOutput = handle; process.standardError = handle
        try process.run(); process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw UpdateError("安装包解压或签名验证失败，当前 App 未被修改。")
        }
        return try String(contentsOf: output, encoding: .utf8)
    }

    // Paths are positional arguments, never interpolated into executable shell code.
    // Keep the old bundle until both replacement and LaunchServices opening succeed.
    public static let replacementScript = #"""
    set -eu
    pid="$1"; target="$2"; staged="$3"; work="$4"
    backup="$work/Previous.app"
    n=0
    while /bin/kill -0 "$pid" 2>/dev/null; do
        n=$((n + 1))
        if [ "$n" -ge 60 ]; then exit 1; fi
        /bin/sleep 1
    done
    if ! /bin/mv "$target" "$backup"; then
        /usr/bin/open "$target" || true
        exit 1
    fi
    if ! /bin/mv "$staged" "$target"; then
        /bin/mv "$backup" "$target"
        /usr/bin/open "$target" || true
        exit 1
    fi
    if ! /usr/bin/open -n "$target"; then
        /bin/mv "$target" "$work/Failed.app"
        /bin/mv "$backup" "$target"
        /usr/bin/open "$target" || true
        exit 1
    fi
    /bin/rm -rf "$work"
    """#
}
