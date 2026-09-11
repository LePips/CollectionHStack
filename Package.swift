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
    dependencies: [
        .package(url: "https://github.com/ra1028/DifferenceKit", from: "1.3.0"),
    ],
    targets: [
        .target(
            name: "CollectionHStack",
            dependencies: [
                .product(name: "DifferenceKit", package: "DifferenceKit"),
            ]
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
