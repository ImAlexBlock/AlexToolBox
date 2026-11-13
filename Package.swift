// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "AlexToolBox",
    platforms: [.macOS(.v26)],
    products: [
        .executable(name: "AlexToolBox", targets: ["AlexToolBox"]),
    ],
    targets: [
        .target(
            name: "MacouseSPI",
            path: "Sources/MacouseSPI",
            linkerSettings: [.linkedFramework("IOKit")]
        ),
        .target(
            name: "MouseControl",
            dependencies: ["MacouseSPI"],
            path: "Sources/MouseControl",
            linkerSettings: [.linkedFramework("IOKit")]
        ),
        .target(
            name: "HeadsetControl",
            path: "Sources/HeadsetControl",
            linkerSettings: [
                .linkedFramework("IOBluetooth"),
                .linkedFramework("CoreBluetooth"),
            ]
        ),
        .target(
            name: "UsageControl",
            path: "Sources/UsageControl",
            linkerSettings: [.linkedFramework("Security")]
        ),
        .executableTarget(
            name: "AlexToolBox",
            dependencies: ["MouseControl", "HeadsetControl", "UsageControl"],
            path: "Sources/AlexToolBox"
        ),
        .testTarget(
            name: "MouseControlTests",
            dependencies: ["MouseControl"],
            path: "Tests/MouseControlTests"
        ),
        .testTarget(
            name: "HeadsetControlTests",
            dependencies: ["HeadsetControl"],
            path: "Tests/HeadsetControlTests"
        ),
        .testTarget(
            name: "UsageControlTests",
            dependencies: ["UsageControl"],
            path: "Tests/UsageControlTests"
        ),
    ],
    swiftLanguageModes: [.v5]
)
