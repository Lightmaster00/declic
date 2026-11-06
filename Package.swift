// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Declic",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "Declic",
            path: "Sources/Declic",
            linkerSettings: [
                .linkedFramework("ScreenCaptureKit"),
                .linkedFramework("Carbon"),
                .linkedFramework("AVFoundation"),
            ]
        ),
        .testTarget(
            name: "DeclicTests",
            dependencies: ["Declic"],
            path: "Tests/DeclicTests"
        ),
    ]
)
