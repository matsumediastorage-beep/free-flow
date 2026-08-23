// swift-tools-version: 6.0
import PackageDescription

// The app is split into a library plus a thin executable shim on purpose.
//
// Xcode's Command Line Tools ship an incomplete swift-testing (the `Testing`
// framework is there, but `_Testing_Foundation` has no module interface) and no
// XCTest at all, so `swift test` cannot run without a full Xcode install.
// Rather than require a 10GB download to check the logic that decides whether
// you dictated or typed a capital letter, the tests are a plain executable that
// runs anywhere — see Sources/FlowTests. SwiftPM forbids depending on an
// executable target, hence FlowKit.
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
        .target(
            name: "FlowKit",
            dependencies: [
                .product(name: "FluidAudio", package: "FluidAudio")
            ],
            path: "Sources/FlowKit"
        ),
        .executableTarget(
            name: "Flow",
            dependencies: ["FlowKit"],
            path: "Sources/Flow",
            swiftSettings: [
                .unsafeFlags(["-parse-as-library"])
            ]
        ),
        .executableTarget(
            name: "FlowTests",
            dependencies: ["FlowKit"],
            path: "Sources/FlowTests"
        ),
    ]
)
