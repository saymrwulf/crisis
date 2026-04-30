// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "CrisisViz",
    platforms: [.macOS(.v26)],
    targets: [
        .executableTarget(
            name: "CrisisViz",
            path: "Sources/CrisisViz",
            resources: [.copy("crisis_data.json")]
        )
    ]
)
