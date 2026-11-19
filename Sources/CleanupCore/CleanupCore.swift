import Foundation

public enum Category: String, CaseIterable, Identifiable, Sendable {
    case containers, images, volumes, networks, cache
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .containers: return "已停止容器"
        case .images: return "未使用镜像"
        case .volumes: return "未使用 Volumes"
        case .networks: return "未使用网络"
        case .cache: return "构建缓存"
        }
    }
    public var icon: String {
        switch self {
        case .containers: return "shippingbox"
        case .images: return "square.stack.3d.up"
        case .volumes: return "externaldrive"
        case .networks: return "network"
        case .cache: return "hammer"
        }
    }
    public var detail: String {
        switch self {
        case .containers: return "仅退出或已失效的容器，保留运行中、暂停及尚未启动的容器。"
        case .images: return "没有被任何容器引用的镜像，包含有标签的镜像。"
        case .volumes: return "没有被任何容器引用的数据卷，包含命名卷和数据库数据。"
        case .networks: return "没有容器连接的自定义网络，保留系统默认网络。"
        case .cache: return "清理时由 Docker 判断可回收的构建缓存；后续构建可能变慢。"
        }
    }
    public var usageType: String {
        switch self {
        case .containers: return "Containers"
        case .images: return "Images"
        case .volumes: return "Local Volumes"
        case .cache: return "Build Cache"
        case .networks: return "Networks"
        }
    }
}

public struct Resource: Identifiable, Sendable {
    public let id: String
    public let name: String
    public let detail: String
    public init(id: String, name: String, detail: String = "") {
        self.id = id; self.name = name; self.detail = detail
    }
}

public struct Usage: Decodable, Sendable {
    public let type: String
    public let size: String
    public let reclaimable: String
    public let totalCount: String
    enum CodingKeys: String, CodingKey {
        case type = "Type", size = "Size", reclaimable = "Reclaimable", totalCount = "TotalCount"
    }

    fileprivate var reclaimableBytes: Int64? {
        let size = reclaimable.prefix { $0 != "(" }.trimmingCharacters(in: .whitespaces)
        let number = size.prefix { $0.isNumber || $0 == "." }
        let unit = size.dropFirst(number.count).trimmingCharacters(in: .whitespaces).lowercased()
        let units = ["b", "kb", "mb", "gb", "tb", "pb", "eb"]
        guard let value = Double(number), let exponent = units.firstIndex(of: unit) else { return nil }
        return Int64(exactly: (value * pow(1000, Double(exponent))).rounded())
    }
}

public struct Snapshot: Sendable {
    public var resources: [Category: [Resource]] = [:]
    public var usage: [Usage] = []
    public var stoppedContainerBytes: Int64?
    public var date = Date()
    public init() {}
    public subscript(_ category: Category) -> [Resource] { resources[category] ?? [] }

    public func estimatedReclaimableBytes(for categories: Set<Category>) -> Int64? {
        var total: Int64 = 0
        for category in categories where !self[category].isEmpty {
            let bytes: Int64?
            switch category {
            case .containers: bytes = stoppedContainerBytes
            case .networks: bytes = 0
            case .images, .volumes, .cache:
                bytes = usage.first { $0.type == category.usageType }?.reclaimableBytes
            }
            guard let bytes else { return nil }
            let (sum, overflow) = total.addingReportingOverflow(bytes)
            guard !overflow else { return nil }
            total = sum
        }
        return total
    }
}

public struct Container: Decodable, Sendable {
    public let id: String
    public let name: String
    public let image: String
    public let state: State
    public let mounts: [Mount]
    public struct State: Decodable, Sendable { public let status: String
        enum CodingKeys: String, CodingKey { case status = "Status" }
    }
    public struct Mount: Decodable, Sendable {
        public let type: String
        public let name: String?
        enum CodingKeys: String, CodingKey { case type = "Type", name = "Name" }
    }
    enum CodingKeys: String, CodingKey {
        case id = "Id", name = "Name", image = "Image", state = "State", mounts = "Mounts"
    }
}

public enum Safety {
    public static func stopped(_ containers: [Container]) -> [Resource] {
        containers.filter { ["exited", "dead"].contains($0.state.status) }.map {
            Resource(id: $0.id, name: $0.name.trimmingCharacters(in: CharacterSet(charactersIn: "/")), detail: $0.state.status)
        }
    }
    public static func unusedVolumes(_ names: [String], containers: [Container]) -> [Resource] {
        let used = Set(containers.flatMap(\.mounts).filter { $0.type == "volume" }.compactMap(\.name))
        return names.filter { !used.contains($0) }.map { Resource(id: $0, name: $0) }
    }
    public static func removalCommand(_ category: Category, id: String) -> [String]? {
        // No force: Docker refuses removal if a resource becomes used after scanning.
        switch category {
        case .containers: return ["container", "rm", id]
        case .images: return ["image", "rm", id]
        case .volumes: return ["volume", "rm", id]
        case .networks: return ["network", "rm", id]
        case .cache: return nil
        }
    }
}

public struct DockerError: LocalizedError {
    public let message: String
    public var errorDescription: String? { message }
}

public struct DockerClient: Sendable {
    public let executable: URL
    public init() throws {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let paths = ["/usr/local/bin/docker", "/opt/homebrew/bin/docker", "\(home)/.orbstack/bin/docker"]
        guard let path = paths.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) else {
            throw DockerError(message: "未找到 Docker CLI。请安装并启动 OrbStack，启用其命令行工具。")
        }
        executable = URL(fileURLWithPath: path)
    }

    @discardableResult public func run(_ arguments: [String]) throws -> String {
        let process = Process()
        process.executableURL = executable
        process.arguments = ["--context", "orbstack"] + arguments
        var environment = ProcessInfo.processInfo.environment
        for key in ["DOCKER_HOST", "DOCKER_CONTEXT", "DOCKER_TLS_VERIFY", "DOCKER_CERT_PATH"] {
            environment.removeValue(forKey: key)
        }
        environment["PATH"] = "/usr/local/bin:/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin"
        process.environment = environment
        let output = Pipe()
        process.standardOutput = output
        // stderr uses a file so large CLI output cannot deadlock two pipe buffers.
        let errorURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        FileManager.default.createFile(atPath: errorURL.path, contents: nil)
        let errors = try FileHandle(forWritingTo: errorURL)
        defer { try? errors.close(); try? FileManager.default.removeItem(at: errorURL) }
        process.standardError = errors
        try process.run()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        let result = String(decoding: data, as: UTF8.self)
        if process.terminationStatus != 0 {
            let error = (try? String(contentsOf: errorURL, encoding: .utf8)) ?? ""
            throw DockerError(message: "docker \(arguments.joined(separator: " "))\n\(error.isEmpty ? result : error)")
        }
        return result
    }

    private func lines(_ arguments: [String]) throws -> [String] {
        try run(arguments).split(separator: "\n").map(String.init)
    }
    private func decode<T: Decodable>(_ type: T.Type, _ text: String) throws -> T {
        try JSONDecoder().decode(type, from: Data(text.utf8))
    }
    private func containers() throws -> [Container] {
        let ids = try lines(["container", "ls", "--all", "--quiet", "--no-trunc"])
        if ids.isEmpty { return [] }
        return try decode([Container].self, run(["container", "inspect"] + ids))
    }

    private func stoppedContainerBytes(_ candidates: [Resource]) throws -> Int64? {
        guard !candidates.isEmpty else { return 0 }
        struct ContainerSize: Decodable { let SizeRw: Int64? }
        let sizes = try decode([ContainerSize].self, run(["container", "inspect", "--size"] + candidates.map(\.id)))
        let knownSizes = sizes.compactMap(\.SizeRw).filter { $0 >= 0 }
        guard knownSizes.count == candidates.count else { return nil }
        return knownSizes.reduce(0, +)
    }

    public func scan() throws -> Snapshot {
        try run(["info", "--format", "{{.ServerVersion}}"])
        var snapshot = Snapshot()
        let containers = try containers()
        snapshot.resources[.containers] = Safety.stopped(containers)
        snapshot.stoppedContainerBytes = try? stoppedContainerBytes(snapshot[.containers])
        let volumes = try lines(["volume", "ls", "--quiet"])
        snapshot.resources[.volumes] = Safety.unusedVolumes(volumes, containers: containers)

        struct Image: Decodable { let ID: String; let Repository: String; let Tag: String; let Size: String }
        let usedImages = Set(containers.map(\.image))
        let images = try lines(["image", "ls", "--all", "--no-trunc", "--format", "{{json .}}"])
            .map { try decode(Image.self, $0) }
        let grouped = Dictionary(grouping: images.filter { !usedImages.contains($0.ID) }, by: \.ID)
        snapshot.resources[.images] = grouped.map { id, images in
            let tags = images.filter { $0.Repository != "<none>" }.map { "\($0.Repository):\($0.Tag)" }
            return Resource(id: id, name: tags.isEmpty ? String(id.prefix(24)) : tags.joined(separator: ", "), detail: images.first?.Size ?? "")
        }.sorted { $0.name < $1.name }

        struct Network: Decodable {
            let Id: String; let Name: String; let Containers: [String: ContainerLink]?
            struct ContainerLink: Decodable {}
        }
        let networkIDs = try lines(["network", "ls", "--quiet", "--no-trunc"])
        let networks: [Network] = networkIDs.isEmpty ? [] : try decode([Network].self, run(["network", "inspect"] + networkIDs))
        snapshot.resources[.networks] = networks.filter {
            !["bridge", "host", "none"].contains($0.Name) && ($0.Containers ?? [:]).isEmpty
        }.map { Resource(id: $0.Id, name: $0.Name) }
        snapshot.usage = try lines(["system", "df", "--format", "{{json .}}"])
            .map { try decode(Usage.self, $0) }
        if let cache = snapshot.usage.first(where: { $0.type == Category.cache.usageType }), cache.totalCount != "0" {
            snapshot.resources[.cache] = [Resource(id: "cache", name: "Docker 默认构建缓存", detail: "可回收 \(cache.reclaimable)")]
        }
        snapshot.date = Date()
        return snapshot
    }

    public func clean(snapshot: Snapshot, categories: Set<Category>, log: @Sendable (String) -> Void) -> Int {
        var failures = 0
        for category in Category.allCases where categories.contains(category) {
            for item in snapshot[category] {
                do {
                    log("正在清理 · \(category.title) · \(item.name)")
                    if category == .containers {
                        // Check again: a previously stopped container may now be paused/running/created.
                        let current = try decode([Container].self, run(["container", "inspect", item.id]))
                        guard Safety.stopped(current).contains(where: { $0.id == item.id }) else {
                            log("跳过：容器状态已变化 · \(item.name)"); continue
                        }
                    }
                    if category == .cache {
                        log(try run(["builder", "prune", "--all", "--force"]))
                    } else if let command = Safety.removalCommand(category, id: item.id) {
                        log(try run(command))
                    }
                } catch {
                    failures += 1
                    log("未删除 · \(item.name)\n\(error.localizedDescription)")
                }
            }
        }
        return failures
    }
}
