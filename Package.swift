// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Aria",
    platforms: [
        .iOS(.v17)
    ],
    products: [
        .library(
            name: "Aria",
            targets: ["Aria"]
        ),
    ],
    dependencies: [
        // SQLite wrapper
        .package(url: "https://github.com/groue/GRDB.swift.git", from: "6.24.0"),
        // WebSocket client
        .package(url: "https://github.com/daltoniam/Starscream.git", from: "4.0.0"),
        // Keychain access
        .package(url: "https://github.com/kishikawakatsumi/KeychainAccess.git", from: "4.2.0"),
        // Google Generative AI SDK
        .package(url: "https://github.com/google-gemini/generative-ai-swift.git", from: "0.5.0"),
    ],
    targets: [
        .target(
            name: "Aria",
            dependencies: [
                .product(name: "GRDB", package: "GRDB.swift"),
                .product(name: "Starscream", package: "Starscream"),
                .product(name: "KeychainAccess", package: "KeychainAccess"),
                .product(name: "GoogleGenerativeAI", package: "generative-ai-swift"),
            ],
            path: "Aria"
        ),
        .testTarget(
            name: "AriaTests",
            dependencies: ["Aria"],
            path: "AriaTests"
        ),
    ]
)
