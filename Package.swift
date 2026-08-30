// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "FATHOM",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(name: "FathomKit", targets: ["FathomKit"]),
        .executable(name: "fathom", targets: ["FathomCLI"])
    ],
    targets: [
        .target(
            name: "CFathomHardware",
            linkerSettings: [
                .linkedFramework("CoreFoundation"),
                .linkedFramework("CoreVideo"),
                .linkedFramework("IOKit")
            ]
        ),
        .target(
            name: "CFathomStorage",
            publicHeadersPath: "include"
        ),
        .systemLibrary(
            name: "CSQLite",
            path: "Sources/CSQLite"
        ),
        .target(
            name: "FathomKit",
            dependencies: [
                "CFathomHardware",
                "CFathomStorage",
                "CSQLite"
            ],
            path: "FathomKit",
            resources: [
                .process("Actions/Recipes"),
                .process("Hardware/ChannelMaps")
            ],
            linkerSettings: [
                .linkedFramework("IOBluetooth"),
                .linkedFramework("CoreServices"),
                .linkedFramework("CoreWLAN"),
                .linkedFramework("SystemConfiguration")
            ]
        ),
        .executableTarget(
            name: "FathomCLI",
            dependencies: ["FathomKit"],
            path: "FathomCLI"
        ),
        .testTarget(
            name: "FathomKitTests",
            dependencies: ["CFathomHardware", "CFathomStorage", "FathomKit"],
            path: "FathomKitTests",
            // The RELEASE-GATES gate 2 recordings, captured from a real
            // Mac15,9 by `fathom capture-fixtures`. They are declared with
            // `.copy` rather than `.process` because the IOReport and IOHID
            // payloads are binary property lists exactly as the C bridge
            // emitted them: a fixture that the build re-encodes is a fixture
            // of the build, not of the hardware.
            resources: [.copy("Fixtures")]
        )
    ]
)
