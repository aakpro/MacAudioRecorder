// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "InternalSoundRecorder",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(
            name: "InternalSoundRecorder",
            targets: ["InternalSoundRecorder"]
        ),
        .library(
            name: "InternalSoundRecorderCore",
            targets: ["InternalSoundRecorderCore"]
        )
    ],
    targets: [
        .target(
            name: "InternalSoundRecorderCore",
            path: "Sources/InternalSoundRecorderCore"
        ),
        .executableTarget(
            name: "InternalSoundRecorder",
            dependencies: [
                "InternalSoundRecorderCore"
            ],
            path: "Sources/InternalSoundRecorder"
        ),
        .testTarget(
            name: "InternalSoundRecorderTests",
            dependencies: [
                "InternalSoundRecorderCore"
            ],
            path: "Tests/InternalSoundRecorderTests"
        )
    ]
)
