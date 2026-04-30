// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "DevCleaner",
    platforms: [.macOS(.v14)],
    targets: [
        .target(
            name: "DevCleanerLib",
            path: "Sources/DevCleaner",
            sources: ["Models", "Services"]
        ),
        .executableTarget(
            name: "DevCleaner",
            dependencies: ["DevCleanerLib"],
            path: "Sources/DevCleanerApp"
        ),
        .target(
            name: "TestKit",
            path: "Sources/TestKit"
        ),
        .executableTarget(
            name: "DevCleanerTests",
            dependencies: ["DevCleanerLib", "TestKit"],
            path: "Sources/DevCleanerTests"
        ),
    ]
)
