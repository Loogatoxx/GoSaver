// swift-tools-version: 6.2
// GoSaver — compilé avec Swift Package Manager, sans projet Xcode.
// Le .app est assemblé par scripts/bundle.sh.
import PackageDescription

let package = Package(
    name: "GoSaver",
    defaultLocalization: "fr",
    platforms: [.macOS(.v26)],
    targets: [
        .executableTarget(
            name: "GoSaver",
            path: "Sources/GoSaver",
            resources: [.copy("Resources/Fonts")]
        )
    ]
)
