import SwiftUI

public struct BrandMark: View {
    public init() {}

    public var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: AppTheme.Radius.mark, style: .continuous)
                .fill(AppTheme.ember)
            Image(systemName: "chevron.right")
                .font(AppTheme.Typography.mark)
                .foregroundStyle(AppTheme.emberForeground)
        }
        .frame(width: AppTheme.Size.mark, height: AppTheme.Size.mark)
        .accessibilityLabel("Embercue")
    }
}
