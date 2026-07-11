// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "KeynoteKit",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "IWAContainer", targets: ["IWAContainer"]),
        .library(name: "KeynoteSchemas", targets: ["KeynoteSchemas"]),
        .library(name: "KeynoteModel", targets: ["KeynoteModel"]),
        .executable(name: "iwatool", targets: ["iwatool"]),
    ],
    dependencies: [
        .package(url: "https://github.com/weichsel/ZIPFoundation.git", from: "0.9.19"),
        .package(url: "https://github.com/apple/swift-protobuf.git", from: "1.28.2"),
    ],
    targets: [
        .target(
            name: "IWAContainer",
            dependencies: [.product(name: "ZIPFoundation", package: "ZIPFoundation")]
        ),
        .target(
            name: "KeynoteSchemas",
            dependencies: [.product(name: "SwiftProtobuf", package: "swift-protobuf")]
        ),
        .target(
            name: "KeynoteModel",
            dependencies: [
                "IWAContainer",
                "KeynoteSchemas",
                .product(name: "SwiftProtobuf", package: "swift-protobuf"),
            ]
        ),
        .executableTarget(
            name: "iwatool",
            dependencies: ["IWAContainer", "KeynoteModel"]
        ),
        .testTarget(
            name: "IWAContainerTests",
            dependencies: ["IWAContainer"],
            resources: [.copy("Fixtures")]
        ),
        .testTarget(
            name: "KeynoteModelTests",
            dependencies: ["KeynoteModel"],
            resources: [.copy("Fixtures")]
        ),
    ]
)
