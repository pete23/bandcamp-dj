// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "bandcamp-sync",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "BandcampKit", targets: ["BandcampKit"]),
        .executable(name: "bandcamp-sync", targets: ["bandcamp-sync"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.5.0"),
    ],
    targets: [
        .target(name: "BandcampKit"),
        .executableTarget(
            name: "bandcamp-sync",
            dependencies: [
                "BandcampKit",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ]
        ),
        .testTarget(
            name: "BandcampKitTests",
            dependencies: ["BandcampKit"],
            resources: [.copy("Fixtures")]
        ),
    ]
)
