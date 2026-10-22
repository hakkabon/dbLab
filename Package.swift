// swift-tools-version: 6.0
// db-Lab Package.swift
// NumericCore owns numerical factorization; DBLabCore owns loudspeaker-domain
// models and the reusable UI, while db-Lab is a deliberately thin app shell.

import PackageDescription

let package = Package(
    name: "db-Lab",

    // ── Supported platforms ──────────────────────────────────────────────────
    platforms: [
        .macOS(.v14),   // Charts, NavigationSplitView, Grid
        .iOS(.v17),     // iPadOS SwiftUI app target
    ],

    // ── Products ─────────────────────────────────────────────────────────────
    products: [
        .executable(name: "db-Lab", targets: ["db-Lab"]),
    ],

    // ── Dependencies ─────────────────────────────────────────────────────────
    dependencies: [
        .package(
            url: "https://github.com/hakkabon/Swift-NumericCore.git",
            revision: "7318e8c470079b5255142d223750c251e9b2cfe7"
        ),
    ],

    // ── Targets ──────────────────────────────────────────────────────────────
    targets: [
        // ── Main app ─────────────────────────────────────────────────────────
        .target(
            name: "DBLabCore",
            dependencies: [
                .product(name: "NumericCore", package: "Swift-NumericCore"),
                .product(name: "NumericCoreAccelerate", package: "Swift-NumericCore"),
            ],
            path: "Sources/db-Lab"
        ),
        .executableTarget(
            name: "db-Lab",
            dependencies: ["DBLabCore"],
            path: "Sources/db-LabApp"
        ),

        // ── Tests ─────────────────────────────────────────────────────────────
        .testTarget(
            name: "db-LabTests",
            dependencies: ["DBLabCore"],
            path: "Tests/db-LabTests"
        ),
    ]
)
