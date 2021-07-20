// swift-tools-version:5.4

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
    ],
    targets: [
        .target(name: "SwiftOracle",
                dependencies: ["cocilib"]
        )
    ]
)
