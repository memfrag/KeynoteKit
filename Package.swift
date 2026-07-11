// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "KeynoteKit",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "IWAContainer", targets: ["IWAContainer"]),
        .executable(name: "iwatool", targets: ["iwatool"]),
    ],
    dependencies: [
        .package(url: "https://github.com/weichsel/ZIPFoundation.git", from: "0.9.19"),
    ],
    targets: [
        .target(
            name: "IWAContainer",
            dependencies: [.product(name: "ZIPFoundation", package: "ZIPFoundation")]
        ),
        .executableTarget(
            name: "iwatool",
            dependencies: ["IWAContainer"]
        ),
        .testTarget(
            name: "IWAContainerTests",
            dependencies: ["IWAContainer"],
            resources: [.copy("Fixtures")]
        ),
    ]
)
