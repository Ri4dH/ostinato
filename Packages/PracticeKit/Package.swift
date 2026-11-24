// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "PracticeKit",
    defaultLocalization: "en",
    platforms: [.iOS(.v26), .watchOS(.v26), .macOS(.v26)],
    products: [
        .library(name: "PracticeKit", targets: ["PracticeKit"])
    ],
    targets: [
        .target(
            name: "PracticeKit",
            resources: [.process("Resources")]
        ),
        .testTarget(
            name: "PracticeKitTests",
            dependencies: ["PracticeKit"]
        )
    ]
)
