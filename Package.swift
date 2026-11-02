// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Ledge",
    platforms: [.macOS(.v14)],
    targets: [
        .target(
            name: "LedgePrivate",
            cSettings: [.unsafeFlags(["-fobjc-arc"])],
            linkerSettings: [
                .linkedFramework("Foundation"),
                .linkedFramework("CoreGraphics"),
                .linkedFramework("IOKit"),
                .unsafeFlags([
                    "-F/System/Library/PrivateFrameworks",
                    "-framework", "MultitouchSupport",
                    "-framework", "DisplayServices",
                    "-framework", "SkyLight",
                ]),
            ]
        ),
        .target(name: "LedgeCore"),
        .executableTarget(
            name: "Ledge",
            dependencies: ["LedgePrivate", "LedgeCore"]
        ),
        .testTarget(name: "LedgeCoreTests", dependencies: ["LedgeCore"]),
    ]
)
