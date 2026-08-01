// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Embercue",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "EmbercueCore", targets: ["EmbercueCore"]),
        .library(name: "EmbercueMac", targets: ["EmbercueMac"]),
        .executable(name: "Embercue", targets: ["Embercue"]),
        .executable(name: "EmbercueChecks", targets: ["EmbercueChecks"])
    ],
    dependencies: [
        .package(url: "https://github.com/swiftlang/swift-markdown.git", exact: "0.8.0")
    ],
    targets: [
        .target(name: "EmbercueCore"),
        .target(name: "EmbercueMac", dependencies: [
            "EmbercueCore",
            .product(name: "Markdown", package: "swift-markdown")
        ]),
        .executableTarget(name: "Embercue", dependencies: ["EmbercueMac"]),
        .executableTarget(name: "EmbercueChecks", dependencies: ["EmbercueCore", "EmbercueMac"]),
        .testTarget(name: "EmbercueCoreTests", dependencies: ["EmbercueCore"]),
        .testTarget(name: "EmbercueMacTests", dependencies: ["EmbercueMac", "EmbercueCore"])
    ]
)
