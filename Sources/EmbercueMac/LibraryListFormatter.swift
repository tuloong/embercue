import EmbercueCore
import Foundation

public enum LibraryListFormatter {
    public static func numberedList(_ items: [LibraryItem]) -> String {
        items.enumerated().map { index, item in
            let lines = item.text.split(separator: "\n", omittingEmptySubsequences: false)
            guard let first = lines.first else { return "\(index + 1)." }
            let continuation = lines.dropFirst().map { "   \($0)" }.joined(separator: "\n")
            return "\(index + 1). \(first)" + (continuation.isEmpty ? "" : "\n\(continuation)")
        }.joined(separator: "\n")
    }
}
