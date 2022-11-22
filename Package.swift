// swift-tools-version:5.6

import PackageDescription

let package = Package(
    name: "SwiftOracle",
    products: [
            .library(
                name: "SwiftOracle",
                targets: ["SwiftOracle"]
            ),
    ],
    dependencies: [
        .package(url: "https://github.com/iliasaz/cocilib", from: "1.1.0"),
        .package(url: "https://github.com/apple/swift-log.git", from: "1.0.0"),
    ],
    targets: [
        .target(name: "SwiftOracle",
                dependencies: [
                    .product(name: "cocilib", package: "cocilib"),
                    .product(name: "Logging", package: "swift-log")
                ]
        )
    ]
)
