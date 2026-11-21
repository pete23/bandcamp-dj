// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "bandcamp-sync",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "BandcampKit", targets: ["BandcampKit"]),
        .library(name: "MusicLibraryKit", targets: ["MusicLibraryKit"]),
        .executable(name: "bandcamp-sync", targets: ["bandcamp-sync"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.5.0"),
    ],
    targets: [
        .target(name: "BandcampKit"),
        .target(name: "MusicLibraryKit"),
        .executableTarget(
            name: "bandcamp-sync",
            dependencies: [
                "BandcampKit",
                "MusicLibraryKit",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ]
        ),
        .testTarget(
            name: "BandcampKitTests",
            dependencies: ["BandcampKit"],
            resources: [.copy("Fixtures")]
        ),
        .testTarget(name: "MusicLibraryKitTests", dependencies: ["MusicLibraryKit"]),
    ]
)
