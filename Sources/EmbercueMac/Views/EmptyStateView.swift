import SwiftUI

public struct EmptyStateView: View {
    let title: String
    let description: String

    public init(title: String, description: String) {
        self.title = title
        self.description = description
    }

    public var body: some View {
        ContentUnavailableView {
            Label(title, systemImage: "sparkles")
        } description: {
            Text(description)
        }
        .padding(.vertical, 22)
    }
}
