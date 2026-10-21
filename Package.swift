// swift-tools-version: 6.2
// GoSaver — compilé avec Swift Package Manager, sans projet Xcode.
// Le .app est assemblé par scripts/bundle.sh.
import PackageDescription

let package = Package(
    name: "GoSaver",
    defaultLocalization: "fr",
    platforms: [.macOS(.v26)],
    targets: [
        // Le moteur (scan, classement, nettoyage) : aucune interface, testable seul.
        .target(
            name: "GoSaverCore",
            path: "Sources/GoSaverCore"
        ),
        // L'appli SwiftUI.
        .executableTarget(
            name: "GoSaver",
            dependencies: ["GoSaverCore"],
            path: "Sources/GoSaver",
            resources: [.copy("Resources/Fonts")]
        ),
        // Outil de terminal pour lancer un relevé et lire les chiffres bruts.
        .executableTarget(
            name: "gosaver-survey",
            dependencies: ["GoSaverCore"],
            path: "Sources/gosaver-survey"
        ),
        .testTarget(
            name: "GoSaverCoreTests",
            dependencies: ["GoSaverCore"],
            path: "Tests/GoSaverCoreTests"
        ),
    ]
)
