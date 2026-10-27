// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "ArtCNNMetal",
    platforms: [.macOS(.v13), .iOS(.v16), .tvOS(.v16), .visionOS(.v1)],
    products: [
        .library(name: "ArtCNNMetal", targets: ["ArtCNNMetal"]),
        .executable(name: "artcnn-metal", targets: ["artcnn-metal-cli"])
    ],
    dependencies: [.package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.3.0")],
    targets: [
        .target(name: "ArtCNNMetal", exclude: ["Shaders"], resources: [.copy("Resources/THIRD-PARTY.txt")],
                plugins: [.plugin(name: "CompileArtCNNMetalShaders")]),
        .plugin(name: "CompileArtCNNMetalShaders", capability: .buildTool()),
        .executableTarget(name: "artcnn-metal-cli", dependencies: ["ArtCNNMetal", .product(name: "ArgumentParser", package: "swift-argument-parser")]),
        .testTarget(name: "ArtCNNMetalTests", dependencies: ["ArtCNNMetal"])
    ]
)
