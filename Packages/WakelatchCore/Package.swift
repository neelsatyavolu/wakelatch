// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "WakelatchCore",
    platforms: [.iOS(.v26), .macOS(.v15)],
    products: [
        .library(name: "WakelatchCore", targets: ["WakelatchCore"]),
    ],
    targets: [
        .target(name: "WakelatchCore"),
        .target(name: "WakelatchCoreTestSupport", dependencies: ["WakelatchCore"]),
        .testTarget(name: "WakelatchCoreTests", dependencies: ["WakelatchCore", "WakelatchCoreTestSupport"]),
    ]
)
