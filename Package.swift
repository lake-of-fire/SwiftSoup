// swift-tools-version:6.0

import PackageDescription

let package = Package(
    name: "SwiftSoup",
    // Xcode 27 no longer supports building macOS targets below 12. The Reader
    // still supports iOS 15 independently; this only raises SwiftSoup's macOS
    // package floor to the toolchain's minimum supported value.
    platforms: [.macOS(.v12), .iOS(.v13), .tvOS(.v13), .watchOS(.v6)],
    products: [
        .library(name: "SwiftSoup", targets: ["SwiftSoup"]),
        .executable(name: "SwiftSoupProfile", targets: ["SwiftSoupProfile"])
    ],
    targets: [
        .target(
            name: "SwiftSoup",
            path: "Sources"),
        .executableTarget(
            name: "SwiftSoupProfile",
            dependencies: ["SwiftSoup"],
            path: "Tools/SwiftSoupProfile"),
        .testTarget(
            name: "SwiftSoupTests",
            dependencies: ["SwiftSoup"])
    ]
)
