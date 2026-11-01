// swift-tools-version: 6.0

import PackageDescription
import Foundation

let packageDirectory = URL(fileURLWithPath: #filePath).deletingLastPathComponent().path
let appInfoPlist = "\(packageDirectory)/TimeboxStudio/App/Info.plist"
let cliInfoPlist = "\(packageDirectory)/timeboxctl/Info.plist"

let package = Package(
    name: "TimeboxStudio",
    platforms: [
        .macOS(.v13),
        .iOS(.v15)
    ],
    products: [
        .executable(name: "TimeboxStudio", targets: ["TimeboxStudio"]),
        .executable(name: "timeboxctl", targets: ["timeboxctl"]),
        .library(name: "TimeboxKit", targets: ["TimeboxKit"]),
        .library(name: "TimeboxBluetooth", targets: ["TimeboxBluetooth"])
    ],
    dependencies: [
        .package(url: "https://github.com/mattt/bestline-swift.git", revision: "823c299247f2f35a4fd9a70f7bea4c8c9edcc946")
    ],
    targets: [
        .target(name: "TimeboxCommands", dependencies: ["TimeboxKit", "TimeboxUtilities"], path: "timeboxctl/Commands"),
        .target(name: "REPLInputSupport", path: "timeboxctl/REPLInputSupport", publicHeadersPath: "include"),
        .target(name: "TimeboxREPL", dependencies: [
            .target(name: "REPLInputSupport", condition: .when(platforms: [.macOS])),
            .product(name: "Bestline", package: "bestline-swift", condition: .when(platforms: [.macOS]))
        ], path: "timeboxctl/REPL"),
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
                "TimeboxREPL",
                "TimeboxCommands",
                "TimeboxBluetooth",
                "TimeboxKit",
                "TimeboxUtilities"
            ],
            path: "timeboxctl",
            exclude: ["Info.plist", "REPL", "REPLInputSupport", "Commands"],
            linkerSettings: [
                .unsafeFlags(["-Xlinker", "-sectcreate", "-Xlinker", "__TEXT", "-Xlinker", "__info_plist", "-Xlinker", cliInfoPlist])
            ]
        ),
        .testTarget(
            name: "TimeboxStudioTests",
            dependencies: [
                "TimeboxREPL",
                "TimeboxCommands",
                "TimeboxBluetooth",
                "TimeboxKit",
                "TimeboxUtilities"
            ],
            path: "TimeboxStudioTests"
        )
    ],
    swiftLanguageModes: [.v5]
)
