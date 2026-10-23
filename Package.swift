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
        .library(name: "DBLabDomain", targets: ["DBLabDomain"]),
        .library(name: "DBLabNumeric", targets: ["DBLabNumeric"]),
        .library(name: "DBLabEnclosure", targets: ["DBLabEnclosure"]),
        .library(name: "DBLabSynthesis", targets: ["DBLabSynthesis"]),
        .library(name: "DBLabAcoustics", targets: ["DBLabAcoustics"]),
        .library(name: "DBLabMultiphysics", targets: ["DBLabMultiphysics"]),
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
        .target(
            name: "DBLabDomain",
            path: "Sources/DBLabDomain"
        ),
        .target(
            name: "DBLabNumeric",
            dependencies: [
                .product(name: "NumericCore", package: "Swift-NumericCore"),
                .product(name: "NumericCoreSparse", package: "Swift-NumericCore"),
            ],
            path: "Sources/DBLabNumeric"
        ),
        .target(
            name: "DBLabEnclosure",
            dependencies: ["DBLabDomain", "DBLabNumeric"],
            path: "Sources/DBLabEnclosure"
        ),
        .target(
            name: "DBLabSynthesis",
            dependencies: [
                "DBLabNumeric",
                .product(name: "NumericCoreOptimization", package: "Swift-NumericCore"),
            ],
            path: "Sources/DBLabSynthesis"
        ),
        .target(
            name: "DBLabAcoustics",
            dependencies: ["DBLabDomain", "DBLabNumeric"],
            path: "Sources/DBLabAcoustics"
        ),
        .target(
            name: "DBLabMultiphysics",
            dependencies: ["DBLabDomain", "DBLabNumeric"],
            path: "Sources/DBLabMultiphysics"
        ),
        // ── Main app ─────────────────────────────────────────────────────────
        .target(
            name: "DBLabCore",
            dependencies: [
                "DBLabDomain",
                "DBLabNumeric",
                "DBLabEnclosure",
                "DBLabSynthesis",
                "DBLabAcoustics",
                "DBLabMultiphysics",
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
            dependencies: [
                "DBLabCore", "DBLabDomain", "DBLabNumeric", "DBLabEnclosure", "DBLabSynthesis", "DBLabAcoustics", "DBLabMultiphysics",
                .product(name: "NumericCoreSparse", package: "Swift-NumericCore"),
            ],
            path: "Tests/db-LabTests",
            resources: [.copy("Fixtures")]
        ),
    ]
)
