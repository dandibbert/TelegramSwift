// swift-tools-version:5.5
import PackageDescription

let package = Package(
    name: "EnhancedMediaPlayer",
    platforms: [.macOS(.v10_13)],
    products: [.library(name: "EnhancedMediaPlayer", targets: ["EnhancedMediaPlayer"])],
    targets: [
        .target(name: "EnhancedMediaPlayer"),
        .testTarget(name: "EnhancedMediaPlayerTests", dependencies: ["EnhancedMediaPlayer"])
    ]
)
