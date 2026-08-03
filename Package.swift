// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Flow",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "Flow", targets: ["Flow"])
    ],
    dependencies: [
        .package(url: "https://github.com/FluidInference/FluidAudio.git", from: "0.12.4")
    ],
    targets: [
        .executableTarget(
            name: "Flow",
            dependencies: [
                .product(name: "FluidAudio", package: "FluidAudio")
            ],
            path: "Sources/Flow",
            swiftSettings: [
                .unsafeFlags(["-parse-as-library"])
            ]
        ),
        .testTarget(
            name: "FlowTests",
            dependencies: ["Flow"],
            path: "Tests/FlowTests"
        ),
    ]
)
