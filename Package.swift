// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "KeynoteKit",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "IWAContainer", targets: ["IWAContainer"]),
        .library(name: "KeynoteSchemas", targets: ["KeynoteSchemas"]),
        .library(name: "KeynoteModel", targets: ["KeynoteModel"]),
        .library(name: "KeynoteBuilder", targets: ["KeynoteBuilder"]),
        .executable(name: "iwatool", targets: ["iwatool"]),
    ],
    dependencies: [
        .package(url: "https://github.com/weichsel/ZIPFoundation.git", from: "0.9.19"),
        // Keep in sync with the protoc-gen-swift used by scripts/gen-protos.sh —
        // a newer runtime than the generator produces deprecation warnings.
        .package(url: "https://github.com/apple/swift-protobuf.git", from: "1.38.1"),
        .package(url: "https://github.com/swiftlang/swift-docc-plugin", from: "1.4.0"),
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
        .target(
            name: "KeynoteBuilder",
            dependencies: ["KeynoteModel"],
            resources: [.copy("Resources/seed.key")]
        ),
        .executableTarget(
            name: "iwatool",
            dependencies: ["IWAContainer", "KeynoteModel", "KeynoteBuilder"]
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
        .testTarget(
            name: "KeynoteBuilderTests",
            dependencies: ["KeynoteBuilder", "KeynoteModel"],
            resources: [.copy("Resources/template.key"), .copy("Resources/template2.key"), .copy("Resources/blue.png")]
        ),
    ]
)
