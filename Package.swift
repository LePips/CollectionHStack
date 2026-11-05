// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "CollectionHStack",
    platforms: [
        .iOS(.v18),
        .tvOS(.v18),
        .macOS(.v15),
    ],
    products: [
        .library(
            name: "CollectionHStack",
            targets: ["CollectionHStack"]
        ),
    ],
    targets: [
        .target(
            name: "CollectionHStack"
        ),
        .testTarget(
            name: "CollectionHStackTests",
            dependencies: [
                "CollectionHStack",
            ]
        ),
    ],
    swiftLanguageModes: [.v5]
)
