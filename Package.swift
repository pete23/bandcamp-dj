// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "bandcamp-sync",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "BandcampKit", targets: ["BandcampKit"]),
        .library(name: "MusicLibraryKit", targets: ["MusicLibraryKit"]),
        .library(name: "SyncKit", targets: ["SyncKit"]),
        .executable(name: "bandcamp-sync", targets: ["bandcamp-sync"]),
        .executable(name: "BandcampSyncApp", targets: ["BandcampSyncApp"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.5.0"),
    ],
    targets: [
        .target(name: "BandcampKit"),
        .target(name: "MusicLibraryKit"),
        .target(name: "SyncKit", dependencies: ["BandcampKit", "MusicLibraryKit"]),
        .executableTarget(
            name: "bandcamp-sync",
            dependencies: [
                "BandcampKit",
                "MusicLibraryKit",
                "SyncKit",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ]
        ),
        .executableTarget(name: "BandcampSyncApp", dependencies: ["BandcampKit", "MusicLibraryKit", "SyncKit"]),
        .testTarget(
            name: "BandcampKitTests",
            dependencies: ["BandcampKit"],
            resources: [.copy("Fixtures")]
        ),
        .testTarget(name: "MusicLibraryKitTests", dependencies: ["MusicLibraryKit"]),
        .testTarget(name: "SyncKitTests", dependencies: ["SyncKit"]),
    ]
)
