// swift-tools-version: 6.0
import PackageDescription

// Builds with the Xcode Command Line Tools alone. Use scripts/build-app.sh to wrap the
// executable in mtts.app — macOS only shows the Motion permission prompt to an app bundle.
let package = Package(
    name: "mtts",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "mtts",
            path: "mtts",
            exclude: ["Info.plist"]),
        .testTarget(
            name: "mttsTests",
            dependencies: ["mtts"],
            path: "mttsTests"),
    ],
    swiftLanguageModes: [.v6]
)
