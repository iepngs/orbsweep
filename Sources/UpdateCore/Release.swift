import Foundation
import CryptoKit

public struct AppVersion: Comparable, Sendable {
    private let parts: [Int]
    public init?(_ text: String) {
        let values = text.split(separator: ".", omittingEmptySubsequences: false)
        guard values.count == 3,
              values.allSatisfy({ !$0.isEmpty && $0.allSatisfy({ $0.isASCII && $0.isNumber }) }),
              values.allSatisfy({ Int($0) != nil }) else { return nil }
        parts = values.map { Int($0)! }
    }
    public static func < (lhs: Self, rhs: Self) -> Bool { lhs.parts.lexicographicallyPrecedes(rhs.parts) }
}

public struct UpdateError: LocalizedError {
    public let message: String
    public init(_ message: String) { self.message = message }
    public var errorDescription: String? { message }
}

public struct Release: Decodable, Sendable {
    public struct Asset: Decodable, Sendable {
        public let name: String
        public let browser_download_url: URL
        public let digest: String?
        public let size: Int
    }
    public let tag_name: String
    public let draft: Bool
    public let prerelease: Bool
    public let body: String?
    public let assets: [Asset]

    public func update(after current: String) throws -> AvailableUpdate? {
        guard let installed = AppVersion(current) else { throw UpdateError("无法读取当前版本，请使用打包后的 OrbSweep.app。") }
        guard !draft, !prerelease, tag_name.hasPrefix("v"),
              let latest = AppVersion(String(tag_name.dropFirst())) else {
            throw UpdateError("发布信息中的版本无效。")
        }
        guard latest > installed else { return nil }
        let version = String(tag_name.dropFirst())
        let name = "OrbSweep-\(version)-macOS-universal.zip"
        let expected = "https://github.com/iepngs/orbsweep/releases/download/\(tag_name)/\(name)"
        guard let asset = assets.first(where: { $0.name == name }),
              asset.browser_download_url.absoluteString == expected,
              asset.size > 0, asset.size <= 100_000_000,
              let digest = asset.digest, digest.hasPrefix("sha256:") else {
            throw UpdateError("新版安装包尚未准备好或缺少校验信息，请稍后再试。")
        }
        let hash = String(digest.dropFirst(7))
        guard hash.count == 64, hash.allSatisfy({ "0123456789abcdef".contains($0) }) else {
            throw UpdateError("安装包校验信息无效。")
        }
        return AvailableUpdate(version: version, notes: body ?? "", url: asset.browser_download_url, sha256: hash, size: asset.size)
    }
}

public struct AvailableUpdate: Sendable {
    public let version: String
    public let notes: String
    public let url: URL
    public let sha256: String
    public let size: Int

    public func verifyArchive(_ file: URL) throws {
        let data = try Data(contentsOf: file, options: .mappedIfSafe)
        let hash = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        guard data.count == size, hash == sha256 else {
            throw UpdateError("安装包校验失败，当前 App 未被修改。请重新检查更新。")
        }
    }
}
