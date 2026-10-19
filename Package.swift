// swift-tools-version: 5.9

import PackageDescription
import Foundation

let packageDirectory = URL(fileURLWithPath: #file).deletingLastPathComponent().path
let appInfoPlist = "\(packageDirectory)/TimeboxStudio/App/Info.plist"
let cliInfoPlist = "\(packageDirectory)/timeboxctl/Info.plist"

let package = Package(
    name: "TimeboxStudio",
    platforms: [
        .macOS(.v13),
        .iOS(.v15)
    ],
    products: [
        .executable(name: "mini-timers-prototype", targets: ["MiniTimersPrototype"]),
        .executable(name: "TimeboxStudio", targets: ["TimeboxStudio"]),
        .executable(name: "timeboxctl", targets: ["timeboxctl"]),
        .library(name: "TimeboxKit", targets: ["TimeboxKit"]),
        .library(name: "TimeboxBluetooth", targets: ["TimeboxBluetooth"])
    ],
    dependencies: [
        .package(url: "https://github.com/jpsim/Yams.git", from: "6.2.2")
    ],
    targets: [
        .executableTarget(
            name: "MiniTimersPrototype",
            dependencies: ["TimeboxBluetooth", "TimeboxKit"],
            path: "timeboxctl/MiniTimersPrototype",
            exclude: ["README.md", "packet-demo.html", "observations.json", "sources.md"]
        ),
        .target(
            name: "TimeboxCLIKit",
            dependencies: ["TimeboxBluetooth", "TimeboxKit", "TimeboxUtilities", .product(name: "Yams", package: "Yams")],
            path: "timeboxctl/Support"
        ),
        .target(
            name: "TimeboxUtilities",
            path: "TimeboxStudio/Utilities"
        ),
        .target(
            name: "TimeboxKit",
            dependencies: ["TimeboxUtilities"],
            path: "TimeboxStudio/TimeboxKit"
        ),
        .target(
            name: "TimeboxBluetooth",
            dependencies: ["TimeboxKit", "TimeboxUtilities"],
            path: "TimeboxStudio/Bluetooth",
            linkerSettings: [
                .linkedFramework("CoreBluetooth"),
                .linkedFramework("IOBluetooth", .when(platforms: [.macOS]))
            ]
        ),
        .target(
            name: "TimeboxPersistence",
            dependencies: ["TimeboxKit"],
            path: "TimeboxStudio/Persistence"
        ),
        .executableTarget(
            name: "TimeboxStudio",
            dependencies: [
                "TimeboxBluetooth",
                "TimeboxKit",
                "TimeboxPersistence",
                "TimeboxUtilities"
            ],
            path: "TimeboxStudio",
            exclude: ["App/Info.plist", "Bluetooth", "TimeboxKit", "Persistence", "Utilities"],
            sources: ["App", "UI"],
            linkerSettings: [
                .unsafeFlags(["-Xlinker", "-sectcreate", "-Xlinker", "__TEXT", "-Xlinker", "__info_plist", "-Xlinker", appInfoPlist])
            ]
        ),
        .executableTarget(
            name: "timeboxctl",
            dependencies: [
                "TimeboxCLIKit",
                "TimeboxBluetooth",
                "TimeboxKit",
                "TimeboxUtilities"
            ],
            path: "timeboxctl",
            exclude: ["Info.plist", "Support", "MiniTimersPrototype"],
            linkerSettings: [
                .unsafeFlags(["-Xlinker", "-sectcreate", "-Xlinker", "__TEXT", "-Xlinker", "__info_plist", "-Xlinker", cliInfoPlist])
            ]
        ),
        .testTarget(
            name: "TimeboxStudioTests",
            dependencies: [
                "TimeboxCLIKit",
                "TimeboxBluetooth",
                "TimeboxKit",
                "TimeboxUtilities"
            ],
            path: "TimeboxStudioTests"
        )
    ]
)
