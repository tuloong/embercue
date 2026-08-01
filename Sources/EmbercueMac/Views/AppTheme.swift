import AppKit
import SwiftUI

public enum AppTheme {
    public static let railSurface = Color(nsColor: .windowBackgroundColor).opacity(0.82)
    public static let cardSurface = Color(nsColor: .controlBackgroundColor).opacity(0.94)
    public static let selectedCardSurface = Color.accentColor.opacity(0.12)
    public static let searchSurface = Color(nsColor: .textBackgroundColor).opacity(0.96)
    public static let railMaterial: Material = .thinMaterial

    private static let emberRed = 155.0 / 255.0
    private static let emberGreen = 54.0 / 255.0
    private static let emberBlue = 10.0 / 255.0
    public static let ember = Color(red: emberRed, green: emberGreen, blue: emberBlue)
    public static let emberForeground = Color.white

    public enum Spacing {
        public static let micro: CGFloat = 3
        public static let compact: CGFloat = 6
        public static let control: CGFloat = 8
        public static let card: CGFloat = 8
        public static let rail: CGFloat = 12
        public static let section: CGFloat = 14
        public static let editorHorizontal: CGFloat = 11
        public static let topVertical: CGFloat = 14
        public static let topGap: CGFloat = 8
        public static let cardGap: CGFloat = 8
        public static let composerGap: CGFloat = 10
        public static let searchContentGap: CGFloat = 7
        public static let searchHorizontalInset: CGFloat = 11
        public static let sectionHeaderGap: CGFloat = 8
        public static let sectionContentGap: CGFloat = 18
        public static let composerHorizontalInset: CGFloat = 12
        public static let scrollTop: CGFloat = 17
    }

    public enum Radius {
        public static let mark: CGFloat = 5
        public static let control: CGFloat = 12
        public static let card: CGFloat = 15
        public static let rail: CGFloat = 24
    }

    public enum Size {
        public static let mark: CGFloat = 20
        public static let iconButton: CGFloat = 20
        public static let composerHeight: CGFloat = 64
        public static let topControlHeight: CGFloat = 30
        public static let selectionCircle: CGFloat = 18
        public static let selectionHitTarget: CGFloat = 28
        public static let composerCircle: CGFloat = 18
        public static let currentRailWidth: CGFloat = 3
        public static let previewCurrent = 4
        public static let previewSecondary = 2
        public static let sectionRuleHeight: CGFloat = 1
    }

    public enum Stroke {
        public static let circle: CGFloat = 1.2
        public static let selection: CGFloat = 2
    }

    public enum Control {
        public static let compactSize: ControlSize = .small
        public static let overflowImageScale: Image.Scale = .large
    }

    public enum Typography {
        public static let mark = Font.system(size: 9, weight: .bold)
        public static let section = Font.caption2.weight(.semibold)
        public static let sectionCount = Font.caption2.monospacedDigit()
        public static let search = Font.system(size: 13)
        public static let cardLabel = Font.caption.weight(.medium)
        public static let notice = Font.caption
        public static let emptyState = Font.callout
        public static let body = Font.body
        public static let composer = Font.system(size: 12)
    }

}
