import Foundation

public struct SystemDisk: Sendable {
    public let name: String
    public let totalBytes: Int64
    public let availableBytes: Int64
    public var usedBytes: Int64 { totalBytes - availableBytes }
    public var usedFraction: Double {
        totalBytes > 0 ? Double(usedBytes) / Double(totalBytes) : 0
    }

    public init(name: String, totalBytes: Int64, availableBytes: Int64) {
        self.name = name
        self.totalBytes = max(0, totalBytes)
        self.availableBytes = min(max(0, availableBytes), self.totalBytes)
    }

    public static func read() throws -> SystemDisk {
        // Modern macOS boots from a sealed system volume paired with a writable
        // Data volume. Query Data so the capacity reflects where user data lives.
        let dataPath = "/System/Volumes/Data"
        let path = FileManager.default.fileExists(atPath: dataPath) ? dataPath : "/"
        let values = try URL(fileURLWithPath: path).resourceValues(forKeys: [
            .volumeNameKey, .volumeTotalCapacityKey, .volumeAvailableCapacityKey
        ])
        guard let total = values.volumeTotalCapacity, total > 0,
              let available = values.volumeAvailableCapacity else {
            throw DiskError()
        }
        return SystemDisk(name: values.volumeName ?? "启动磁盘", totalBytes: Int64(total), availableBytes: Int64(available))
    }

    private struct DiskError: LocalizedError {
        var errorDescription: String? { "暂时无法读取系统磁盘容量，请重新扫描。" }
    }
}
