import Foundation
import UpdateCore

enum UpdateTests {
    static func rejected(_ body: () throws -> Void) {
        do { try body(); preconditionFailure("Expected update validation failure") } catch {}
    }

    static func release(version: String = "1.0.12", url: String? = nil, hash: String? = nil, prerelease: Bool = false) throws -> Release {
        let digest = hash ?? "sha256:ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
        let json: [String: Any] = [
            "tag_name": "v\(version)", "draft": false, "prerelease": prerelease,
            "assets": [["name": "OrbSweep-\(version)-macOS-universal.zip", "size": 3, "digest": digest,
                        "browser_download_url": url ?? "https://github.com/iepngs/orbsweep/releases/download/v\(version)/OrbSweep-\(version)-macOS-universal.zip"]]
        ]
        return try JSONDecoder().decode(Release.self, from: JSONSerialization.data(withJSONObject: json))
    }

    static func run() throws {
        expect(AppVersion("1.0.10")! > AppVersion("1.0.9")!)
        expect(AppVersion("2.0.0")! > AppVersion("1.99.99")!)
        for invalid in ["", "1.2", "1.2.3.4", "1.2.-1", "1.0.2-beta", "1. 2.3", "１.0.0"] {
            expect(AppVersion(invalid) == nil)
        }
        expect(try release().update(after: "1.0.12") == nil)
        expect(try release(version: "1.0.9").update(after: "1.0.11") == nil)
        rejected { _ = try release(prerelease: true).update(after: "1.0.11") }
        rejected { _ = try release(url: "https://example.com/update.zip").update(after: "1.0.11") }
        rejected { _ = try release(hash: "sha256:invalid").update(after: "1.0.11") }
        rejected { _ = try release().update(after: "开发版") }

        let temp = FileManager.default.temporaryDirectory.appendingPathComponent("OrbSweep checks \(UUID().uuidString)")
        try FileManager.default.createDirectory(at: temp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temp) }
        let archive = temp.appendingPathComponent("archive.zip")
        let update = try release().update(after: "1.0.11")!
        try Data("abc".utf8).write(to: archive)
        try update.verifyArchive(archive)
        try Data("abd".utf8).write(to: archive)
        rejected { try update.verifyArchive(archive) }
        try Data("abcd".utf8).write(to: archive)
        rejected { try update.verifyArchive(archive) }

        try UpdateInstaller.validateArchiveEntries("OrbSweep.app/\nOrbSweep.app/Contents/MacOS/OrbSweep\n", details: "-rw-r--r--")
        for path in ["/tmp/evil", "OrbSweep.app/../../evil", "Other.app/Contents", ""] {
            rejected { try UpdateInstaller.validateArchiveEntries(path, details: "") }
        }
        rejected { try UpdateInstaller.validateArchiveEntries("OrbSweep.app/link", details: "lrwxr-xr-x link") }
        let invalidApp = temp.appendingPathComponent("Wrong.app/Contents")
        try FileManager.default.createDirectory(at: invalidApp, withIntermediateDirectories: true)
        let invalidInfo = try PropertyListSerialization.data(fromPropertyList: [
            "CFBundleIdentifier": "another.app", "CFBundleShortVersionString": "1.0.12",
            "CFBundleExecutable": "OrbSweep"
        ], format: .xml, options: 0)
        try invalidInfo.write(to: invalidApp.appendingPathComponent("Info.plist"))
        rejected { try UpdateInstaller.validateBundle(invalidApp.deletingLastPathComponent(), version: "1.0.12") }

        // Exercise the real replacement script in disposable directories. Only the
        // launcher is stubbed so checks never open or replace an installed app.
        try replacement(in: temp, stagedExists: true, launcher: "/usr/bin/true", succeeds: true)
        try replacement(in: temp, stagedExists: false, launcher: "/usr/bin/true", succeeds: false)
        try replacement(in: temp, stagedExists: true, launcher: "/usr/bin/false", succeeds: false)
        print("PASS: update versions, release validation, SHA-256, archive paths, install and rollback")
    }

    static func replacement(in root: URL, stagedExists: Bool, launcher: String, succeeds: Bool) throws {
        let directory = root.appendingPathComponent(UUID().uuidString)
        let work = directory.appendingPathComponent(".stage.noindex")
        let target = directory.appendingPathComponent("OrbSweep ' test.app")
        let staged = work.appendingPathComponent("new.app")
        try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: false)
        try Data("old".utf8).write(to: target.appendingPathComponent("version"))
        if stagedExists {
            try FileManager.default.createDirectory(at: staged, withIntermediateDirectories: false)
            try Data("new".utf8).write(to: staged.appendingPathComponent("version"))
        }
        let script = directory.appendingPathComponent("install.sh")
        try UpdateInstaller.replacementScript.replacingOccurrences(of: "/usr/bin/open", with: launcher)
            .write(to: script, atomically: true, encoding: .utf8)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = [script.path, "2147483647", target.path, staged.path, work.path]
        process.standardError = FileHandle.nullDevice
        try process.run(); process.waitUntilExit()
        expect((process.terminationStatus == 0) == succeeds)
        expect(try String(contentsOf: target.appendingPathComponent("version")) == (succeeds ? "new" : "old"))
    }
}
