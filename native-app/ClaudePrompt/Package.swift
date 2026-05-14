// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Flowgate",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "Flowgate", targets: ["ClaudePrompt"])
    ],
    dependencies: [
        .package(url: "https://github.com/daltoniam/Starscream.git", from: "4.0.0"),
        .package(url: "https://github.com/soffes/HotKey.git", from: "0.2.0"),
    ],
    targets: [
        .executableTarget(
            name: "ClaudePrompt",
            dependencies: ["Starscream", "HotKey"],
            path: "Sources"
        )
    ]
)
