// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "ClickInsight",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "ClickInsight", targets: ["ClickInsightApp"])
    ],
    targets: [
        .target(
            name: "ClickInsightCore",
            path: "Sources/ClickInsightCore"
        ),
        .executableTarget(
            name: "ClickInsightApp",
            dependencies: ["ClickInsightCore"],
            path: "Sources/ClickInsightApp"
        )
    ]
)
