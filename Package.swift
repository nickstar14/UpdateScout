// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "PrismPack",
    platforms: [.macOS(.v15)],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.8.0"),
    ],
    targets: [
        .executableTarget(
            name: "PrismPack",
            dependencies: [.product(name: "Sparkle", package: "Sparkle")],
            path: "Sources/PrismPack",
            swiftSettings: [.swiftLanguageMode(.v5)],
            linkerSettings: [
                // Sparkle.framework is embedded in Contents/Frameworks by build-app.sh.
                .unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"])
            ]
        ),
        .testTarget(
            name: "PrismPackTests",
            dependencies: ["PrismPack"],
            path: "Tests/PrismPackTests"
        )
    ]
)
