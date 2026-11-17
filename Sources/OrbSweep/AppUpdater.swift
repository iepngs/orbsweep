import SwiftUI
import AppKit
import UpdateCore

@MainActor
final class AppUpdater: ObservableObject {
    enum Phase {
        case idle, checking, available, current, downloading, installing, failed
    }
    @Published var presented = false
    @Published private(set) var phase: Phase = .idle
    @Published private(set) var update: AvailableUpdate?
    @Published private(set) var message = ""
    let currentVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "开发版"
    var isInstalling: Bool { phase == .downloading || phase == .installing }
    var working: Bool { phase == .checking || isInstalling }

    func check() {
        guard !working else { return }
        presented = true; phase = .checking; update = nil
        message = "正在检查 GitHub 上的最新正式版…"
        Task {
            do {
                var request = URLRequest(url: URL(string: "https://api.github.com/repos/iepngs/orbsweep/releases/latest")!)
                request.timeoutInterval = 30
                request.cachePolicy = .reloadIgnoringLocalCacheData
                request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
                request.setValue("OrbSweep/\(currentVersion)", forHTTPHeaderField: "User-Agent")
                let (data, response) = try await URLSession.shared.data(for: request)
                guard let http = response as? HTTPURLResponse else { throw UpdateError("无法读取更新服务响应。") }
                if http.statusCode == 403 || http.statusCode == 429 { throw UpdateError("GitHub 暂时限制了请求次数，请稍后重试。") }
                guard http.statusCode == 200 else { throw UpdateError("暂时无法获取新版信息（HTTP \(http.statusCode)）。") }
                let release = try JSONDecoder().decode(Release.self, from: data)
                update = try release.update(after: currentVersion)
                phase = update == nil ? .current : .available
                message = update == nil ? "你正在使用最新版本。" : "新版已准备好，安装后会自动重新打开 OrbSweep。"
            } catch { fail(error) }
        }
    }

    func install() {
        guard phase == .available, let update else { return }
        phase = .downloading; message = "正在下载 \(update.version)…"
        Task {
            var staging: URL?
            do {
                let target = Bundle.main.bundleURL.standardizedFileURL
                let parent = target.deletingLastPathComponent()
                guard target.pathExtension == "app", !target.path.hasPrefix("/Volumes/"),
                      FileManager.default.isWritableFile(atPath: target.path),
                      FileManager.default.isWritableFile(atPath: parent.path) else {
                    throw UpdateError("请先将 OrbSweep 放到你有写入权限的“应用程序”目录，再重试更新。")
                }
                // Same-volume staging makes the final rename atomic and keeps Spotlight out.
                let work = parent.appendingPathComponent(".OrbSweep-update-\(UUID().uuidString).noindex", isDirectory: true)
                try FileManager.default.createDirectory(at: work, withIntermediateDirectories: false)
                staging = work
                var request = URLRequest(url: update.url)
                request.timeoutInterval = 120
                let (download, response) = try await URLSession.shared.download(for: request)
                defer { try? FileManager.default.removeItem(at: download) }
                guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw UpdateError("下载失败，请检查网络后重试。") }
                let archive = work.appendingPathComponent("update.zip")
                try FileManager.default.moveItem(at: download, to: archive)
                message = "正在校验安装包和应用签名…"
                let app = try await Task.detached {
                    try UpdateInstaller.prepare(archive: archive, update: update, staging: work)
                }.value

                let script = work.appendingPathComponent("install.sh")
                try UpdateInstaller.replacementScript.write(to: script, atomically: true, encoding: .utf8)
                let logs = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs")
                try FileManager.default.createDirectory(at: logs, withIntermediateDirectories: true)
                let log = logs.appendingPathComponent("OrbSweep-update.log")
                FileManager.default.createFile(atPath: log.path, contents: nil)
                let handle = try FileHandle(forWritingTo: log)
                defer { try? handle.close() }
                let helper = Process()
                helper.executableURL = URL(fileURLWithPath: "/bin/sh")
                helper.arguments = [script.path, String(ProcessInfo.processInfo.processIdentifier), target.path, app.path, work.path]
                helper.standardInput = FileHandle.nullDevice
                helper.standardOutput = handle; helper.standardError = handle
                // Avoid inheriting a working directory inside the bundle being replaced.
                helper.currentDirectoryURL = parent
                try helper.run()
                staging = nil // The independent helper now owns staging and rollback.
                phase = .installing; message = "正在重启并安装新版…"
                presented = false
            } catch {
                if let staging { try? FileManager.default.removeItem(at: staging) }
                fail(error)
            }
        }
    }

    func finishInstallation() {
        // AppKit defers termination while a sheet is attached to the window.
        if phase == .installing { NSApplication.shared.terminate(nil) }
    }

    private func fail(_ error: Error) {
        phase = .failed
        message = error.localizedDescription
    }
}

struct AppUpdateView: View {
    @ObservedObject var updater: AppUpdater
    let cleanupBusy: Bool
    private let teal = Color(red: 0.12, green: 0.65, blue: 0.57)

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 14) {
                Image(systemName: updater.phase == .current ? "checkmark.circle.fill" : "arrow.down.circle.fill")
                    .font(.system(size: 36)).foregroundStyle(teal)
                VStack(alignment: .leading, spacing: 5) {
                    Text("OrbSweep 更新").font(.title2.bold())
                    Text("当前版本 \(updater.currentVersion)").font(.callout).foregroundStyle(.secondary)
                }
                Spacer()
            }
            Divider()
            if let update = updater.update {
                HStack {
                    Text("新版 \(update.version)").font(.headline)
                    Spacer()
                    Text(ByteCountFormatter.string(fromByteCount: Int64(update.size), countStyle: .file))
                        .font(.caption).foregroundStyle(.secondary)
                }
                if !update.notes.isEmpty {
                    ScrollView {
                        Text(LocalizedStringKey(update.notes)).font(.system(size: 12)).textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(height: 140).padding(12)
                    .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 10))
                }
            }
            HStack(alignment: .top, spacing: 10) {
                if updater.working { ProgressView().controlSize(.small) }
                Text(updater.message).font(.callout)
                    .foregroundStyle(updater.phase == .failed ? Color.red : Color.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack {
                Link("发布页面", destination: URL(string: "https://github.com/iepngs/orbsweep/releases")!)
                    .font(.callout)
                Spacer()
                Button(updater.phase == .available ? "稍后" : "关闭") { updater.presented = false }
                    .keyboardShortcut(.cancelAction).disabled(updater.isInstalling)
                if updater.phase == .available {
                    Button("安装并重启") { updater.install() }
                        .buttonStyle(.borderedProminent).tint(teal)
                        .disabled(cleanupBusy)
                } else if updater.phase == .failed {
                    Button("重试") { updater.check() }.buttonStyle(.borderedProminent).tint(teal)
                }
            }
        }
        .padding(26).frame(width: 450)
        .interactiveDismissDisabled(updater.isInstalling)
    }
}
