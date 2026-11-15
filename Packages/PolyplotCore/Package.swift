// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "PolyplotCore",
    platforms: [.iOS(.v18), .macOS(.v15)],
    products: [
        .library(name: "PolyplotCore", targets: ["PolyplotCore"]),
    ],
    targets: [
        .target(name: "PolyplotCore"),
        .testTarget(name: "PolyplotCoreTests", dependencies: ["PolyplotCore"]),
    ]
)
