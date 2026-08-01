import Foundation

public struct EmbercueVersion: Comparable, Equatable, Sendable {
    private let components: [Int]

    public init?(_ value: String) {
        let normalized = value.hasPrefix("v") ? String(value.dropFirst()) : value
        let parts = normalized.split(separator: ".", omittingEmptySubsequences: false)
        guard !parts.isEmpty, parts.allSatisfy({ !$0.isEmpty && $0.allSatisfy(\.isNumber) }) else { return nil }
        let values = parts.compactMap { Int($0) }
        guard values.count == parts.count, values.allSatisfy({ $0 >= 0 }) else { return nil }
        components = values
    }

    public static func < (lhs: Self, rhs: Self) -> Bool {
        let width = max(lhs.components.count, rhs.components.count)
        for index in 0..<width {
            let left = index < lhs.components.count ? lhs.components[index] : 0
            let right = index < rhs.components.count ? rhs.components[index] : 0
            if left != right { return left < right }
        }
        return false
    }

    public static func == (lhs: Self, rhs: Self) -> Bool {
        !(lhs < rhs) && !(rhs < lhs)
    }
}

public enum UpdateCheckResult: Equatable, Sendable {
    case updateAvailable(version: String, releaseURL: URL)
    case upToDate
    case unavailable
}

public enum GitHubReleaseUpdateDecoder {
    public static let latestReleaseURL = URL(string: "https://api.github.com/repos/tuloong/embercue-releases/releases/latest")!

    private struct Release: Decodable {
        let tagName: String
        let htmlURL: URL

        enum CodingKeys: String, CodingKey {
            case tagName = "tag_name"
            case htmlURL = "html_url"
        }
    }

    public static func decode(data: Data, statusCode: Int, currentVersion: String) -> UpdateCheckResult {
        guard (200..<300).contains(statusCode),
              let release = try? JSONDecoder().decode(Release.self, from: data),
              release.htmlURL.scheme == "https",
              let current = EmbercueVersion(currentVersion),
              let latest = EmbercueVersion(release.tagName) else { return .unavailable }
        return current < latest ? .updateAvailable(version: release.tagName, releaseURL: release.htmlURL) : .upToDate
    }
}

@MainActor
public final class GitHubReleaseUpdateChecker {
    public init() {}

    public func check(currentVersion: String = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0", completion: @escaping @Sendable @MainActor (UpdateCheckResult) -> Void) {
        var request = URLRequest(url: GitHubReleaseUpdateDecoder.latestReleaseURL)
        request.setValue("Embercue update checker", forHTTPHeaderField: "User-Agent")
        URLSession.shared.dataTask(with: request) { data, response, _ in
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
            let result = data.map { GitHubReleaseUpdateDecoder.decode(data: $0, statusCode: statusCode, currentVersion: currentVersion) } ?? .unavailable
            Task { @MainActor in completion(result) }
        }.resume()
    }
}
