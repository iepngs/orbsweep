import SwiftUI
import AppKit
import CleanupCore
private typealias CleanupCategory = CleanupCore.Category
// Use the property wrapper explicitly: the macOS 27 CLT SDK also exports
// a same-named State macro whose plugin is only available in full Xcode.
private typealias StoredState<Value> = SwiftUI.State<Value>

@MainActor
final class CleanupModel: ObservableObject {
    @Published var snapshot: Snapshot?
    @Published var selected: Set<CleanupCore.Category> = [.images, .networks, .cache]
    @Published var busy = false
    @Published var status = "准备扫描 OrbStack"
    @Published var error: String?
    @Published var logs = ""
    var selectionCount: Int { selected.reduce(0) { $0 + (snapshot?[$1].count ?? 0) } }

    func scan() {
        guard !busy else { return }
        busy = true; error = nil; status = "正在扫描…"
        Task {
            do {
                let result = try await Task.detached { try DockerClient().scan() }.value
                snapshot = result; status = "扫描完成"
            } catch {
                self.error = error.localizedDescription
                snapshot = nil; status = "无法连接或读取 OrbStack，请启动后重试"
            }
            busy = false
        }
    }

    func clean() {
        guard !busy, let snapshot else { return }
        let categories = selected
        busy = true; error = nil; logs = ""; status = "正在清理，请勿退出程序…"
        Task {
            do {
                let failures = try await Task.detached {
                    let client = try DockerClient()
                    return client.clean(snapshot: snapshot, categories: categories) { message in
                        DispatchQueue.main.async {
                            self.logs += message.trimmingCharacters(in: .whitespacesAndNewlines) + "\n\n"
                        }
                    }
                }.value
                self.snapshot = nil
                let fresh = try await Task.detached { try DockerClient().scan() }.value
                self.snapshot = fresh
                status = failures == 0 ? "清理完成，已重新扫描" : "清理结束，\(failures) 项未删除，请查看执行记录"
            } catch {
                self.snapshot = nil
                self.error = error.localizedDescription
                status = "执行结束，请重新扫描确认状态"
            }
            busy = false
        }
    }
}

@main
struct OrbSweepApp: App {
    @StateObject private var model = CleanupModel()
    var body: some Scene {
        WindowGroup("OrbSweep") {
            ContentView(model: model)
                .frame(minWidth: 1040, minHeight: 740)
        }
        .defaultSize(width: 1120, height: 820)
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandMenu("清理") {
                Button("重新扫描") { model.scan() }
                    .keyboardShortcut("r", modifiers: .command)
                    .disabled(model.busy)
            }
        }
    }
}

struct ContentView: View {
    @ObservedObject var model: CleanupModel
    @StoredState private var focused: CleanupCore.Category = .images
    @StoredState private var confirming = false
    @StoredState private var volumeConsent = false
    @StoredState private var showLogs = false
    private let teal = Color(red: 0.12, green: 0.65, blue: 0.57)

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            VStack(alignment: .leading, spacing: 18) {
                header
                if let error = model.error {
                    ScrollView { Text(error).font(.caption).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading) }
                        .frame(maxHeight: 90).padding(12)
                        .background(Color.red.opacity(0.09), in: RoundedRectangle(cornerRadius: 10))
                }
                usageCards
                HStack(alignment: .top, spacing: 16) {
                    categories.frame(width: 310)
                    resourceList.frame(maxWidth: .infinity, maxHeight: .infinity)
                }.frame(maxHeight: .infinity)
                if !model.logs.isEmpty {
                    DisclosureGroup("执行记录", isExpanded: $showLogs) {
                        ScrollView {
                            Text(model.logs).font(.system(size: 11, design: .monospaced))
                                .textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                        }.frame(height: 110).padding(.top, 6)
                    }
                }
                footer
            }
            .padding(26)
            .background(Color(nsColor: .windowBackgroundColor))
        }
        .task { if model.snapshot == nil { model.scan() } }
        .sheet(isPresented: $confirming) { confirmation }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 24) {
            HStack(spacing: 10) {
                Image(systemName: "sparkles.rectangle.stack.fill").font(.system(size: 28)).foregroundStyle(teal)
                Text("OrbSweep").font(.system(size: 22, weight: .bold))
            }.padding(.top, 18)
            Text("让开发空间轻一点。")
                .font(.system(size: 13)).foregroundStyle(.white.opacity(0.6))
            Label("空间清理", systemImage: "sparkles")
                .font(.system(size: 14, weight: .semibold))
                .frame(maxWidth: .infinity, alignment: .leading).padding(12)
                .background(teal.opacity(0.18), in: RoundedRectangle(cornerRadius: 10))
            Spacer()
            VStack(alignment: .leading, spacing: 12) {
                Label("清理边界", systemImage: "shield.lefthalf.filled").foregroundStyle(teal)
                    .font(.system(size: 13, weight: .semibold))
                Text("保留运行中、暂停和未启动的容器。\n\n保留容器仍在引用的数据卷与镜像。\n\n不强制删除被占用资源。")
                    .font(.system(size: 12)).foregroundStyle(.white.opacity(0.65)).lineSpacing(3)
            }
            Divider().overlay(.white.opacity(0.12))
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) { Circle().fill(teal).frame(width: 6, height: 6); Text("仅操作 OrbStack") }
                Text("Docker context · orbstack").foregroundStyle(.white.opacity(0.45)).font(.system(size: 10, design: .monospaced))
            }.font(.system(size: 12))
        }
        .padding(22).frame(width: 220).frame(maxHeight: .infinity)
        .foregroundStyle(.white)
        .background(Color(red: 0.075, green: 0.12, blue: 0.15))
    }

    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 6) {
                Text("清理未使用资源").font(.system(size: 26, weight: .bold))
                Text("先扫描，再确认。正在使用的资源由 Docker 保护。")
                    .font(.system(size: 12)).foregroundStyle(.secondary)
            }
            Spacer()
            Button { model.scan() } label: { Label("重新扫描", systemImage: "arrow.clockwise") }
                .controlSize(.large).disabled(model.busy)
        }
    }

    private var usageCards: some View {
        HStack(spacing: 10) {
            ForEach([CleanupCategory.containers, .images, .volumes, .cache]) { category in
                let type = usageType(category)
                let usage = model.snapshot?.usage.first { $0.type == type }
                VStack(alignment: .leading, spacing: 7) {
                    Label(category == .containers ? "全部容器" : category.title.replacingOccurrences(of: "未使用", with: ""), systemImage: category.icon)
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                    Text(usage?.size ?? "—").font(.system(size: 21, weight: .semibold, design: .rounded))
                    Text("Docker 可回收 \(usage?.reclaimable ?? "—")")
                        .font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1).minimumScaleFactor(0.75)
                }.frame(maxWidth: .infinity, alignment: .leading).padding(13)
                    .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 12))
            }
        }
    }

    private var categories: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("选择清理类别").font(.system(size: 13, weight: .semibold)).padding(.bottom, 3)
            ForEach(CleanupCategory.allCases) { category in
                HStack(spacing: 10) {
                    Toggle("清理\(category.title)", isOn: Binding(
                        get: { model.selected.contains(category) },
                        set: { if $0 { model.selected.insert(category) } else { model.selected.remove(category) } }
                    )).labelsHidden().toggleStyle(.checkbox).disabled(model.busy)
                    Button { focused = category } label: {
                        HStack {
                            Image(systemName: category.icon).frame(width: 22).foregroundStyle(focused == category ? teal : .secondary)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(category.title).font(.system(size: 13, weight: .medium))
                                Text(category == .volumes ? "含永久数据 · 谨慎选择" : category == .containers ? "删除容器内的可写数据" : "点击查看待清理内容")
                                    .font(.system(size: 10)).foregroundStyle(category == .volumes ? .orange : .secondary)
                            }
                            Spacer(minLength: 0)
                            Text("\(model.snapshot?[category].count ?? 0)")
                                .font(.system(size: 12, weight: .medium, design: .monospaced)).foregroundStyle(.secondary)
                        }.contentShape(Rectangle())
                    }.buttonStyle(.plain)
                }.padding(12)
                    .background(focused == category ? teal.opacity(0.09) : Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(focused == category ? teal.opacity(0.4) : .clear))
            }
            Text("删除容器后才变为空闲的资源，会在下次扫描中显示，需再次确认清理。")
                .font(.system(size: 11)).foregroundStyle(.secondary).lineSpacing(3).padding(.top, 4)
        }
    }

    private var resourceList: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack { Text(focused.title).font(.system(size: 14, weight: .semibold)); Spacer(); Text("扫描快照").font(.caption2).foregroundStyle(.secondary) }
            Text(focused.detail).font(.system(size: 11)).foregroundStyle(.secondary).lineSpacing(3).fixedSize(horizontal: false, vertical: true)
            Divider()
            if let snapshot = model.snapshot {
                if snapshot[focused].isEmpty {
                    VStack(spacing: 10) {
                        Image(systemName: "checkmark.circle").font(.system(size: 32)).foregroundStyle(teal)
                        Text("没有待清理内容").font(.system(size: 13, weight: .medium))
                        Text("此类别当前没有符合条件的资源。")
                            .font(.system(size: 11)).foregroundStyle(.secondary)
                    }.frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 0) {
                            ForEach(snapshot[focused]) { item in
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(item.name).font(.system(size: 12, weight: .medium)).textSelection(.enabled)
                                    Text(item.detail.isEmpty ? item.id : item.detail)
                                        .font(.system(size: 10, design: .monospaced)).foregroundStyle(.secondary).textSelection(.enabled)
                                }.frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 10)
                                Divider()
                            }
                        }
                    }
                }
            } else {
                Text(model.busy ? "正在读取资源…" : "扫描后查看待清理内容")
                    .foregroundStyle(.secondary).frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            if focused == .cache {
                Text("缓存以类别为单位清理，仅限 OrbStack 默认 builder。执行时的可回收量可能变化。")
                    .font(.system(size: 10)).foregroundStyle(.secondary)
            }
        }.padding(16).background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 12))
    }

    private var footer: some View {
        HStack(spacing: 12) {
            if model.busy { ProgressView().controlSize(.small) }
            VStack(alignment: .leading, spacing: 4) {
                Text(model.status).font(.system(size: 12, weight: .medium))
                if let date = model.snapshot?.date {
                    Text("最近扫描 \(date.formatted(date: .omitted, time: .standard)) · 空间统计包含共享层，不等于实际释放量")
                        .font(.system(size: 10)).foregroundStyle(.secondary)
                }
            }
            Spacer()
            Button {
                volumeConsent = false; confirming = true
            } label: { Label("清理所选（\(model.selectionCount)）", systemImage: "trash") }
                .buttonStyle(.borderedProminent).tint(teal).controlSize(.large)
                .disabled(model.busy || model.snapshot == nil || model.selectionCount == 0)
        }.padding(.top, 2)
    }

    private var confirmation: some View {
        let deletesVolumes = model.selected.contains(.volumes) && !(model.snapshot?[.volumes].isEmpty ?? true)
        return VStack(alignment: .leading, spacing: 18) {
            Label("确认永久删除", systemImage: "exclamationmark.triangle.fill")
                .font(.title2.bold()).foregroundStyle(.orange)
            Text("将清理以下扫描结果，删除操作无法撤销：").foregroundStyle(.secondary)
            ForEach(CleanupCategory.allCases.filter { model.selected.contains($0) && !(model.snapshot?[$0].isEmpty ?? true) }) { category in
                HStack { Label(category.title, systemImage: category.icon); Spacer(); Text("\(model.snapshot?[category].count ?? 0) 项") }
            }
            if deletesVolumes {
                Text("未使用不代表没有价值。未被容器引用的数据库和命名卷也会永久删除。")
                    .font(.callout).foregroundStyle(.red)
                Toggle("我确认所选未使用 volumes 中的数据可以永久删除", isOn: $volumeConsent)
            }
            if model.selected.contains(.containers) {
                Text("已停止容器内未保存到 volume 的文件也会删除。")
                    .font(.caption).foregroundStyle(.secondary)
            }
            HStack {
                Spacer()
                Button("取消") { confirming = false }.keyboardShortcut(.cancelAction)
                Button("永久删除", role: .destructive) {
                    confirming = false; showLogs = true; model.clean()
                }.disabled(deletesVolumes && !volumeConsent)
            }
        }.padding(28).frame(width: 490)
    }

    private func usageType(_ category: CleanupCategory) -> String {
        switch category {
        case .containers: return "Containers"
        case .images: return "Images"
        case .volumes: return "Local Volumes"
        case .cache: return "Build Cache"
        case .networks: return "Networks"
        }
    }
}
