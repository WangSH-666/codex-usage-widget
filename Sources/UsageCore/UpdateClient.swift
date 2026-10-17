import Foundation

public struct ReleaseVersion: Equatable, Comparable, Sendable {
    private let components: [Int]
    public init?(_ text: String) {
        let value = text.hasPrefix("v") ? String(text.dropFirst()) : text
        let pieces = value.split(separator: ".", omittingEmptySubsequences: false)
        guard (1...4).contains(pieces.count), pieces.allSatisfy({ !$0.isEmpty && $0.allSatisfy { $0.isASCII && $0.isNumber } }) else { return nil }
        let numbers = pieces.compactMap { Int($0) }
        guard numbers.count == pieces.count else { return nil }
        var normalized = numbers
        while normalized.count > 1 && normalized.last == 0 { normalized.removeLast() }
        components = normalized
    }
    public static func < (lhs: Self, rhs: Self) -> Bool {
        for index in 0..<max(lhs.components.count, rhs.components.count) {
            let left = index < lhs.components.count ? lhs.components[index] : 0
            let right = index < rhs.components.count ? rhs.components[index] : 0
            if left != right { return left < right }
        }
        return false
    }
}

public struct ReleaseUpdate: Equatable, Sendable {
    public let version: String
    public let notes: String
    public let pageURL: URL
    public let downloadURL: URL?

    public func isNewer(than installed: String) -> Bool {
        guard let local = ReleaseVersion(installed), let remote = ReleaseVersion(version) else { return false }
        return remote > local
    }

    public static func decode(_ data: Data, statusCode: Int, architecture: String) throws -> Self {
        switch statusCode {
        case 200: break
        case 404: throw UpdateError.noRelease
        case 403, 429: throw UpdateError.rateLimited
        default: throw UpdateError.unavailable
        }
        struct Asset: Decodable { let name: String; let browser_download_url: URL }
        struct Release: Decodable {
            let tag_name: String
            let body: String?
            let html_url: URL
            let draft: Bool
            let prerelease: Bool
            let assets: [Asset]
        }
        guard let release = try? JSONDecoder().decode(Release.self, from: data),
              !release.draft, !release.prerelease, ReleaseVersion(release.tag_name) != nil,
              trusted(release.html_url, prefix: "/WangSH-666/codex-usage-widget/releases/tag/") else { throw UpdateError.invalidRelease }
        let version = release.tag_name.hasPrefix("v") ? String(release.tag_name.dropFirst()) : release.tag_name
        let assetName = "Codex-Usage-\(version)-macOS-\(architecture).zip"
        let asset = release.assets.first { $0.name == assetName && trusted($0.browser_download_url, prefix: "/WangSH-666/codex-usage-widget/releases/download/") }
        return Self(version: version, notes: release.body ?? "", pageURL: release.html_url, downloadURL: asset?.browser_download_url)
    }

    private static func trusted(_ url: URL, prefix: String) -> Bool {
        url.scheme == "https" && url.host == "github.com" && url.user == nil && url.password == nil && url.port == nil && url.path.hasPrefix(prefix)
    }
}

public enum UpdateError: LocalizedError {
    case noRelease, rateLimited, unavailable, invalidRelease
    public var errorDescription: String? {
        switch self {
        case .noRelease: return "暂时没有可用的公开版本。"
        case .rateLimited: return "GitHub 暂时限制了访问，请稍后再试。"
        case .unavailable: return "暂时无法检查更新，请检查网络后重试。"
        case .invalidRelease: return "更新信息不完整，请稍后重试或查看 GitHub 发布页。"
        }
    }
}

public struct UpdateClient {
    public static let releasePage = URL(string: "https://github.com/WangSH-666/codex-usage-widget/releases/latest")!
    public static var architecture: String {
        #if arch(arm64)
        return "arm64"
        #else
        return "x86_64"
        #endif
    }
    public init() {}
    public func latest() async throws -> ReleaseUpdate {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 15
        configuration.timeoutIntervalForResource = 20
        configuration.httpShouldSetCookies = false
        configuration.httpCookieStorage = nil
        configuration.urlCache = nil
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        var request = URLRequest(url: URL(string: "https://api.github.com/repos/WangSH-666/codex-usage-widget/releases/latest")!)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("Codex-Usage-Update-Check", forHTTPHeaderField: "User-Agent")
        do {
            let (data, response) = try await session.data(for: request)
            guard let response = response as? HTTPURLResponse else { throw UpdateError.unavailable }
            return try ReleaseUpdate.decode(data, statusCode: response.statusCode, architecture: Self.architecture)
        } catch let error as UpdateError { throw error }
        catch { throw UpdateError.unavailable }
    }
}
