// swift-tools-version:5.5
import PackageDescription
let package = Package(
    name: "BotForumCompatibilityTests",
    platforms: [.macOS(.v10_13)],
    dependencies: [.package(path: "../../submodules/telegram-ios/submodules/TelegramApi")],
    targets: [.testTarget(name: "BotForumCompatibilityTests", dependencies: [.product(name: "TelegramApi", package: "TelegramApi")], path: "Tests")]
)
