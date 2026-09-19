// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "PopQuizCore",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [.library(name: "PopQuizCore", targets: ["PopQuizCore"])],
    targets: [
        .target(name: "PopQuizCore"),
        .testTarget(
            name: "PopQuizCoreTests",
            dependencies: ["PopQuizCore"],
            resources: [.copy("Fixtures")]
        ),
    ]
)
